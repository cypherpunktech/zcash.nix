#!/usr/bin/env bash
# The claim this repository makes about its version pins, written as something
# that can go red.
#
# WHY: helium-flake ran a version-bump cron every fifteen minutes for three
# months and shipped nothing. Every failure path deleted its branch and left the
# last-good pin in place, so "working, nothing to do" and "broken since May"
# looked identical from outside. An updater that does nothing passes silently
# forever; an assertion about how current the pins are cannot.
#
# Two claims, because there are two kinds of pin in this repo:
#
#   tag-pinned  — the package tracks upstream releases. Claim: we are on the
#                 newest release or past it, or it is younger than TAG_GRACE_DAYS
#                 (a bump we have simply not got to yet). Past it is real: the
#                 updater follows tags, and zaino tagged 0.10.1 without ever
#                 publishing it as a release, which read as 16 days behind.
#   rev-pinned  — upstream cuts no releases, so we pin a commit deliberately.
#                 Claim: that commit is younger than REV_GRACE_DAYS, or it is
#                 still the default branch head.
#
# Exits non-zero, naming every package that fails. Requires `gh` and `nix`.
set -euo pipefail

TAG_GRACE_DAYS="${TAG_GRACE_DAYS:-14}"
REV_GRACE_DAYS="${REV_GRACE_DAYS:-90}"
SYSTEM="${SYSTEM:-x86_64-linux}"

now=$(date -u +%s)
stale=()

# `date -d` is GNU, `date -jf` is BSD; this script runs on both a CI runner and
# the maintainer's mac.
epoch_of() {
	date -u -d "$1" +%s 2>/dev/null || date -u -jf %Y-%m-%dT%H:%M:%SZ "$1" +%s
}

days_since() {
	echo $(((now - $(epoch_of "$1")) / 86400))
}

# Whether version $1 is newer than $2. sort -V alone ranks 0.1.0-beta.3 above
# 0.1.0, as does nix's compareVersions; a pre-release suffix becomes `~`, which
# sort -V puts before everything, as semver puts it before the release.
newer() {
	local a b
	a=$(sed -E 's/^v//; s/^([0-9.]+)-/\1~/' <<<"$1")
	b=$(sed -E 's/^v//; s/^([0-9.]+)-/\1~/' <<<"$2")
	[ "$a" != "$b" ] && [ "$(printf '%s\n' "$a" "$b" | sort -V | tail -1)" = "$a" ]
}

# A semver pre-release suffix after the version core. The [0-9] before it keeps
# a name like zebra-utils-v10.0.1 out. update.yml uses the same expression.
PRE='[0-9]-[0-9A-Za-z.-]+$'
is_pre() {
	[[ $1 =~ $PRE ]]
}

eval_attr() {
	nix eval --raw ".#packages.${SYSTEM}.$1.$2"
}

packages=$(nix eval --json ".#packages.${SYSTEM}" --apply builtins.attrNames | jq -r '.[]')

for pkg in $packages; do
	# src.rev exists: flake.nix's `contract` refuses a package without one.
	rev=$(eval_attr "$pkg" src.rev)
	repo=$(eval_attr "$pkg" src.gitRepoUrl | sed -E 's#^https://github\.com/(.+)\.git$#\1#')

	case "$rev" in
	refs/tags/*)
		pinned="${rev#refs/tags/}"
		# The newest release we would ship: never a pre-release (rc, beta) over
		# a stable pin, whatever GitHub says. Zebra marked v7.0.0-rc.0 as its
		# latest release, unflagged, and this demanded it. A pre-release pin
		# (zallet, which has cut nothing else) still follows pre-releases.
		read -r latest published < <(
			gh api "repos/${repo}/releases?per_page=100" --jq "
				[.[] | select(.draft or .prerelease | not)
				     | select($(is_pre "$pinned" && echo true || echo false)
				              or (.tag_name | test(\"$PRE\") | not))][0]
				| \"\(.tag_name) \(.published_at)\""
		)
		if [ "$pinned" = "$latest" ]; then
			echo "ok       $pkg  $pinned (current)"
			continue
		fi
		if newer "$pinned" "$latest"; then
			echo "ok       $pkg  $pinned (past the latest release, $latest)"
			continue
		fi
		age=$(days_since "$published")
		if [ "$age" -lt "$TAG_GRACE_DAYS" ]; then
			echo "ok       $pkg  $pinned -> $latest available, ${age}d old (within ${TAG_GRACE_DAYS}d grace)"
		else
			echo "STALE    $pkg  $pinned -> $latest, released ${age}d ago"
			stale+=("$pkg ($pinned -> $latest, ${age}d)")
		fi
		;;
	*)
		head=$(gh api "repos/${repo}/commits/HEAD" --jq .sha)
		if [ "$rev" = "$head" ]; then
			echo "ok       $pkg  ${rev:0:12} (branch head)"
			continue
		fi
		committed=$(gh api "repos/${repo}/commits/${rev}" --jq .commit.committer.date)
		age=$(days_since "$committed")
		if [ "$age" -lt "$REV_GRACE_DAYS" ]; then
			echo "ok       $pkg  ${rev:0:12}, ${age}d old (within ${REV_GRACE_DAYS}d grace)"
		else
			echo "STALE    $pkg  ${rev:0:12} is ${age}d old; head is ${head:0:12}"
			stale+=("$pkg (${rev:0:12}, ${age}d old)")
		fi
		;;
	esac
done

if [ ${#stale[@]} -gt 0 ]; then
	echo
	echo "${#stale[@]} package(s) behind upstream:" >&2
	printf '  %s\n' "${stale[@]}" >&2
	echo "The update workflow should have bumped these. Check that it is still running." >&2
	exit 1
fi

echo
echo "All $(wc -w <<<"$packages" | tr -d ' ') pins current."

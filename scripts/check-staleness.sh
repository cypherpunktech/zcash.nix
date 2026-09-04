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
#                 newest release, or that release is younger than TAG_GRACE_DAYS
#                 (a bump we have simply not got to yet).
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
		read -r latest published < <(
			gh api "repos/${repo}/releases/latest" --jq '"\(.tag_name) \(.published_at)"'
		)
		if [ "$pinned" = "$latest" ]; then
			echo "ok       $pkg  $pinned (current)"
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

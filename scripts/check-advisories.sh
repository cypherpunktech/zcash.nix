#!/usr/bin/env bash
# Known-vulnerable dependencies, as a claim that can go red.
#
# A package here compiles a few hundred crates that nobody in this repository
# reads. When one of them gets an advisory, the pin is unchanged, the build is
# green, the smoke check passes -- nothing in the other gates can notice. This
# asserts the outcome: no lockfile we build from names a version with a known
# vulnerability, EXCEPT the ones written down in scripts/advisories-accepted.txt.
#
# That exception is the difference between a gate and a decoration. Every
# advisory here is in a dependency of upstream's own committed lockfile, so the
# only fix is upstream shipping a bump; a job that is red every day for a month
# is one nobody reads on the day something new appears. So the known set is
# recorded with a reason and a date, and this goes red when the set CHANGES:
# a new advisory, or an acceptance that has run out of time and must be looked
# at again. An acceptance is not a fix, it is a decision with an expiry.
#
# The claim is about what ships, so the lockfile audited is the one each built
# derivation vendors: its src at its sourceRoot, through passthru.parts for a
# join (zallet builds two). A source tree also carries lockfiles for fuzzers,
# test tools and backends this repository does not build, and an advisory in
# those is not an advisory in the binary. Rust: cargo-audit over that lockfile,
# vulnerabilities only -- unmaintained and unsound warnings are printed as a
# reason to look, never a reason to fail. Go: govulncheck over the built
# binary, counting only findings that reach a vulnerable SYMBOL, which is the
# sharper question than "is the module listed".
#
# Exits non-zero naming every advisory that is not accepted. Requires `nix`,
# `cargo-audit`, `govulncheck`, `jq`; the advisory databases are fetched from
# the network, which is why this is a script and not a derivation.
set -euo pipefail

SYSTEM="${SYSTEM:-$(nix config show system)}"
ACCEPTED="${ACCEPTED:-scripts/advisories-accepted.txt}"
today=$(date -u +%F)

# The accepted set, split by whether it still stands today. String comparison
# is date comparison for ISO-8601, which is why the file is written that way.
declare -A accept_why accept_until expired_on
while read -r id expires why; do
	case "$id" in '' | \#*) continue ;; esac
	if [[ $expires < $today ]]; then
		expired_on["$id"]="$expires"
	else
		accept_why["$id"]="$why"
		accept_until["$id"]="$expires"
	fi
done <"$ACCEPTED"

# Where each advisory was reported, so the failure names the package. A
# package is named once however many of its lockfiles or crate versions carry
# the same advisory: the reader wants to know where to look, not how often.
declare -A seen_in
note() {
	case " ${seen_in[$1]:-} " in *" $2, "* | *" $2 "*) return ;; esac
	seen_in["$1"]="${seen_in[$1]:+${seen_in[$1]}, }$2"
}

packages=$(nix eval --json ".#packages.${SYSTEM}" --apply builtins.attrNames | jq -r '.[]')

for pkg in ${PACKAGES:-$packages}; do
	src=$(nix build --no-link --print-out-paths ".#packages.${SYSTEM}.${pkg}.src")

	if [ -e "$src/go.mod" ]; then
		bin=$(nix build --no-link --print-out-paths ".#packages.${SYSTEM}.${pkg}")/bin/$(nix eval --raw ".#packages.${SYSTEM}.${pkg}.meta.mainProgram")
		echo "== $pkg  govulncheck ${bin#/nix/store/*-}"
		# JSON rather than the text report: a finding whose trace reaches a
		# function is one whose vulnerable symbol is actually linked, which is
		# what the text report calls a Symbol Result. govulncheck exits 0 in
		# this mode whatever it finds, so the findings are the verdict.
		report=$(govulncheck -mode=binary -format json "$bin")
		summaries=$(jq -r 'select(.osv) | .osv | "\(.id)\t\(.summary // .details | split("\n")[0])"' <<<"$report" | sort -u)
		for id in $(jq -r 'select(.finding) | .finding | select(.trace[0].function != null) | .osv' <<<"$report" | sort -u); do
			note "$id" "$pkg"
			printf '   %s  %s\n' "$id" "$(grep -m1 "^${id}	" <<<"$summaries" | cut -f2)"
		done
		continue
	fi

	# One directory per built derivation, relative to src; "." for the root,
	# because an empty word would vanish in the shell and take zallet's main
	# lockfile with it.
	roots=$(nix eval --raw ".#packages.${SYSTEM}.${pkg}" --apply '
		p: builtins.concatStringsSep " " (map (
			d: let sub = builtins.replaceStrings [ (d.src.name + "/") ] [ "" ] (d.sourceRoot or ""); in
			if sub == "" then "." else sub
		) (p.parts or [ p ]))')
	for root in $roots; do
		lock="$src/$root/Cargo.lock"
		if [ ! -e "$lock" ]; then
			echo "UNAUDITABLE  $pkg builds from $root, which has neither Cargo.lock nor go.mod" >&2
			note "no-lockfile-in-$root" "$pkg"
			continue
		fi
		echo "== $pkg  cargo audit ${lock#"$src"/}"
		# cargo-audit exits non-zero when it finds something and still writes
		# its report, so the exit code says nothing the report does not.
		report=$(cargo audit --file "$lock" --json 2>/dev/null || true)
		jq -e 'has("vulnerabilities")' >/dev/null <<<"$report" || {
			echo "FAILED   $pkg  cargo audit produced no report for $root" >&2
			note "cargo-audit-failed-in-$root" "$pkg"
			continue
		}
		while IFS=$'\t' read -r id crate version title; do
			[ -n "$id" ] || continue
			note "$id" "$pkg"
			printf '   %s  %s %s  %s\n' "$id" "$crate" "$version" "$title"
		done < <(jq -r '.vulnerabilities.list[] | [.advisory.id, .package.name, .package.version, .advisory.title] | @tsv' <<<"$report")
		# Unmaintained, unsound, yanked: worth knowing, never a failure.
		jq -r '.warnings | to_entries[] | "   (\(.key)) " + ([.value[] | .package.name] | join(", "))' <<<"$report" |
			grep -v '() $' || true
	done
done

# Three questions about the set, in the order that matters.
new=()
for id in "${!seen_in[@]}"; do
	[ -n "${accept_why[$id]:-}" ] && continue
	if [ -n "${expired_on[$id]:-}" ]; then
		new+=("$id (${seen_in[$id]}): accepted until ${expired_on[$id]}, which has passed -- has upstream shipped a fix?")
	else
		new+=("$id (${seen_in[$id]}): new since the accepted set was last reviewed")
	fi
done

# An acceptance for something nobody reports any more is a stale claim in the
# tree, and only a scan of everything can say so: with PACKAGES set, "not
# reported" means "not by this one".
dead=()
if [ -z "${PACKAGES:-}" ]; then
	for id in "${!accept_why[@]}"; do
		[ -z "${seen_in[$id]:-}" ] && dead+=("$id")
	done
fi

echo
if [ ${#dead[@]} -gt 0 ]; then
	echo "Fixed upstream, or no longer reachable; delete from $ACCEPTED: ${dead[*]}"
fi

if [ ${#new[@]} -gt 0 ]; then
	echo "${#new[@]} advisory/advisories that are not accepted:" >&2
	printf '  %s\n' "${new[@]}" >&2
	echo >&2
	echo "The fix is upstream: a dependency bump in their next release. If there is" >&2
	echo "nothing to do but wait, add the id to $ACCEPTED with a date to look again." >&2
	exit 1
fi

echo "No unaccepted advisories in $(wc -w <<<"${PACKAGES:-$packages}" | tr -d ' ') package(s)."
for id in "${!accept_why[@]}"; do
	printf 'accepted %s until %s  %s\n' "$id" "${accept_until[$id]}" "${accept_why[$id]}"
done

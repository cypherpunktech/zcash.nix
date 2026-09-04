#!/usr/bin/env bash
# Re-run every fetcher this repository wrote a hash for, and fail if the
# bytes it fetches today are not the bytes the hash claims.
#
# A fixed-output derivation's store path depends on its hash alone. Bump a
# tag and leave the hash, or paste a sibling's, and every store that has that
# path -- yours, the cache, every runner after the first -- calls it valid and
# never runs the fetcher: green CI, old source. Only `--rebuild` executes a
# fetcher whose output already exists. repro.yml rebuilds the package; its
# sources are inputs there and are never re-fetched. This is the other half of
# that claim: the pinned source is still what upstream serves.
#
# Only hashes typed into packages/ are checked -- the ones that are ours to get
# wrong. The closure also holds nixpkgs' own fetchers, which Hydra re-runs.
# Nothing is memoised: a verdict is about today, and twenty downloads a day is
# the price of it.
#
# Exits non-zero naming every hash that does not re-fetch. Requires `nix`, `jq`.
set -euo pipefail

SYSTEM="${SYSTEM:-$(nix config show system)}"
ours=$(grep -rhoE 'sha256-[A-Za-z0-9+/]{43}=' packages/ | sort -u)
log=$(mktemp)
trap 'rm -f "$log"' EXIT
failed=()

for pkg in ${PACKAGES:-$(nix eval --json ".#packages.${SYSTEM}" --apply builtins.attrNames | jq -r '.[]')}; do
	# Where a fixed output's hash sits depends on the fetcher: fetchzip's
	# `source` carries it on the output, fetchCargoVendor's staging in env.
	# The keys are store basenames, hence the prefix.
	drvs=$(nix derivation show -r ".#packages.${SYSTEM}.\"${pkg}\"" | jq -r --arg ours "$ours" '
		($ours | split("\n")) as $h
		| .derivations | to_entries[]
		| (.value.outputs.out.hash // .value.env.outputHash) as $x
		| select($x != null and ($h | index($x)) != null)
		| "/nix/store/" + (.key | ltrimstr("/nix/store/"))')
	for drv in $drvs; do
		name=${drv#/nix/store/*-}
		name=${name%.drv}
		# The output must be valid before --rebuild has anything to compare
		# against; from the cache if it is there, fetched if not.
		nix build --no-link "${drv}^*"
		if nix build --no-link --rebuild "${drv}^*" >"$log" 2>&1; then
			echo "refetched  $pkg  $name"
		elif grep -q 'hash mismatch in fixed-output derivation' "$log"; then
			grep -E 'specified:|got:' "$log" >&2 || true
			failed+=("$pkg $name: what upstream serves no longer matches the hash in packages/$pkg")
		else
			tail -5 "$log" >&2
			failed+=("$pkg $name: the fetch itself failed, which is no verdict")
		fi
	done
done

if [ ${#failed[@]} -gt 0 ]; then
	echo >&2
	echo "${#failed[@]} pinned source(s) that do not re-fetch to their hash:" >&2
	printf '  %s\n' "${failed[@]}" >&2
	echo "A hash that does not re-fetch is a source nobody has seen. Find out why before bumping." >&2
	exit 1
fi

#!/usr/bin/env bash
# Known-vulnerable dependencies, as a claim that can go red.
#
# A package here compiles a few hundred crates that nobody in this repository
# reads. When one of them gets a RustSec advisory, the pin is unchanged, the
# build is green, the smoke check passes -- nothing in the existing gates can
# notice. This asserts the outcome: no lockfile we build from names a crate
# version with a known vulnerability. It goes red the day the advisory is
# published, whether or not anyone read the announcement.
#
# The claim is about what ships, so the lockfile audited is the one each
# built derivation vendors: its src at its sourceRoot, through passthru.parts
# for a join (zallet builds two). A source tree also carries lockfiles for
# fuzzers, test tools and backends this repository does not build, and an
# advisory in those is not an advisory in the binary. Rust: cargo-audit over
# that lockfile. Go: govulncheck over the built binary, which asks the sharper
# question -- not "is the module listed" but "is the vulnerable symbol linked".
#
# Unmaintained-crate warnings are printed and do not fail: they are a reason
# to look, not a vulnerability. Exits non-zero naming every failing package.
# Requires `nix`, `cargo-audit`, `govulncheck`; the advisory database is
# fetched from the network, which is why this is a script and not a derivation.
set -euo pipefail

SYSTEM="${SYSTEM:-$(nix config show system)}"

packages=$(nix eval --json ".#packages.${SYSTEM}" --apply builtins.attrNames | tr -d '[]"' | tr ',' ' ')
failed=()

for pkg in ${PACKAGES:-$packages}; do
	src=$(nix build --no-link --print-out-paths ".#packages.${SYSTEM}.${pkg}.src")
	if [ -e "$src/go.mod" ]; then
		bin=$(nix build --no-link --print-out-paths ".#packages.${SYSTEM}.${pkg}")/bin/$(nix eval --raw ".#packages.${SYSTEM}.${pkg}.meta.mainProgram")
		echo "== $pkg  govulncheck ${bin#/nix/store/*-}"
		govulncheck -mode=binary "$bin" || failed+=("$pkg")
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
			echo "UNCHECKABLE  $pkg builds from $root, which has neither Cargo.lock nor go.mod" >&2
			failed+=("$pkg (unauditable)")
			continue
		fi
		echo "== $pkg  cargo audit ${lock#"$src"/}"
		cargo audit --file "$lock" || failed+=("$pkg (${lock#"$src"/})")
	done
done

if [ ${#failed[@]} -gt 0 ]; then
	echo
	echo "${#failed[@]} package(s) with known-vulnerable dependencies:" >&2
	printf '  %s\n' "${failed[@]}" >&2
	echo "The fix is upstream: a dependency bump in the next release. Until then this stays red, on purpose." >&2
	exit 1
fi

echo
echo "No known-vulnerable dependencies in $(wc -w <<<"${PACKAGES:-$packages}" | tr -d ' ') package(s)."

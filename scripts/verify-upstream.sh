#!/usr/bin/env bash
# Does the source we build come from the maintainer, or merely from GitHub?
#
# A pinned hash makes the source immutable from the moment it was recorded; it
# says nothing about whether that moment recorded the right bytes. The only
# thing that can is a signature by someone who is not GitHub. Where an
# upstream signs its release tags, this closes the loop end to end:
#
#   the pinned public key   verifies   the tag's signature
#   the tag's tree          hashes to  the exact src.outputHash we build from
#
# so a rewritten tag, a substituted tarball, or a compromised forge all fail
# here, in a check that a user of this repository can rerun in a minute.
#
# A package declares what upstream signs with `passthru.upstreamSigners`, an
# ssh allowed-signers file kept next to the derivation (see packages/zinder).
# Adding a key is a reviewed change to this repository, never a download at
# check time: the first pin trusts GitHub's key listing once, every later one
# trusts the previous reviewer. Packages that declare nothing are reported as
# unsigned and do not fail -- that is upstream's state, not a regression --
# and the list of them is the honest answer to "which sources are verified".
#
# Exits non-zero if any declared signature fails to verify or any verified
# tag's tree differs from the pinned source. Requires `nix`, `git`, `ssh-keygen`.
set -euo pipefail

SYSTEM="${SYSTEM:-$(nix config show system)}"

eval_attr() {
	nix eval --raw ".#packages.${SYSTEM}.$1.$2"
}

packages=$(nix eval --json ".#packages.${SYSTEM}" --apply builtins.attrNames | tr -d '[]"' | tr ',' ' ')
failed=()
unsigned=()
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for pkg in ${PACKAGES:-$packages}; do
	if ! signers=$(eval_attr "$pkg" upstreamSigners 2>/dev/null); then
		unsigned+=("$pkg")
		continue
	fi
	rev=$(eval_attr "$pkg" src.rev)
	tag="${rev#refs/tags/}"
	if [ "$tag" = "$rev" ]; then
		echo "FAIL     $pkg  declares signers but is pinned to commit ${rev:0:12}, not a tag" >&2
		failed+=("$pkg (not tag-pinned)")
		continue
	fi
	url=$(eval_attr "$pkg" src.gitRepoUrl)
	expected=$(eval_attr "$pkg" src.outputHash)

	# init + fetch rather than clone --branch: the latter warns about every
	# annotated tag and lectures about detached HEAD, and this needs one object.
	repo="$work/$pkg"
	git init --quiet "$repo"
	git -C "$repo" fetch --quiet --depth 1 "$url" tag "$tag"
	if ! verdict=$(git -C "$repo" -c gpg.ssh.allowedSignersFile="$signers" verify-tag --raw "$tag" 2>&1); then
		echo "FAIL     $pkg  $tag: ${verdict}" >&2
		failed+=("$pkg ($tag signature)")
		continue
	fi
	# The signed object is the tag; what we build is its tree. Bridge the two
	# the way fetchFromGitHub does: export the tree, hash it as nix would.
	mkdir "$repo.tree"
	git -C "$repo" archive --format=tar "$tag" | tar -x -C "$repo.tree"
	actual=$(nix hash path --sri "$repo.tree")
	if [ "$actual" != "$expected" ]; then
		echo "FAIL     $pkg  $tag verifies, but its tree is $actual and the pinned source is $expected" >&2
		failed+=("$pkg ($tag tree mismatch)")
		continue
	fi
	echo "verified $pkg  $tag  $(sed -n 's/^Good "git" signature for \(.*\) with \([A-Z0-9]*\) key \(.*\)$/\1 \2 \3/p' <<<"$verdict")"
done

for pkg in "${unsigned[@]}"; do
	echo "unsigned $pkg  upstream publishes nothing that authenticates its source"
done

if [ ${#failed[@]} -gt 0 ]; then
	echo
	echo "${#failed[@]} package(s) whose source is NOT what the maintainer signed:" >&2
	printf '  %s\n' "${failed[@]}" >&2
	echo "Do not bump, do not build. Find out why before anything else." >&2
	exit 1
fi

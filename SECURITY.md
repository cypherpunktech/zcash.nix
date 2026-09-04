# Security

These are packaging definitions. They compile upstream source; they are not an audit of it. Installing
from here means trusting this repository's maintainers and the binary cache in addition to the upstream
projects. That is more trust than `cargo install`, not less, justified only because the alternative is
unpinned, unreproducible, hand-installed binaries.

## Guaranteed

- **Content pinning.** Every package pins a tag or commit and the SHA-256 of the source tree. A moved
  tag or altered tarball fails the build; it never builds something else quietly.
- **Dependency pinning.** `cargoHash` over the committed `Cargo.lock`; `vendorHash` over `go.sum`.
- **No impurity.** No `--impure`, no unpinned `fetchTarball`, no host tools, no import-from-derivation.
  Builds run in the sandbox on every platform: CI sets `sandbox = true` with no fallback, macOS included,
  where Nix's own default is off.
- **Pinned sources still fetch.** Every hash written in `packages/` is re-fetched daily; a moved tag or
  a changed tarball is red the next morning, not at the next cache miss.
- **The cache serves what CI built.** After every push to `main`, every package's store path is checked
  to be in the cache, signed with this repository's key.
- **Pinned CI.** Every action pinned by commit SHA, least-privilege `permissions:`,
  `persist-credentials: false`.
- **Reproducibility is measured.** `repro.yml` rebuilds packages N times and fails on any byte of
  difference. On macOS stock nixpkgs Rust binaries do not reproduce; `flake.nix` closes the three
  channels through which the random build directory reaches the binary.
- **Bumps merge only when green.** A version bump merges itself after the full matrix, the VM tests,
  and the checks below pass on its branch. Nothing lands on `main` without that check.

## Not guaranteed

- **Source authenticity, except where upstream signs.** Pinning makes source immutable from then on;
  it does not prove the bytes were the maintainer's. Where a release tag is signed, `verify-upstream.sh`
  checks the signature against a key pinned in the repository and hashes the signed tree to the exact
  source built. Today: zinder, lightwalletd-rs. The others sign binaries or nothing; the daily `trust`
  run lists them as unsigned.
- **Vulnerable dependencies are reported, not patched.** cargo-audit and govulncheck run daily over
  what each build vendors. Red until upstream ships the bump. Check the `trust` workflow before running
  a node from here.
- **Upstream test suites are not run.** They need live peers and chain state. Each binary is executed
  once (`checks.smoke-*`) and each module is booted in a VM; neither is a correctness test.
- **Build-time code execution.** Building runs every crate's `build.rs`. Unavoidable, hence the sandbox.

## Binary cache

`cypherpunktech.cachix.org`, key `cypherpunktech.cachix.org-1:WKo2WboMVH8HUtCKNsSFx31YQibaJ2eocruFvAzWgA4=`.
Without it everything builds from source.

**What is in it.** Every package's outputs, the fixed-output derivations they are built from (source
trees, vendored crates, Go modules), the smoke-check outputs, and the NixOS system closures of the VM
tests. Nothing `cache.nixos.org` already serves. Images and devshells are not.

**Who writes.** CI, on pushes to `main`, and nothing else: pull requests and forks get no token, and
there is no maintainer push path. A run pushes only if every package's licence permits redistribution,
all or nothing, because a store path cannot be kept out of a cache once anything referencing it is
pushed.

**Who signs.** Cachix holds the signing key; maintainers hold only the push token. A stolen token means
signed poison until it is revoked, and consumers cannot tell, because the public key does not change.
Revocation: rotate the token in Cachix and in the repository's secrets, then re-push every current
output from a clean CI run, because paths pushed during the window look like any other. There is no key
rotation.

**What it means.** A binary in the cache was built by CI; it has not necessarily passed its smoke test,
because the push happens after the job whatever its result. The `check` run is the record. To use the
cache without trusting it: `nix build --rebuild .#zebra` against the substituted path, or compare a local
build's `NarHash` with `curl https://cypherpunktech.cachix.org/<hash>.narinfo`. `repro.yml` is the
maintainers doing the same, monthly.

## Reporting

A problem in this repository's packaging: open a security advisory here. A vulnerability in a
packaged project: report it upstream, a public issue here would only broadcast it.

| Project | Report to |
|---|---|
| zebra, zinder | https://github.com/ZcashFoundation/zebra/security |
| zallet, lightwalletd | https://github.com/zcash/zallet/security |
| zaino | https://github.com/zingolabs/zaino |
| zakura | https://github.com/zakura-core/zakura |
| ztreamer | https://github.com/distractedm1nd/ztreamer |
| lightwalletd-rs | https://github.com/jpgonzalezra/lightwalletd-rs |
| zpay | https://github.com/gustavovalverde/zpay |

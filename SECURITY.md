# Security

## What this repository is, in trust terms

These are packaging definitions. They compile upstream source; they are not an
audit of it, and nothing here makes an unsafe program safe. The MIT licence
covers the Nix code only — each packaged project keeps its own licence and its
own security posture.

Be clear-eyed about what that means for a Zcash toolchain: installing from here
means trusting **this repository's maintainers, in addition to** the upstream
projects, and the binary cache below on top of that. That is strictly more trust
than `cargo install` from upstream, not less. It is worth it only because the
alternative is unpinned, unreproducible, hand-installed binaries.

## What is actually guaranteed

- **Content pinning.** Every package pins a tag or commit *and* the SHA-256 of
  the extracted source tree. If upstream moves a tag or a CDN serves different
  bytes, the hash mismatches and the build fails loudly. It does not build
  something else quietly.
- **Dependency pinning.** Rust dependencies come from a `cargoHash` over the
  committed `Cargo.lock`; Go from a `vendorHash` over `go.sum`. A dependency
  substituted underneath us changes that hash.
- **No impurity.** No `--impure`, no unpinned `fetchTarball`, no host tools
  reached from a derivation. Builds run in the Nix sandbox.
- **Pinned CI actions.** Every GitHub Action is pinned by full commit SHA, not
  tag; tags are mutable. Workflows declare least-privilege `permissions:` and
  check out with `persist-credentials: false`.
- **No auto-merge.** Version bumps open a pull request and wait for a human. A
  consensus node's version is not something a bot should land unread.

## What is NOT guaranteed

- **Source authenticity is verified only where upstream signs it.** Pinning
  makes the source *immutable from then on*; it does not prove the bytes were
  the maintainer's to begin with. Where an upstream signs its release tags,
  `scripts/verify-upstream.sh` checks that the pinned tag carries the
  maintainer's signature (key pinned in `packages/<name>/allowed_signers`,
  changed only by a reviewed commit) and that the signed tree hashes to the
  exact source built here; it runs daily and before every version bump. Today
  that covers zinder. zebra, zakura and zallet sign only their release
  *binaries*; zaino and lightwalletd sign nothing. The daily run lists them as
  unsigned, which is the state of the ecosystem, not a claim about it.
- **Known-vulnerable dependencies are reported, not fixed here.**
  `scripts/check-advisories.sh` runs cargo-audit over each lockfile a build
  vendors and govulncheck over the Go binary, daily. It is red whenever any
  package ships a dependency with a published advisory, and stays red until
  upstream releases the bump: the fix is a version PR, not a patch carried in
  this repository. Check the `trust` workflow before running a node from here.
- **Upstream test suites are not run.** Every package sets `doCheck = false`:
  these are node, indexer and wallet integration suites that want live network
  peers and real chain state, neither of which exists in a build sandbox. What
  *is* run is a smoke check that starts each binary — see `checks.smoke-*`.
  That catches link and wrapper breakage; it is not a correctness test.
- **Bit-for-bit reproducibility is worked for, and measured, not assumed.**
  On Linux the Rust packages reproduce with no flags at all, across machines.
  On macOS, stock nixpkgs Rust binaries do *not* — Hydra's own `fd` and
  `ripgrep` fail `nix build --rebuild` there — because Nix runs each darwin
  build in a randomly named directory, and that name reaches the binary
  through three channels nixpkgs leaves open: rustc's panic paths, C
  `__FILE__` strings, and ld64's debug-map stabs. `flake.nix` closes all three
  for every Rust package here. A package can still stamp in its own build
  environment — zaino read the build user — and that is fixed in the package.
  `.github/workflows/repro.yml` rebuilds a package N times and fails on any
  difference; each run's summary carries the verdict per package and platform,
  and a failing run keeps both binaries as an artifact. Pinning guarantees the
  same *inputs*; a matching store path is still not independent verification
  of a binary — run `repro.yml` yourself.
- **Build-time code execution.** Building a Rust workspace runs `build.rs` from
  every crate in the graph, and building Go runs its toolchain. This is normal
  and unavoidable, and it is why builds are sandboxed and CI tokens are not left
  in the working tree.

## Binary cache

Prebuilt artifacts are served from `cypherpunktech.cachix.org`, signed with:

```
cypherpunktech.cachix.org-1:WKo2WboMVH8HUtCKNsSFx31YQibaJ2eocruFvAzWgA4=
```

Nix verifies that signature before using anything from the cache. Using the
cache means trusting whoever can push to it, which currently includes a
maintainer's workstation — aarch64-darwin binaries are built there because a
private repository has no macOS runner. If that trust is not acceptable to you,
do not enable the substituter; everything builds from source without it, and
Nix will not use a flake's advertised cache for an untrusted user anyway.

## Reporting a vulnerability

For a problem in **this repository's packaging** — a bad pin, a derivation
reaching outside its sandbox, a leaked credential in CI — open a GitHub security
advisory on this repository, or an issue if it is not sensitive.

For a vulnerability in a **packaged project**, report it to that project, not
here. We cannot fix it and a public issue here would only broadcast it:

| Project | Report to |
|---|---|
| zebra, zinder | https://github.com/ZcashFoundation/zebra/security |
| zallet, lightwalletd, librustzcash | https://github.com/zcash/zallet/security |
| zaino | https://github.com/zingolabs/zaino |
| zakura | https://github.com/zakura-core/zakura |
| zpay | https://github.com/gustavovalverde/zpay |

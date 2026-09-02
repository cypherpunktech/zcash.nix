# zcash.nix

Nix packages and NixOS modules for the Zcash ecosystem, built from pinned source.

nixpkgs ships one Zcash node: `zcash` 5.4.2, which is zcashd, which is sunset.
Zakura, Zebra, the indexers and Zallet have no nixpkgs attribute at all.

## Packages

| | | binaries |
|---|---|---|
| **zakura** | Zcash full node built for scale | `zakurad`, `zakura-prune-state`, `zakura-rollback-state` |
| **zebra** | Zcash Foundation's Zcash node | `zebrad` |
| **zinder** | ZF's service-oriented indexer | `zinder-ingest`, `-projector`, `-query`, `-compat-lightwalletd` |
| **zaino** | Zingo Labs' indexer and proxy | `zainod` |
| **zallet** | RPC wallet replacing zcashd's | `zallet` + its `zallet-zebra` backend |
| **ztreamer** | Light-wallet server with an embedded zakura node | `ztreamerd` |
| **lightwalletd** | Light-client backend | `lightwalletd` |
| **lightwalletd-rs** | Light-client backend, in Rust | `lightwalletd-rs` |
| **zpay** | Payments facilitator (x402, MPP) | `zpay-runtime`, `zspend-runtime` |

`lightwalletd` is the one package nixpkgs also has; kept because nixpkgs sits
five releases behind.

`ztreamer` has **no licence upstream** yet, so it is labelled `unfree`: it
builds from here on your machine, is never served from the cache, and needs
`allowUnfreePredicate` when used through the overlay. A licence upstream
changes one line.

## Use

```console
$ nix run github:cypherpunktech/zcash.nix#zakura -- --version
```

```nix
# flake input
inputs.zcash-nix.url = "github:cypherpunktech/zcash.nix";

# or as an overlay
nixpkgs.overlays = [ zcash-nix.overlays.default ];

# packaging your own Zcash tool: Rust that is bit-reproducible on darwin
rustPlatform = zcash-nix.lib.reproducibleRustPlatform pkgs;
```

Hacking on the Zcash software itself — `cargo build` in a zebra or zaino
checkout, with the rocksdb/bindgen/protoc environment that makes it build:

```console
$ nix develop github:cypherpunktech/zcash.nix#zcash
```

> The repository is currently private, so these need a credential —
> `git+ssh://git@github.com/cypherpunktech/zcash.nix`.

## NixOS modules

```nix
imports = [ zcash-nix.nixosModules.default ];

services.zcash.zakura.mainnet = {
  enable = true;
  settings.rpc.listen_addr = "127.0.0.1:8232";   # freeform zakura.toml
};
services.zcash.zakura.testnet = {
  enable = true;
  settings.network.network = "Testnet";
};
```

One module per package. Nodes and indexers are multi-instance: each entry
is its own unit (`zakura-mainnet.service`) with its own state directory
(`/var/lib/zakura-mainnet`), so mainnet and testnet coexist on one host.
Wallets (`zallet`, `zpay`) are single. Every service runs under `DynamicUser`
with an empty `CapabilityBoundingSet`, `ProtectSystem=strict`, a 0700
`StateDirectory`, a syscall filter and `MemoryDenyWriteExecute` — see
[`modules/hardening.nix`](modules/hardening.nix). Every service also takes
`extraArgs`, and `user`: a static user instead of `DynamicUser`, which is
the one way two services can share a state directory (zallet reading its
node's database: give both the same `user`).

Three things the modules refuse to guess:

- `openFirewall` opens peer-to-peer, never RPC.
- `lightwalletd` and `lightwalletd-rs` need TLS, or an explicit
  `insecureNoTLS = true`; the Go one also needs a credential source.
- `ztreamer` has two listeners for two publics: `openFirewall` is the wallet
  gRPC port, `openPeerPort` the embedded node's.
- `zallet` needs `acceptBetaRisk = true`. It holds spending keys and upstream
  says not to trust it with real funds. It will not create a wallet for you.

`zinder`'s four runtimes share a storage tree, so its `user` defaults to a
static `zinder-<instance>` and may not be null.

## Binary cache

`https://cypherpunktech.cachix.org`, public, no credential needed to pull.
Nix ignores a flake's own `nixConfig` for untrusted users, so either pass
`--accept-flake-config` or set it yourself:

```nix
nix.settings = {
  extra-substituters = [ "https://cypherpunktech.cachix.org" ];
  extra-trusted-public-keys = [
    "cypherpunktech.cachix.org-1:WKo2WboMVH8HUtCKNsSFx31YQibaJ2eocruFvAzWgA4="
  ];
};
```

aarch64-darwin binaries are pushed from a maintainer's machine; a private repo
has no macOS runner.

## Platforms

`aarch64-darwin`, `aarch64-linux`, `x86_64-linux`. A package lists a platform
only once its binary has *run* there — `meta.platforms` is the only copy of
that claim, so there is no table here to drift from it.

## Not packaged

Four repos in this ecosystem are Rust libraries with zero binary targets. Nix
owns environments; cargo owns dependency graphs.

| | |
|---|---|
| [librustzcash](https://github.com/zcash/librustzcash) | `cargo add zcash_client_backend` |
| [zakura-core/common](https://github.com/zakura-core/common) | `cargo add zakura-primitives` |
| [zakura-core/wallet-libraries](https://github.com/zakura-core/wallet-libraries) | `cargo add zakura-client-backend` |
| [zally](https://github.com/gustavovalverde/zally) | not published; git dependency |

Also unbuilt as developer tooling rather than deployables: `zebra-utils`,
`zakura-utils`, `zinder-bench`, `zinder-explorer`, `zinder-compat-cipherscan`,
`zpay-demo`.

## Updates

`update.yml` runs `nix-update` weekly, one PR per package, no auto-merge.
`stale.yml` runs daily and fails if a pin falls behind — an updater that
silently stops looks identical to one with nothing to do.
`trust.yml` runs daily: cargo-audit and govulncheck over what each build
vendors, and signature verification of the pinned tag where upstream signs
one (today: zinder). Red means a vulnerable dependency shipped upstream.

## More

[SECURITY.md](SECURITY.md) — what is and is not guaranteed.
[CONTRIBUTING.md](CONTRIBUTING.md) — adding a package or module.
[AGENTS.md](AGENTS.md) — conventions and the traps behind them.

MIT for the packaging code. Each packaged project keeps its own license.

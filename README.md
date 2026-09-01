# zcash.nix

Nix packages and NixOS modules for the Zcash ecosystem, built from pinned source.

nixpkgs ships one Zcash node: `zcash` 5.4.2, which is zcashd, which is sunset.
Zebra, the indexers and Zallet have no nixpkgs attribute at all.

## Packages

| | | binaries |
|---|---|---|
| **zebra** | Zcash Foundation's Zcash node | `zebrad` |
| **zakura** | Zcash full node built for scale | `zakurad`, `zakura-prune-state`, `zakura-rollback-state` |
| **zinder** | ZF's service-oriented indexer | `zinder-ingest`, `-projector`, `-query`, `-compat-lightwalletd` |
| **zaino** | Zingo Labs' indexer and proxy | `zainod` |
| **zallet** | RPC wallet replacing zcashd's | `zallet` + its `zallet-zebra` backend |
| **lightwalletd** | Light-client backend | `lightwalletd` |
| **zpay** | Payments facilitator (x402, MPP) | `zpay-runtime`, `zspend-runtime` |

`lightwalletd` is the one package nixpkgs also has; kept because nixpkgs sits
five releases behind.

## Use

```console
$ nix run github:cypherpunktech/zcash.nix#zebra -- --version
```

```nix
# flake input
inputs.zcash-nix.url = "github:cypherpunktech/zcash.nix";

# or as an overlay
nixpkgs.overlays = [ zcash-nix.overlays.default ];
```

> The repository is currently private, so these need a credential —
> `git+ssh://git@github.com/cypherpunktech/zcash.nix`.

## NixOS modules

```nix
imports = [ zcash-nix.nixosModules.default ];

services.zcash.zebra = {
  enable = true;
  settings.rpc.listen_addr = "127.0.0.1:8232";   # freeform zebrad.toml
};
```

One module per package. Every service runs under `DynamicUser` with an empty
`CapabilityBoundingSet`, `ProtectSystem=strict`, a 0700 `StateDirectory`, a
syscall filter and `MemoryDenyWriteExecute` — see
[`modules/hardening.nix`](modules/hardening.nix).

Three things the modules refuse to guess:

- `openFirewall` opens peer-to-peer, never RPC.
- `lightwalletd` needs TLS, or an explicit `insecureNoTLS = true`, plus a
  credential source.
- `zallet` needs `acceptBetaRisk = true`. It holds spending keys and upstream
  says not to trust it with real funds. It will not create a wallet for you.

`zinder`'s four runtimes share a storage tree, so they run as one static user
rather than `DynamicUser`. A test keeps that confined to `zinder`.

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

## More

[SECURITY.md](SECURITY.md) — what is and is not guaranteed.
[CONTRIBUTING.md](CONTRIBUTING.md) — adding a package or module.
[AGENTS.md](AGENTS.md) — conventions and the traps behind them.

MIT for the packaging code. Each packaged project keeps its own license.

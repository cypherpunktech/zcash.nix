![zcash.nix](./banner.png)

# zcash.nix [![GitHub Actions][gha-badge]][gha] [![X][x-badge]][x]

[gha]: https://github.com/cypherpunktech/zcash.nix/actions
[gha-badge]: https://github.com/cypherpunktech/zcash.nix/actions/workflows/check.yml/badge.svg
[x]: https://x.com/cypherpunk
[x-badge]: https://img.shields.io/twitter/follow/cypherpunk

Nix packages and NixOS modules for the [Zcash](https://z.cash) ecosystem, built from pinned source.

Running Zcash infrastructure means installing a node, an indexer, and a wallet server from different
teams, each with its own build, and keeping them all current on every machine. nixpkgs offers no help
here: its one Zcash node is zcashd, which is sunset. This repository packages the whole post-zcashd
stack, runs each program as a hardened service, and proves every claim it makes in CI, on every
platform, before anything ships.

## Packages

| Package | | Binaries |
| --- | --- | --- |
| **zakura** | Zcash full node built for scale | `zakurad`, `zakura-prune-state`, `zakura-rollback-state` |
| **zebra** | Zcash Foundation's node | `zebrad` |
| **zaino** | Zingo Labs' indexer and proxy | `zainod` |
| **zinder** | ZF's service-oriented indexer | `zinder-ingest`, `-projector`, `-query`, `-compat-lightwalletd` |
| **ztreamer** | Light-wallet server with an embedded zakura node | `ztreamerd` |
| **lightwalletd** | Light-client backend | `lightwalletd` |
| **lightwalletd-rs** | Light-client backend, in Rust | `lightwalletd-rs` |
| **zallet** | RPC wallet replacing zcashd's | `zallet` and its zebra backend |
| **zpay** | Payments facilitator (x402, MPP) | `zpay-runtime`, `zspend-runtime` |

Every package is built and its binary run on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. A
platform is listed only once that has happened there. `ztreamer` has no licence upstream yet, so it is
labelled `unfree`: it builds on your machine and is never served from the cache or the registry.

## Usage

Run a package directly, or add the flake to your configuration:

```console
$ nix run github:cypherpunktech/zcash.nix#zakura -- --version
```

```nix
inputs.zcash-nix.url = "github:cypherpunktech/zcash.nix";

# as an overlay
nixpkgs.overlays = [ zcash-nix.overlays.default ];
```

Prebuilt binaries for all three platforms are served from `cypherpunktech.cachix.org`. Nix ignores a
flake's own cache settings for untrusted users, so pass `--accept-flake-config` or add the cache
yourself:

```nix
nix.settings = {
  extra-substituters = [ "https://cypherpunktech.cachix.org" ];
  extra-trusted-public-keys = [ "cypherpunktech.cachix.org-1:WKo2WboMVH8HUtCKNsSFx31YQibaJ2eocruFvAzWgA4=" ];
};
```

Containers are published to GHCR, one per package: non-root, state in `/data`, tagged by version only.

```console
$ docker run -v zakura:/data ghcr.io/cypherpunktech/zakura:1.3.0 start
```

To work on the Zcash software itself, `nix develop github:cypherpunktech/zcash.nix#zcash` gives a shell
with the exact toolchain and native inputs the packages are built with, so `cargo build` works in a
zebra or zaino checkout. To package a Zcash tool of your own, `lib.reproducibleRustPlatform` is the
Rust platform that makes builds bit-reproducible on macOS.

## NixOS Modules

```nix
imports = [ zcash-nix.nixosModules.default ];

services.zcash.zakura.mainnet = {
  enable = true;
  settings.rpc.listen_addr = "127.0.0.1:8232"; # freeform zakura.toml
};

services.zcash.zakura.testnet = {
  enable = true;
  settings.network.network = "Testnet";
};
```

One module per package. Nodes and indexers are multi-instance, so mainnet and testnet coexist on one
host, each as its own unit with its own state directory. Wallets are single-instance.

Every service runs as a dynamic user with no capabilities, a read-only system, a private state
directory, and a syscall filter. Every service takes `extraArgs`, and `user` for the one case where two
services must share a state directory, such as zallet reading its node's database.

The modules refuse to guess on security. `openFirewall` opens the peer-to-peer port and never RPC.
The lightwalletd modules require TLS or an explicit `insecureNoTLS = true`. `zallet` requires
`acceptBetaRisk = true`, because it holds spending keys and upstream says not to trust it with real
funds yet.

## Verification

This repository does not ask to be trusted. Each claim below is a job that goes red when the claim
stops being true.

- Every binary is built and executed on every platform it claims.
- Every module is booted in a virtual machine, including a full stack that mines blocks, indexes
  them, and answers a wallet's query.
- Builds are rebuilt and compared byte for byte.
- Dependencies are scanned daily for published vulnerabilities.
- Where upstream signs its releases, the signature is verified against the exact source that was built.
- Version bumps are proposed weekly, tested on every platform, and merged once green. A daily check
  fails if any package falls behind upstream.

See [SECURITY.md](SECURITY.md) for what is and is not guaranteed.

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for adding a package or module, and
[`AGENTS.md`](AGENTS.md) for the conventions and the reasons behind them.

## License

This project is licensed under [MIT](LICENSE). Each packaged project keeps its own license.

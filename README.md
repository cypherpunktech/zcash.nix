![zcash.nix](./banner.png)

# zcash.nix [![GitHub Actions][gha-badge]][gha] [![X][x-badge]][x]

[gha]: https://github.com/cypherpunktech/zcash.nix/actions
[gha-badge]: https://github.com/cypherpunktech/zcash.nix/actions/workflows/check.yml/badge.svg
[x]: https://x.com/cypherpunk
[x-badge]: https://img.shields.io/twitter/follow/cypherpunk

Nix packages and NixOS modules for the [Zcash](https://z.cash) ecosystem, built from pinned source.

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

Built and run on `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.

## Usage

```console
$ nix run github:cypherpunktech/zcash.nix#zakura -- --version
```

```nix
inputs.zcash-nix.url = "github:cypherpunktech/zcash.nix";
nixpkgs.overlays = [ zcash-nix.overlays.default ];
```

```nix
imports = [ zcash-nix.nixosModules.default ];

services.zcash.zakura.mainnet = {
  enable = true;
  settings.rpc.listen_addr = "127.0.0.1:8232"; # freeform zakura.toml
};
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md).

## License

[MIT](LICENSE)

# zcash.nix

Nix packages for the Zcash ecosystem, built from source.

nixpkgs packages exactly one Zcash node: `zcash` 5.4.2 — that is zcashd, which is
sunset. Zebra, the indexers and Zallet, the stack that actually replaces it, have
no nixpkgs attribute at all. This flake is that gap, closed.

## Packages

### Nodes

| | |
|---|---|
| **zebra** | The Zcash Foundation's independent, consensus-compatible Zcash node. `zebrad` |
| **zakura** | Zcash full node built for scale. `zakurad`, plus `zakura-prune-state` and `zakura-rollback-state` |

### Indexers

| | |
|---|---|
| **zinder** | Service-oriented Zcash indexer: native WalletQuery gRPC plus drop-in lightwalletd compatibility. `zinder-ingest`, `zinder-projector`, `zinder-query`, `zinder-compat-lightwalletd` |
| **zaino** | Indexer and proxy server for the Zcash protocol. `zainod` |

### Wallets

| | |
|---|---|
| **zallet** | The RPC wallet replacing zcashd's embedded wallet. `zallet` — shipped with its `zallet-zebra` backend, because the `zallet` command is only a launcher and cannot run without one |

### Payments

| | |
|---|---|
| **zpay** | Zcash-native payments facilitator: x402 and MPP wire adapters over one protocol-neutral core. `zpay-runtime`, `zspend-runtime` |

## Three ways in

> This repository is currently **private**. Every `github:cypherpunktech/zcash.nix`
> reference below therefore needs a GitHub credential Nix can use — an SSH key
> plus `git+ssh://git@github.com/cypherpunktech/zcash.nix`, or an access token.
> The snippets are written for the public form so nothing has to change when it
> opens up.

**Run one now** — nothing installed, nothing left behind:

```console
$ nix run github:cypherpunktech/zcash.nix#zebra -- --version
```

**As a flake input:**

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    zcash-nix.url = "github:cypherpunktech/zcash.nix";
  };

  outputs = { nixpkgs, zcash-nix, ... }: {
    # zcash-nix.packages.${system}.zebra
  };
}
```

**As an overlay**, so the packages appear beside everything else in `pkgs`:

```nix
nixpkgs.overlays = [ zcash-nix.overlays.default ];
# pkgs.zebra, pkgs.zallet, ...
```

## What you are trusting

Every package is compiled from upstream source at a pinned tag or commit, with
the source tree's content hash recorded in this repo. No vendor binaries are
downloaded and repackaged; there is no `--impure`, and no unpinned fetch
anywhere in the tree. If upstream moves a tag, the hash stops matching and the
build fails loudly rather than quietly building something else.

What that does **not** give you: these are packaging definitions, not an audit of
the software being packaged. The upstream projects keep their own licenses and
their own security posture. The MIT license here covers the Nix code only.

## Platform support

Each derivation's `meta.platforms` is the claim, and it is the only copy of it —
a table here would be a second source of truth free to drift from the thing CI
actually builds. `checks.smoke-<name>` is generated only for platforms a package
claims, so widening that list immediately widens what has to pass. A platform a
package cannot build on appears in `meta.badPlatforms` with the error that put
it there.

A package is listed for a platform because its binary *started* there, not
because it compiled.

```console
$ nix eval --json github:cypherpunktech/zcash.nix#packages.x86_64-linux --apply builtins.attrNames
```

## Not packaged, and why

Four repositories in this ecosystem are Rust **libraries** with zero binary
targets. Nix owns environments; cargo owns in-project dependency graphs and
registries. Packaging a library here would put nix where cargo already works, so
these are listed rather than wrapped:

| Repository | Consume with |
|---|---|
| [zcash/librustzcash](https://github.com/zcash/librustzcash) | `cargo add zcash_client_backend` (and siblings) |
| [zakura-core/common](https://github.com/zakura-core/common) | `cargo add zakura-primitives` (and siblings) |
| [zakura-core/wallet-libraries](https://github.com/zakura-core/wallet-libraries) | `cargo add zakura-client-backend` |
| [gustavovalverde/zally](https://github.com/gustavovalverde/zally) | not on crates.io — a git dependency on the repository |

Also deliberately unbuilt, as developer tooling rather than deployable
binaries: `zebra-utils`, `zakura-utils`, `zinder-bench`, `zinder-explorer`,
`zinder-compat-cipherscan`, `zpay-demo`. Open an issue if you want one.

## Staying current

`update.yml` runs `nix-update` weekly and opens one pull request per package.
Nothing auto-merges: a consensus node's version bump gets read by a person.

`stale.yml` runs daily and asserts that the pins are current: a package tracking
releases must be on the newest one or within two weeks of it; a package pinned to
a commit, because its upstream cuts no releases, must be on the branch head or
within ninety days of its commit. Which rule applies is read from `src.rev`, the
same field `update.yml` branches on, so the two cannot disagree about what kind
of pin a package has.

It exists because an updater that silently stops working looks exactly like an
updater with nothing to do. This is the check that can go red when that happens,
and it has been tested in the failing direction, not only the passing one.

## Contributing

A package is a directory: `packages/<name>/default.nix`. `flake.nix` discovers it
with `readDir`, so there is no registry to edit. See [AGENTS.md](AGENTS.md) for
the conventions, including the one that matters most — every package must set
`passthru.smokeArgs`, the argv that proves its binary runs.

## License

MIT for the packaging code in this repository. Each packaged project keeps its
own license; see `meta.license` in the corresponding derivation.

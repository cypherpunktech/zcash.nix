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

### Light-client backend

| | |
|---|---|
| **lightwalletd** | The service light wallets talk to. `lightwalletd` — the one package here that nixpkgs also has, kept because nixpkgs sits five releases behind |

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

## NixOS modules

Packages give you a binary. The part that is actually easy to get wrong is the
unit around it — a consensus node holding tens of gigabytes of state, reachable
from the internet, running as root because that is what the blog post did.

```nix
{
  imports = [ zcash-nix.nixosModules.default ];

  services.zcash.zebra = {
    enable = true;
    settings = {
      network.network = "Mainnet";
      rpc.listen_addr = "127.0.0.1:8232";
    };
  };

  services.zcash.lightwalletd = {
    enable = true;
    tls.certFile = "/var/lib/secrets/lwd.pem";
    tls.keyFile = "/var/lib/secrets/lwd.key";
  };
}
```

Every packaged service has a module: `zebra`, `zakura`, `zaino`, `zinder`,
`lightwalletd`, `zallet` and `zpay` — seven modules, ten systemd units, since
`zinder` runs four cooperating runtimes.

Two binaries are deliberately never auto-started, because both hold spend
authority: `zspend-runtime` (shipped with `zpay`) and any wallet you have not
initialised yourself.

Every service runs under `DynamicUser` with an empty `CapabilityBoundingSet`,
`ProtectSystem=strict`, a private `StateDirectory` at mode 0700, a syscall
filter, and `MemoryDenyWriteExecute`. That block lives in one file,
[`modules/hardening.nix`](modules/hardening.nix), with a comment per line
explaining why it is there rather than a wall of directives copied from
somewhere.

`services.zcash.zebra.settings` is freeform: it becomes `zebrad.toml` verbatim,
so every option zebrad has is available and nothing here has to be updated when
upstream adds a field.

Three deliberate refusals:

- **`openFirewall` never opens the RPC port**, only peer-to-peer. RPC is an
  administrative interface; a node exposing it to the internet is a node
  somebody else is driving.
- **lightwalletd will not start without TLS unless you say `insecureNoTLS =
  true`.** A wallet's queries reveal what it is looking for, so plaintext
  defeats much of the point of using Zcash. The module refuses to guess.
- **`zallet` will not enable without `acceptBetaRisk = true`.** It holds
  spending keys, its authors advise against significant funds, and upstream
  itself refuses to generate a config without an explicit beta acknowledgement.
  Wrapping that in a friendly one-liner would launder a warning they went out of
  their way to make unmissable. It also does not initialise a wallet for you:
  generating an encryption identity and a mnemonic are irreversible and belong
  to a human with somewhere safe to put the result.

One documented deviation: `zinder`'s four runtimes share a storage tree, and
`DynamicUser` allocates a different uid per service — so they cannot share a
directory. They run as one static `zinder` user instead. That is forced by the
software's design rather than chosen, and a test asserts it stays confined to
`zinder` rather than spreading.

The modules are covered by NixOS VM tests that boot a machine, start the
service, query its RPC, and assert the hardening is actually applied — not just
that the option was set. They run in CI on `x86_64-linux`; `nixosTest` needs a
Linux builder with KVM, so they cannot run on macOS at all.

## Binary cache

Prebuilt binaries are published to [`cypherpunktech.cachix.org`](https://app.cachix.org/cache/cypherpunktech).
The cache is public: pulling needs no credential.

`flake.nix` advertises it via `nixConfig`, but Nix will not act on a flake's own
config for an untrusted user — you will see:

```
warning: ignoring untrusted flake configuration setting 'extra-substituters'
```

and then build from source. That refusal is correct: a flake asking to be
trusted as a binary source is exactly the thing that should not be automatic.
To accept it, either pass `--accept-flake-config` per command, or add yourself
to `trusted-users` in `nix.conf` and set the substituter there permanently:

```nix
nix.settings = {
  extra-substituters = [ "https://cypherpunktech.cachix.org" ];
  extra-trusted-public-keys = [
    "cypherpunktech.cachix.org-1:WKo2WboMVH8HUtCKNsSFx31YQibaJ2eocruFvAzWgA4="
  ];
};
```

aarch64-darwin binaries are pushed from a maintainer's machine, because a
private repository has no macOS runner to build them.

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

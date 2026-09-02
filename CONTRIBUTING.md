# Contributing

## Adding a package

A package is a directory; `flake.nix` discovers it. No registry to edit.

```console
$ mkdir -p packages/yourthing && cd packages/yourthing
$ nix flake init -t ../..#package
$ git add -A          # flakes only see tracked files
$ just build yourthing
```

Leave `hash` and `cargoHash` as `lib.fakeHash`, build, paste the real hash from the error. Never
guess or truncate one.

Required: `meta.description`, `meta.license`, `meta.homepage`, `meta.mainProgram`, `meta.platforms`,
and `passthru.smokeArgs`, the argv that proves the binary runs. It has no default: an unproven package
fails at evaluation.

`meta.license` is what upstream grants; `redistributable` on the licence decides whether the cache and
registry may carry the binary.

If upstream signs release tags, add `passthru.upstreamSigners = ./allowed_signers;` with only the key
that signed the tag (`git cat-file tag <tag>`, then `ssh-keygen -Y find-principals`). `just verify` must
print `verified`.

## Adding a NixOS module

`modules/yourthing/default.nix`, discovered the same way. Start from `modules/service.nix`: the options
every service has (`enable`, `package`, `extraArgs`, `user`) and `identity`, which turns `user` into the
hardened `serviceConfig`. Nodes and indexers are multi-instance (`modules/zaino` is the smallest
example); wallets are single (`modules/zpay`). Add the service to `tests/units.nix`.

## Before a PR

```console
$ just fmt      # --no-cache: plain `nix fmt` can pass where CI fails
$ just check    # builds and runs every binary for this system
```

VM tests need Linux with KVM; CI runs them.

## Review

`meta.platforms` lists only systems the binary has run on. Comments explain why, not what: `# set
PROTOC` repeats the line; `# zebra's Dockerfile installs exactly libclang-dev and protobuf-compiler`
says what would have to change for it to be wrong. Commits say what was measured and which failure
was fixed.

Bugs in packaging belong here; bugs in a packaged project belong upstream, see
[SECURITY.md](SECURITY.md).

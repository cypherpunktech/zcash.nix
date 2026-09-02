# Contributing

## Adding a package

A package **is** a directory. `flake.nix` finds it with `readDir`, so there is
no registry to edit and nothing to forget.

```console
$ mkdir -p packages/yourthing
$ $EDITOR packages/yourthing/default.nix
$ git add -A          # flakes only see git-TRACKED files
$ just build yourthing
```

Set `hash` and `cargoHash` (or `vendorHash`) to `lib.fakeHash`, build, and paste
the real hash out of the error. Never guess one and never truncate one.

Every derivation must set `meta.description`, `meta.license`, `meta.homepage`,
`meta.mainProgram`, `meta.platforms`, and:

```nix
passthru.smokeArgs = [ "--version" ];
```

`smokeArgs` has **no default**. It is the argv that proves the binary runs, and
a package that cannot answer it fails at evaluation — an unproven package is
worse than an absent one. Pick something that exercises the thing that could
plausibly be broken: for `zallet` it is `--version`, because the launcher passes
it through to a backend binary and so a missing backend fails there.

If upstream signs its release tags, add the signer:

```nix
passthru.upstreamSigners = ./allowed_signers;
```

with the file in ssh allowed-signers form (`email ssh-ed25519 AAAA...`),
carrying only the key that actually signed the tag — `git cat-file tag <tag>`
shows the signature, `ssh-keygen -Y find-principals` says which key made it.
`just verify` must then print `verified` for the package. If upstream signs
nothing, or only binaries, declare nothing: the gate lists it as unsigned.

## Adding a NixOS module

Same rule: `modules/yourthing/default.nix`, discovered by `readDir`. A module is
a function of `self` so its `package` option can default to this flake's build.

Import the shared hardening rather than writing your own:

```nix
serviceConfig = (import ../hardening.nix) // { ... };
```

If your service genuinely cannot use it — `zinder` cannot use `DynamicUser`,
because its four runtimes share a storage tree — say so in a comment where
someone will hit it, and add an assertion to `tests/units.nix` so the deviation
stays confined to the service that needs it.

## Before you open a PR

```console
$ just fmt      # --no-cache: a plain `nix fmt` can pass where CI fails
$ just check    # builds every package for this system and RUNS each binary
```

`just check` will not run the NixOS VM tests on macOS — `nixosTest` needs a
Linux builder with KVM. CI runs them; expect that feedback to arrive there.

## What gets pushed back

Reviews here care about two things beyond correctness.

**Is the claim honest?** `meta.platforms` may only list systems something has
actually been built and run on. A support claim nobody has tested is worse than
no claim, because it looks like evidence.

**Does the comment explain the reason, not the mechanism?** `# set PROTOC` says
what the next line already says. `# zebra's own Dockerfile installs exactly
libclang-dev and protobuf-compiler` says why it is there and what would have to
change for it to be wrong. The second survives someone editing the code; the
first does not.

## Commits

Say what changed and why it had to change that way. If something was measured,
say what was measured — "verified idempotent: a second nix-update run reports no
changes" is worth more than "fixed the updater". If a fix came from a failure,
name the failure, because the next person will hit its cousin.

## Reporting problems

A bug in the packaging belongs here. A bug in a packaged project belongs to that
project — see [SECURITY.md](SECURITY.md) for where each one goes.

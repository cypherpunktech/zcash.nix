# AGENTS.md

Conventions for this repository. They are short because each one exists to stop
a specific failure that has already happened.

## What this repo is

Nix packages for the Zcash ecosystem, built from pinned upstream source. It
exists because nixpkgs packages only `zcash` (sunset zcashd) and `lightwalletd`;
Zebra, the indexers and Zallet have no nixpkgs attribute at all.

## Adding a package

A package **is** a directory: `packages/<name>/default.nix`. `flake.nix` finds it
with `readDir`. There is no registry to edit, and the `packages` output and the
overlay are the same function, so they cannot disagree.

Every derivation must set:

- `meta.description`, `meta.license`, `meta.homepage`
- `meta.mainProgram` — `lib.getExe` and `nix run` both depend on it
- `meta.platforms` — see *Platform honesty* below
- `passthru.smokeArgs` — the argv that proves the binary runs. **No default.**
  A package that does not answer this fails at eval, because an unproven
  package is worse than an absent one.

## Hashes

`hash` and `cargoHash` start as `lib.fakeHash`. Build, read the real hash out of
the error, paste it whole. Never guess one, never truncate one, never copy one
from a sibling package.

Use `cargoHash`, not `cargoLock.lockFile`: several of these workspaces have git
dependencies in `Cargo.lock`, which `fetchCargoVendor` resolves by itself while
`cargoLock` would need a hand-maintained `outputHashes`.

## Platform honesty

`meta.platforms` is a claim, and `checks.smoke-<name>` is generated only for
platforms a package claims — so widening the list immediately widens what CI
must prove. You cannot claim a platform without paying for it.

When a build fails on a platform, move that system into `meta.badPlatforms` with
a comment naming the actual error. Evidence, not silence, and not a lie in the
other direction either. The README's support table states what CI really built.

## The rules that bite

- **Flakes see only git-TRACKED files.** jj's snapshot does not touch git's
  index, so a new file is invisible to `nix build` until `git add`. Every
  justfile recipe stages first; do the same by hand or you will debug a "path
  does not exist" for a file you are looking at.
- **No `--impure`, ever.** No unpinned `fetchTarball`. No host tools from
  `/usr/bin` in a derivation — that is what makes a flake fail inside the
  sandbox on someone else's machine.
- **Never read `$?` after a pipe** — you get the last command's status.
  Redirect to a file and echo `$?` on its own line.
- **Commits go through jj**, never raw git: `jj describe @ --stdin` (heredoc),
  `jj new`, `jj bookmark set main -r @-`, `jj git push --bookmark main`.
  Never `-m "..."`: backticks inside double quotes run as command substitution
  and silently eat words.

## Things that bit us here, with the fix

- **A build script shelling out to `git`.** zaino's `zaino-state/build.rs` stamps
  the binary from `git rev-parse` unless its env vars are set. There is no git in
  the sandbox and no `.git` in the source — it arrives as a tarball. Set the env
  vars the build script documents, fed from `src.rev` so there is no second copy
  of the revision to drift. Do **not** add `git` to `nativeBuildInputs`; that
  makes the error disappear while leaving a build that depends on a host tool.
  Read a new package's `build.rs` files before starting a long build.
- **`include_str!` escaping a crate root in a git dependency.** Plain cargo checks
  the whole repo out into `~/.cargo/git` so the path resolves; `fetchCargoVendor`
  copies each git dependency as a bare crate directory, so it does not. See
  `packages/zpay`. Any workaround for this must fail loudly once it is no longer
  needed, or it becomes a permanent unexamined patch.
- **Running several cargo vendors at once starves them all.** They share
  `http-connections`; four in parallel sat for over an hour with no output while
  each alone takes about ten minutes. Vendor one package at a time.
- **`meta.platforms` blocks `nix build`**, and `nix flake check --all-systems`
  forces every package's drvPath — so an unavailable package is an eval error,
  not a skip. That is why `packages.<system>` is filtered by availability in
  `flake.nix` and the overlay is not.
- **A join derivation still needs `src`.** `packages/zallet` copies two builds
  together and has nothing to unpack, but without `src` the staleness gate cannot
  see what it is pinned to and the package goes silently unwatched.

## The updater must not fail closed

`.github/workflows/update.yml` opens version-bump PRs and never auto-merges. On
failure it leaves the job red and the branch alone — it does not tidy up after
itself.

`.github/workflows/stale.yml` is the reason to trust the pins: it asserts every
package is within 14 days of upstream's latest release, and goes red otherwise.
An updater that does nothing can pass silently forever; that assertion cannot.
This is a direct response to an auto-updater that failed closed for three months
without anyone noticing. **If you change the updater, keep something that can
turn red when it stops working.**

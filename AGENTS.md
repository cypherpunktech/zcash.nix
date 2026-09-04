# AGENTS.md

Conventions for this repository. They are short because each one exists to stop
a specific failure that has already happened.

## What this repo is

Nix packages **and NixOS service modules** for the Zcash ecosystem, built from
pinned upstream source. It exists because nixpkgs packages only `zcash` (sunset
zcashd) and `lightwalletd`; Zebra, the indexers and Zallet have no nixpkgs
attribute at all.

Both halves matter. The packages give a binary; the modules give the unit
around it, which is where a node ends up running as root with its state
world-readable.

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

## Adding a NixOS module

Same rule as packages: `modules/<name>/default.nix`, found by `readDir`. Plain
`.nix` files beside them (`service.nix`, `hardening.nix`, `node.nix`,
`lightwallet.nix`) are skipped by the directory filter — shared code must not
become a module by accident.

A module is a function of `self`, so `package` can default to this flake's
build with no overlay and no second place naming which package a service runs.

`modules/service.nix` is the shape every service shares: the options all of
them carry (`enable`, `package`, `extraArgs`, `user`) and `identity`, which
resolves `user` into the hardened `serviceConfig` -- an allocated DynamicUser
by default, or a static user it creates. Nodes and indexers are
multi-instance (`services.zcash.<name>.<instance>` → unit `<name>-<instance>`,
state `/var/lib/<name>-<instance>`), the nixpkgs `services.bitcoind.<name>`
shape, because mainnet and testnet on one host is the ordinary developer
setup and the option path is the API: it could not be changed after launch
without breaking every user. Wallets are single-instance.

A submodule under `attrsOf` receives its key as `name` -- only if the
function destructures `{ name, ... }`; `args: args.name` gets nothing,
because `_module.args` are injected per named parameter. Bitten live.

A service that cannot use DynamicUser (zinder: four runtimes, one tree)
defaults `user` to a static name and asserts it is not null. `tests/units.nix`
asserts identity and hardening for every unit, including one deliberately
shared user, so a deviation is confined by a test rather than a comment.

**A secret is a string path handed over by `LoadCredential`, never a
`types.path` and never on argv.** `service.secretFile`, `service.credentials`
and `service.notInStore` in `modules/service.nix` are the three rules; the
comment there says why each exists: a path literal is copied to the
world-readable store, a DynamicUser cannot read a root-owned file, and argv
is the unit file, which is in the store. `tests/fixtures/credentials.nix` is
how a test walks that path with no key material committed. Bitten: the
options were `types.path` and the TLS branch had never run in any test.

**Refuse to guess on security-relevant defaults.** Three modules already do:
`openFirewall` never opens RPC, `lightwalletd` will not start without TLS
unless `insecureNoTLS` is set, and `zallet` needs `acceptBetaRisk` because it
holds spending keys and upstream says so itself. Silently picking the
convenient option launders a decision that belongs to the operator.

## Testing modules

`nixosTest` needs a Linux builder with KVM. CI has one; a Mac has one too,
through nix-darwin's `nix.linux-builder.enable = true`: nixpkgs pairs an
aarch64-darwin host with an aarch64-linux guest under HVF, and
`nix run .#nixosTests.aarch64-darwin.stack.driverInteractive` is a Python
REPL with the machines up. Without a builder a wrong test still costs a CI
round trip, so take what evaluation gives for free first: `checks.eval-units`
forces the units machine's whole system on every system, and
`nix eval .#nixosTests.x86_64-linux.<test>.driver.drvPath` does the same for
one test; both fire every assertion and option type. The rendered unit is at
`.#nixosTests.x86_64-linux.<test>.nodes.machine.systemd.services.<unit>`.

Tests state only what they enable: every machine has every module and the
dead-network Regtest node from `tests/fixtures/regtest.nix`. Subdirectories
of `tests/` are fixtures, not tests.

Better still, run the daemons directly. Two of the three VM failures so far
were reproduced on the maintainer's Mac in two minutes each — zebrad looping on
seed-peer DNS, and lightwalletd exiting without RPC credentials.

**An assertion must report what it saw.** `test $(stat -c %a X) = 700` fails
without printing the mode, which cost a round trip to diagnose. Compare in
Python and interpolate the value into the message.

**A crash loop is never "failed".** Under `Restart=on-failure` a unit that
dies every ten seconds is `activating`, not `failed`, and `is-active` is true
for the second between. `NRestarts` is the number that says a service started
cleanly; every per-service test asserts it is 0. That is what caught
lightwalletd opening `/dev/stdout`, a journald socket, at every start.

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
other direction either.

There is deliberately **no support table in the README**: it would be a second
copy of `meta.platforms`, free to drift from the thing CI actually builds. The
derivations are the only claim.

This rule has been broken here once already. All seven packages listed
`aarch64-linux` while no runner had ever compiled any of them — a claim sitting
in the tree looking like evidence, two files from the rule forbidding it.
Nothing caught it because nothing tests a platform you never build.

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
- **`"${pkgs.path}/x"` copies all of nixpkgs into the store**, and CI's
  evaluation refuses that under `--no-build`. `pkgs.path + "/x"` stays a path;
  a file from nixpkgs is `builtins.readFile`, never interpolated.
- **`just docs` after changing an option.** `checks.options-doc` diffs
  `docs/options.md` against the modules and is red while it is stale.
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
- **`nix fmt` can report clean while `checks.formatting` fails.** treefmt caches
  by mtime; the check derivation runs fresh in a sandbox with no cache. Use
  `just fmt`, which passes `--no-cache`, or the local gate is asking a different
  question from CI and is worth nothing.
- **`nix fmt` reformats the `tests/` files' argument lists.** They are functions
  of two arguments, and nixfmt collapses `self:\n_: {` onto one line. Harmless,
  but it is why a freshly written test file always shows as changed once.
- **A join derivation still needs `src`, and `passthru.parts`.** `packages/zallet`
  copies two builds together and has nothing to unpack, but without `src` the
  staleness gate cannot see what it is pinned to and the package goes silently
  unwatched. Likewise `nix build --rebuild` of the join rebuilds only the `cp`,
  so `repro.yml` would pass it forever; `parts` names the derivations whose
  bytes the reproducibility claim is actually about.

## Reproducibility, and how it was lost three times before it was found

Every Rust package here is built bit-reproducibly on darwin through
`reproducibleRustPlatform` in `flake.nix`. Read its comment before touching
it. The rules that came out of finding the causes:

- **Always `--rebuild --keep-failed`.** A differing rebuild without a retained
  `.check` output is a failure you cannot diagnose and will have to reproduce.
  Two cycles were lost this way.
- **Record the build user and build-dir length for every rebuild.** The daemon
  hands out `_nixbld<N>` per concurrent build and names the dir
  `nix-<pid>-<random>`; a lone rebuild gets the same slot and the same length
  as the original and passes by coincidence. A pass proves nothing unless those
  varied.
- **`strings` cannot see an 8-byte value.** rustc encodes it as `mov`/`movk`
  immediates. `BUILD_USER` was ruled out with `strings`, then found by
  disassembling `get_build_info`. Use `otool -tv` on the function that consumes
  the value.
- **Compiler remaps do not reach the linker.** `--remap-path-prefix` fixes what
  rustc writes; N_OSO stabs are what ld64 read from the filesystem, and only
  `-Wl,-S` or `-oso_prefix` touches them.
- **Bucket differing bytes by Mach-O section before theorising.** A diff that
  is only `LC_UUID` + code signature means the content is identical and
  something strip removed differed; `scratchpad` scripts from the investigation
  do this from `cmp -l`. Two wrong theories -- LLVM ThinLTO drift, an ld64 hash
  race -- were written into this tree and removed because the bytes were read
  after the theory rather than before.
- **Linux is a stricter test than darwin for some things.** Its shipped ELF keeps
  `.symtab` with the ThinLTO `.llvm.<hash>` names; darwin's does not. Stable on
  Linux across machines means those hashes are not drifting anywhere.

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

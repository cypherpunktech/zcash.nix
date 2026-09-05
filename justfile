default:
    @just --list

# Flakes see only git-TRACKED files, and jj's snapshot does not touch git's
# index — so a new packages/<name>/default.nix is invisible to nix until it is
# added. Every recipe that evaluates the flake stages first, or you get a
# baffling "path does not exist" for a file that is plainly on disk.
stage:
    @git add -A

# The gate: builds every package for this system AND runs every smoke check.
check: stage
    nix flake check -L

# Cheap gate for CI: proves the flake evaluates for all three systems. The
# two extra flags are what check.yml's eval job runs under (its nix.conf
# forbids import-from-derivation; --no-update-lock-file refuses an input
# added without `nix flake lock`), so local and CI ask the same question.
eval: stage
    nix flake check --all-systems --no-build --no-update-lock-file --no-allow-import-from-derivation

# --no-cache is not paranoia. treefmt caches by mtime, so a plain `nix fmt` can
# report "0 changed" on files it has already seen while checks.formatting --
# which runs fresh in a sandbox with no cache -- fails on the same tree. Bitten
# live: the local gate said clean and CI said otherwise. Local and CI must be
# asking the same question or the local one is worthless.
fmt: stage
    nix fmt -- --no-cache

build PKG: stage
    nix build -L .#{{ PKG }}

update PKG: stage
    nix-update --flake --version=stable {{ PKG }}

# Every VM test's Python, rendered and parsed here. The driver's own syntax
# check runs only where the driver builds, which is Linux; an indentation slip
# in a test otherwise costs a CI round trip to find.
tests: stage
    for t in $(nix eval --json .#nixosTests.x86_64-linux --apply builtins.attrNames | jq -r '.[]'); do nix derivation show "$(nix eval --raw ".#nixosTests.x86_64-linux.$t.driver.drvPath")" | jq -r '.derivations[].env.testScript' | nix run --inputs-from . nixpkgs#python3 -- -c 'import ast,sys; ast.parse(sys.stdin.read())' && echo "$t: parses"; done

# Regenerate the options reference after changing a module. checks.options-doc
# fails while docs/options.md is stale, on every system, in the eval job.
docs: stage
    cp -f "$(nix build --no-link --print-out-paths ".#docs.$(nix eval --raw --impure --expr builtins.currentSystem)")" docs/options.md
    chmod 644 docs/options.md

# The trust gates (trust.yml, stale.yml), runnable here in a minute. Each is
# a flake app carrying its own tools (flake.nix `commands`), so local and CI
# run the same script with the same binaries.
audit: stage
    nix run .#audit

verify: stage
    nix run .#verify

fods: stage
    nix run .#fods

stale: stage
    nix run .#stale

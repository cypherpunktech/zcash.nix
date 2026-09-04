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

# The two trust gates (.github/workflows/trust.yml), runnable here in a minute.
# Auditors come from the flake's pinned nixpkgs so local and CI agree.
audit: stage
    nix shell --inputs-from . nixpkgs#cargo-audit nixpkgs#govulncheck -c ./scripts/check-advisories.sh

verify: stage
    ./scripts/verify-upstream.sh

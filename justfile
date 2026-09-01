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

# Cheap gate for CI: proves the flake evaluates for all three systems.
eval: stage
    nix flake check --all-systems --no-build

fmt: stage
    nix fmt

build PKG: stage
    nix build -L .#{{ PKG }}

update PKG: stage
    nix-update --flake --version=stable {{ PKG }}

# aarch64-darwin has no CI runner while this repo is private, so this machine
# IS the darwin build farm: pushing from here is the only way anyone else gets
# a prebuilt Apple Silicon binary.
push-cache PKG: (build PKG)
    cachix push cypherpunktech ./result

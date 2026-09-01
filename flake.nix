# zcash.nix — Nix packages for the Zcash ecosystem.
#
# WHY THIS EXISTS: nixpkgs packages exactly two things from this ecosystem,
# `zcash` (the SUNSET zcashd) and `lightwalletd`. The whole post-zcashd stack —
# Zebra, the indexers, Zallet — is unpackaged. Everything here is built from
# pinned upstream source; nothing downloads a vendor binary.
{
  description = "Nix packages for the Zcash ecosystem: nodes, indexers, wallets";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      eachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # A package IS a directory under packages/. Adding one is adding a
      # directory — there is no list in this file to forget to edit. The
      # overlay and the packages output are this one function applied to
      # different package sets, so they cannot drift apart.
      packagesFor =
        pkgs:
        lib.genAttrs (lib.attrNames (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./packages)
        )) (name: pkgs.callPackage (./packages + "/${name}") { });

      # `nix flake check --all-systems` forces every package's drvPath, and
      # asking for the drvPath of a package whose own meta says it is
      # unsupported here is an eval error, not a skip. So the packages OUTPUT
      # carries only what a system can actually build. The overlay deliberately
      # stays unfiltered: `pkgs.zebra` should exist everywhere and fail with
      # nixpkgs' own "not available on this platform", the way every other
      # nixpkgs attribute does.
      availableFor =
        pkgs: lib.filterAttrs (_: lib.meta.availableOn pkgs.stdenv.hostPlatform) (packagesFor pkgs);

      # Running the binary is the only gate that catches wrapper and link
      # breakage; eval and even a green `nix build` both miss it (the lesson
      # from ~/nix/checks/default.nix). Each package states its own proof via
      # passthru.smokeArgs, so "how do I know this works" lives next to the
      # thing it is claimed about — and a package that answers nothing fails
      # loudly at eval rather than being silently unproven.
      smokeChecks =
        pkgs:
        lib.mapAttrs' (
          name: pkg:
          lib.nameValuePair "smoke-${name}" (
            pkgs.runCommandLocal "smoke-${name}" { } ''
              ${lib.getExe pkg} ${
                lib.escapeShellArgs (
                  pkg.smokeArgs
                    or (throw "packages/${name} must set passthru.smokeArgs: how does this binary prove it runs?")
                )
              } | tee $out
            ''
          )
        ) (availableFor pkgs);

      treefmtFor =
        pkgs:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          # Nix LINTERS, not just formatting: statix catches antipatterns,
          # deadnix catches bindings nothing reads. Both inside the one gate.
          programs.statix.enable = true;
          programs.deadnix.enable = true;
          programs.taplo.enable = true;
          programs.shfmt.enable = true;
          programs.shfmt.indent_size = 0; # tabs, shfmt's default and shellcheck's
        };
    in
    {
      overlays.default = final: _prev: packagesFor final;

      packages = eachSystem availableFor;

      checks = eachSystem (
        pkgs:
        smokeChecks pkgs
        // {
          formatting = (treefmtFor pkgs).config.build.check self;
        }
      );

      formatter = eachSystem (pkgs: (treefmtFor pkgs).config.build.wrapper);

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.cachix
            pkgs.just
            pkgs.nix-update
          ];
        };
      });
    };
}

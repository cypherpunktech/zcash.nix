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

  # Without this, using this flake means compiling a Zcash node from source --
  # about half an hour for zebra on a fast machine, considerably worse on a
  # laptop. The cache is public, so pulling needs no credential; the token only
  # ever exists on the pushing side.
  #
  # `extra-` prefixes, deliberately: these APPEND to the user's substituters
  # rather than replacing them, so a machine with its own carefully-pinned list
  # keeps it. Nix still asks before trusting a flake's nixConfig unless the user
  # is a trusted-user, which is the correct place for that decision to sit.
  #
  # aarch64-darwin binaries reach this cache only by being pushed from a
  # maintainer's Mac (`just push-cache <pkg>`): while the repo is private there
  # is no macOS runner, so nothing else can produce them.
  nixConfig = {
    extra-substituters = [ "https://cypherpunktech.cachix.org" ];
    extra-trusted-public-keys = [
      "cypherpunktech.cachix.org-1:WKo2WboMVH8HUtCKNsSFx31YQibaJ2eocruFvAzWgA4="
    ];
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

      # Modules follow the same rule as packages: a module IS a directory under
      # modules/, so adding one is adding a directory. hardening.nix sits
      # alongside them as a plain file, which the directory filter skips --
      # shared code is not a module and must not become one by accident.
      moduleNames = lib.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./modules)
      );

      # Each module is a function of `self` so it can default its `package`
      # option to this flake's build. That keeps `services.zcash.zebra.enable =
      # true` working with no overlay and no second place to state which
      # package a service runs.
      modules = lib.genAttrs moduleNames (name: import (./modules + "/${name}") self);

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

      # `nixosModules.default` turns everything on as options (not as running
      # services -- each still needs its own enable), so a consumer imports one
      # thing and then configures what they want.
      nixosModules = modules // {
        default.imports = lib.attrValues modules;
      };

      packages = eachSystem availableFor;

      # A NixOS VM test boots a machine and asserts the service runs, which is
      # the only check that covers the unit rather than the binary. They exist
      # only on Linux: nixosTest needs a Linux builder, so on darwin these are
      # absent rather than failing, and CI is where they actually run.
      nixosTests = eachSystem (
        pkgs:
        # isLinux is necessary but not sufficient: a VM test instantiates the
        # module, which resolves its package from packages.<system>, so a
        # system that claims no packages can produce no tests. aarch64-linux is
        # exactly that case today. Deriving the condition from the package set
        # rather than hardcoding a system means this corrects itself the moment
        # a package is proven on a new Linux target.
        lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux && availableFor pkgs != { }) (
          lib.mapAttrs' (
            file: _:
            let
              name = lib.removeSuffix ".nix" file;
            in
            lib.nameValuePair name (pkgs.testers.runNixOSTest (import (./tests + "/${file}") self))
          ) (lib.filterAttrs (f: _: lib.hasSuffix ".nix" f) (builtins.readDir ./tests))
        )
      );

      checks = eachSystem (
        pkgs:
        smokeChecks pkgs
        // lib.mapAttrs' (n: lib.nameValuePair "vm-${n}") self.nixosTests.${pkgs.stdenv.hostPlatform.system}
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

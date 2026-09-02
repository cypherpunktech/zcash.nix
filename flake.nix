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

      packageNames = lib.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./packages)
      );

      # Not legacyPackages: this instance permits building this flake's own
      # packages whatever their meta.license says. ztreamer's upstream has no
      # licence, so its derivation is honestly labelled `unfree`, and nixpkgs
      # refuses to evaluate an unfree derivation without consent. Here the
      # consent is the act of asking this flake for it: `nix run .#ztreamer`
      # builds public source on your own machine. The overlay is untouched, so
      # a consumer's nixpkgs still asks for allowUnfreePredicate as it should,
      # and the cache push filter still reads the label (discover.yml).
      eachSystem =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = p: builtins.elem (lib.getName p) packageNames;
            }
          )
        );

      # Rust binaries from nixpkgs' buildRustPackage are not bit-reproducible on
      # darwin: Hydra's own fd and ripgrep fail `nix build --rebuild` there. nix
      # runs every darwin build in /nix/var/nix/builds/nix-<pid>-<random>, and
      # no setting pins it -- the constant /build comes from the Linux chroot
      # builder, and sandbox-build-dir is not compiled on darwin. rustc bakes
      # that path into every vendored crate's panic locations; C sources built
      # through the `cc` crate bake it into __FILE__. buildGoModule passes
      # -trimpath. buildRustPackage passes nothing.
      #
      # Measured before being believed: a dependency-free Rust program
      # reproduces here; the same program with one dependency does not; with
      # the remap it does again. Applied once, to every Rust package through
      # the rustPlatform it receives, because the property belongs to "Rust on
      # this nixpkgs" rather than to any package. The channels are the point:
      #   NIX_RUSTFLAGS      -- the rustc wrapper APPENDS it; env RUSTFLAGS would
      #                         replace nixpkgs' own -Cforce-frame-pointers=yes.
      #   NIX_CFLAGS_COMPILE -- through the cc-wrapper for C and C++ alike;
      #                         exporting CXXFLAGS clobbers a crate's [env] one
      #                         (zaino sets `-include cstdint` that way).
      #   $NIX_BUILD_TOP is only known inside the builder, hence preBuild.
      #
      # The remap covers what the COMPILER writes. The LINKER has its own path
      # channel: N_OSO stabs, which record each object's path as ld64 saw it
      # on the link line, /nix/var/nix/builds/nix-<pid>-<random>/... -- no
      # rustc flag reaches them. Only objects carrying DWARF produce stabs; in
      # this tree that is ring's pregenerated assembly, built with -g. ld64
      # excludes stab STRINGS from the LC_UUID hash but not the offsets they
      # push around, and the random dir name is 19 or 20 characters, so about
      # one build in three shifted LC_CODE_SIGNATURE's offset and got a
      # different UUID with byte-identical content. Found by diffing unstripped
      # outputs and predicting each rebuild's result from its dir length
      # before seeing it. `-Wl,-S` makes ld64 emit no stabs at all; nixpkgs
      # strips them in fixupPhase anyway, so nothing that shipped is lost.
      #
      # A package can still embed its own build environment -- zaino read the
      # build user via whoami -- and that is fixed in the package, not here.
      reproducibleRustPlatform =
        pkgs:
        let
          # ld64's `-S`: emit no stabs. GNU ld spells --strip-debug the same
          # way, which would be harmless here but is not what this flag is
          # for, and on Linux the build dir is already constant. Darwin only.
          noStabs = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin " -C link-arg=-Wl,-S";
        in
        pkgs.rustPlatform
        // {
          buildRustPackage =
            args:
            pkgs.rustPlatform.buildRustPackage (
              args
              // {
                preBuild = ''
                  export NIX_RUSTFLAGS="''${NIX_RUSTFLAGS:-} --remap-path-prefix=$NIX_BUILD_TOP=/build${noStabs}"
                  export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:-} -ffile-prefix-map=$NIX_BUILD_TOP=/build"
                ''
                + (args.preBuild or "");
              }
            );
        };

      # Whether the licence lets binaries be served to others -- nixpkgs records
      # that per licence, a package may carry several, and a package that states
      # none gets no benefit of the doubt. This is what decides what reaches the
      # public cache (discover.yml, justfile), so it lives on the package.
      redistributable =
        pkg: pkg.meta ? license && lib.all (l: l.redistributable or false) (lib.toList pkg.meta.license);

      # A package IS a directory under packages/. Adding one is adding a
      # directory — there is no list in this file to forget to edit. The
      # overlay and the packages output are this one function applied to
      # different package sets, so they cannot drift apart.
      packagesFor =
        pkgs:
        lib.genAttrs packageNames (
          name:
          let
            package = import (./packages + "/${name}");
          in
          # callPackage passes explicit arguments unconditionally, and a Go
          # package that never asked for rustPlatform would reject it.
          (pkgs.callPackage package (
            lib.optionalAttrs (lib.functionArgs package ? rustPlatform) {
              rustPlatform = reproducibleRustPlatform pkgs;
            }
          )).overrideAttrs
            (o: {
              passthru = (o.passthru or { }) // {
                redistributable = redistributable o;
              };
            })
        );

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

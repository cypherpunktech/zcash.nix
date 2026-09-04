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
  # CI fills it for all three systems (discover.yml decides the runners);
  # `just push-cache <pkg>` lets a maintainer publish a build ahead of CI.
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
      # none gets no benefit of the doubt. This is what decides whether a CI
      # run may push to the public cache at all (discover.yml), so it lives on
      # the package.
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

      # OCI images: the distribution door for the operators who deploy
      # containers rather than NixOS. One per redistributable package -- the
      # licence rule decides, the same `redistributable` that gates the cache
      # push in discover.yml -- and only for Linux, since that is what a
      # container is. Nothing in the image that the package did not need:
      # its closure, CA certificates for TLS, /data for state, /tmp. Runs as
      # uid 1000 with HOME=/data, so every daemon's home-directory default
      # (zebra's ~/.cache, zaino's ~/.local) lands in the one volume without
      # per-image knowledge of where each puts things. The entrypoint is the
      # package's mainProgram; every binary the package ships is on PATH for
      # an operator who overrides it. Tag is the version and nothing else: a
      # node operator pins, and a `latest` on a consensus node is a footgun.
      imagesFor =
        pkgs:
        lib.mapAttrs (
          name: pkg:
          pkgs.dockerTools.buildLayeredImage {
            name = "ghcr.io/cypherpunktech/${name}";
            tag = pkg.version;
            contents = [
              pkg
              pkgs.cacert
            ];
            fakeRootCommands = ''
              mkdir -p ./data ./tmp
              chown 1000:1000 ./data
              chmod 1777 ./tmp
            '';
            config = {
              Entrypoint = [ (lib.getExe pkg) ];
              User = "1000:1000";
              WorkingDir = "/data";
              Env = [
                "HOME=/data"
                "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              ];
              Volumes."/data" = { };
              Labels = {
                "org.opencontainers.image.title" = name;
                "org.opencontainers.image.version" = pkg.version;
                "org.opencontainers.image.description" = pkg.meta.description;
                "org.opencontainers.image.source" = "https://github.com/cypherpunktech/zcash.nix";
                "org.opencontainers.image.url" = pkg.meta.homepage;
                "org.opencontainers.image.licenses" = lib.concatMapStringsSep "," (l: l.spdxId or l.shortName) (
                  lib.toList pkg.meta.license
                );
              };
            };
          }
        ) (lib.filterAttrs (_: pkg: pkg.redistributable) (availableFor pkgs));

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

      # `nix build .#images.x86_64-linux.zebra` gives a docker-archive to
      # `docker load`; CI pushes them to ghcr.io/cypherpunktech/<name> per
      # architecture and stitches the manifest (check.yml). Linux only: an
      # image is a Linux root filesystem, and a darwin host cannot build one.
      images = eachSystem (pkgs: lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (imagesFor pkgs));

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

      devShells = eachSystem (
        pkgs:
        let
          packages = availableFor pkgs;
        in
        {
          # For working on THIS repository.
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.just
              pkgs.nix-update
            ];
          };

          # For working on the Zcash software itself: the exact toolchain and
          # native inputs (rustc, protoc, the bindgen hook and its libclang,
          # go) that make zebra, zaino and lightwalletd build here, taken from
          # the derivations rather than restated. `cargo build` in a zebra
          # checkout works inside it; nothing is on PATH that the packages
          # did not need.
          zcash = pkgs.mkShell {
            inputsFrom = lib.attrValues packages;
            packages = [ pkgs.cargo-audit ];
          };
        }
      );

      # CONTRIBUTING.md's "Adding a package", executable:
      #   mkdir packages/<name> && cd packages/<name> && nix flake init -t ../..#package
      templates.package = {
        path = ./templates/package;
        description = "A packages/<name>/default.nix skeleton with every field this repository requires";
        welcomeText = ''
          Fill in the placeholders, then from the repository root:

          ```
          git add -A                  # flakes see only tracked files
          nix build .#<name>          # twice: once per fake hash
          nix run .#<name> -- --version
          just check
          ```
        '';
      };

      # What a third-party packager of a Zcash tool actually needs from here:
      # not the nine packages, the property that Rust built on this nixpkgs
      # is bit-reproducible on darwin (see reproducibleRustPlatform), and the
      # licence-derived answer to "may I put this in a public cache".
      lib = {
        inherit reproducibleRustPlatform redistributable;
      };
    };
}

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
  # CI fills it for all three systems (discover.yml decides the runners) and
  # is its only writer: a laptop push would be a second, unreviewed signer.
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

      # The contract a package signs by existing, checked where the package
      # is made: no evaluation of this flake can see a package that breaks it,
      # so `nix flake check`, discover.yml and every script trip on the same
      # throw instead of each discovering a missing field at run time.
      # CONTRIBUTING.md lists these fields; this is the copy that cannot drift
      # from what is enforced. Platforms are the sharpest: a claim outside
      # `systems` is a platform no runner will ever prove (AGENTS.md).
      contract =
        name: pkg:
        let
          need = what: ok: lib.throwIfNot ok "packages/${name}: ${what}";
        in
        need "meta.description must be non-empty" (pkg.meta.description or "" != "") (
          need "meta.homepage" (pkg.meta ? homepage) (
            need "meta.license" (pkg.meta ? license) (
              need "meta.mainProgram: lib.getExe and nix run depend on it" (pkg.meta ? mainProgram) (
                need "passthru.smokeArgs: how does this binary prove it runs?" (pkg ? smokeArgs) (
                  need "src.rev: check-staleness.sh and verify-upstream.sh read it" (pkg.src ? rev) (
                    need "meta.platforms must be a subset of ${toString systems}" (lib.all (p: lib.elem p systems) (
                      pkg.meta.platforms or [ ]
                    )) pkg
                  )
                )
              )
            )
          )
        );

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
          contract name (
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
          )
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
                # The tag is the version and is re-pushed on every push to
                # main; this is what says which commit a pulled image is from
                # (published.yml asserts it is main's tip).
                "org.opencontainers.image.revision" = self.rev or "dirty";
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
      # thing it is claimed about (`contract` refuses a package without one).
      #
      # The same derivation makes the second claim about what ships: nothing
      # in the runtime closure is a compiler, linker or protobuf. A bindgen
      # hook that wrote LIBCLANG_PATH into a binary, or a baked PROTOC path,
      # turns a 90 MB image into a 2 GB one and is invisible to every other
      # gate. gcc's runtime library is the one legitimate hit: Rust links it.
      smokeChecks =
        pkgs:
        lib.mapAttrs' (
          name: pkg:
          lib.nameValuePair "smoke-${name}" (
            pkgs.runCommandLocal "smoke-${name}" { closure = pkgs.closureInfo { rootPaths = [ pkg ]; }; } ''
              ${lib.getExe pkg} ${lib.escapeShellArgs pkg.smokeArgs} | tee $out
              if sed 's|^/nix/store/[a-z0-9]*-||' "$closure/store-paths" \
                | grep -E '^(rustc|cargo|go|clang|llvm|protobuf|binutils|gcc)-[0-9]' \
                | grep -vE '^gcc-[0-9.]+-lib(gcc)?$'; then
                echo "packages/${name}: build tools in the runtime closure (above)" >&2
                exit 1
              fi
            ''
          )
        ) (availableFor pkgs);

      # The scripts behind the trust gates (trust.yml, stale.yml, `just`),
      # packaged with the tools they call. Two things this buys over a bare
      # `bash scripts/x.sh`: the tools are the lock's, not the runner image's
      # -- verify-upstream.sh's git and ssh-keygen ARE the security property
      # -- and writeShellApplication runs shellcheck at build time. `nix` is
      # deliberately not among them: the one on PATH is the daemon's. The
      # files stay files: readable, greppable, runnable by hand.
      commands =
        pkgs:
        lib.mapAttrs
          (
            name:
            {
              file,
              tools,
              description,
            }:
            pkgs.writeShellApplication {
              inherit name;
              runtimeInputs = tools;
              text = builtins.readFile (./scripts + "/${file}");
              meta = { inherit description; };
            }
          )
          {
            audit = {
              file = "check-advisories.sh";
              tools = with pkgs; [
                cargo-audit
                govulncheck
                jq
              ];
              description = "cargo-audit and govulncheck over the lockfile each package vendors";
            };
            verify = {
              file = "verify-upstream.sh";
              tools = with pkgs; [
                git
                openssh
                gnutar
                jq
              ];
              description = "where upstream signs its tags, the pinned source is what the maintainer signed";
            };
            stale = {
              file = "check-staleness.sh";
              tools = with pkgs; [
                gh
                jq
              ];
              description = "every package is close to upstream's latest release";
            };
            fods = {
              file = "check-fods.sh";
              tools = with pkgs; [ jq ];
              description = "every hash typed into packages/ still re-fetches to the bytes it names";
            };
          };

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
      # package a service runs. The module system records a declaring file
      # only for path imports; a module imported as a value here would have
      # every option and error attributed to flake.nix, so each is told its
      # own file.
      modules = lib.genAttrs moduleNames (
        name:
        lib.setDefaultModuleLocation "${self}/modules/${name}/default.nix" (
          import (./modules + "/${name}") self
        )
      );

      # The options reference, rendered from the modules by nixpkgs' own tool
      # so it cannot disagree with them. Evaluated outside NixOS: descriptions
      # and types need no system, and `_module.check = false` lets the
      # modules' systemd, users and firewall definitions go unmatched.
      # docs/options.md is the committed rendering; checks.options-doc fails
      # while it is stale and `just docs` regenerates it.
      optionsDoc =
        pkgs:
        pkgs.nixosOptionsDoc {
          options =
            (lib.evalModules {
              modules = lib.attrValues modules ++ [ { _module.check = false; } ];
              specialArgs = { inherit pkgs; };
            }).options.services.zcash;
          # Declarations as name/url pairs: a bare string is rendered as a
          # nixpkgs file, and these are not nixpkgs.
          transformOptions =
            o:
            o
            // {
              declarations = map (
                d:
                let
                  file = lib.removePrefix "${self}/" (toString d);
                in
                {
                  name = file;
                  url = "https://github.com/cypherpunktech/zcash.nix/blob/main/${file}";
                }
              ) o.declarations;
            };
        };

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
          # shfmt formats; shellcheck finds the `$?`-after-a-pipe class of bug
          # in the scripts CI runs. .envrc is direnv's, not bash.
          programs.shellcheck.enable = true;
          settings.formatter.shellcheck.excludes = [ ".envrc" ];
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
      # the only check that covers the unit rather than the binary. The guest
      # is always Linux; the host need not be. nixpkgs pairs an aarch64-darwin
      # host with an aarch64-linux guest under HVF and asks only for a Linux
      # remote builder for the guest's closure (nix-darwin's
      # `nix.linux-builder`), so the tests exist wherever a package set does.
      # `checks` below keeps them to Linux hosts, so `nix flake check` on a
      # Mac needs no builder; `nix run .#nixosTests.<system>.<t>.driverInteractive`
      # is the local loop. CI runs them on x86_64-linux with KVM.
      nixosTests = eachSystem (
        pkgs:
        lib.optionalAttrs (availableFor pkgs != { }) (
          lib.mapAttrs' (
            file: _:
            let
              name = lib.removeSuffix ".nix" file;
            in
            lib.nameValuePair name (
              pkgs.testers.runNixOSTest {
                imports = [ (import (./tests + "/${file}") self) ];
                # Every machine has every module and the dead-network Regtest
                # node defined once (tests/fixtures/regtest.nix), so a test
                # states only what it enables. Subdirectories are fixtures,
                # not tests: the filter below takes files.
                defaults.imports = [
                  self.nixosModules.default
                  ./tests/fixtures/regtest.nix
                ];
              }
            )
          ) (lib.filterAttrs (f: _: lib.hasSuffix ".nix" f) (builtins.readDir ./tests))
        )
      );

      checks = eachSystem (
        pkgs:
        smokeChecks pkgs
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
          lib.mapAttrs' (n: lib.nameValuePair "vm-${n}") self.nixosTests.${pkgs.stdenv.hostPlatform.system}
        )
        // {
          formatting = (treefmtFor pkgs).config.build.check self;

          # The units test's machine is a NixOS system with every module
          # enabled. Forcing its drvPath evaluates every assertion, option
          # type and unit definition, and needs no builder -- so this runs
          # under `nix flake check --no-build` on every system, including a
          # Mac, before the VM test ever boots it. AGENTS.md's manual
          # "evaluate a real system" advice, as a gate.
          # The context is discarded because forcing the path is the whole
          # check; keeping it would make this derivation depend on BUILDING
          # that system, which is the VM test's job.
          # docs/options.md is what the modules currently say; anything else
          # is stale, and `just docs` is the fix. The committed file travels
          # as a string so nothing is copied into the store for a comparison.
          options-doc =
            pkgs.runCommandLocal "options-doc"
              {
                committed = builtins.readFile ./docs/options.md;
                passAsFile = [ "committed" ];
              }
              ''
                if ! diff -u "$committedPath" ${self.docs.${pkgs.stdenv.hostPlatform.system}} | tee $out; then
                  echo "docs/options.md is stale: run \`just docs\` and commit the result" >&2
                  exit 1
                fi
              '';

          eval-units = pkgs.runCommandLocal "eval-units" {
            drv = builtins.unsafeDiscardStringContext self.nixosTests.x86_64-linux.units.nodes.machine.system.build.toplevel.drvPath;
          } "echo $drv > $out";
        }
      );

      formatter = eachSystem (pkgs: (treefmtFor pkgs).config.build.wrapper);

      # `nix build .#docs.<system>`: the options reference as CommonMark.
      docs = eachSystem (pkgs: (optionsDoc pkgs).optionsCommonMark);

      # `nix run .#audit|verify|stale|fods`; `nix flake show` lists them with
      # what each claims.
      apps = eachSystem (
        pkgs:
        lib.mapAttrs (_: drv: {
          type = "app";
          program = lib.getExe drv;
          meta = { inherit (drv.meta) description; };
        }) (commands pkgs)
      );

      devShells = eachSystem (
        pkgs:
        let
          packages = availableFor pkgs;
        in
        {
          # For working on THIS repository.
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.jq
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

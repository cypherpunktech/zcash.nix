# zaino — Zingo Labs' indexer and proxy server for the Zcash protocol.
#
# Upstream ships its own flake, but it pulls in crane and fenix to pin a
# toolchain by hash. nixpkgs' rustc is 1.97, comfortably past zaino's 1.96 MSRV,
# so this build needs neither: it is the same two inputs as every other package
# here, and it gets the same smoke check and the same auto-updater.
#
# Upstream's nix/package.nix also points librocksdb-sys at a prebuilt
# nixpkgs rocksdb to skip a C++ compile. That is an optimisation, not a
# requirement — librocksdb-sys builds its bundled copy fine with the bindgen
# hook alone, and one fewer moving part is worth more here than the minutes.
#
# Version bumps: `just update zaino`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
let
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "zingolabs";
    repo = "zaino";
    # Upstream tags releases without a `v` prefix.
    tag = version;
    hash = "sha256-fOtSK4OvOMXwv8RcjH26Vz5pvY2VrtekW7hQ2i430ak=";
  };
in
rustPlatform.buildRustPackage {
  pname = "zaino";
  inherit version src;

  cargoHash = "sha256-qeFIEH+CtZi/gJApR/s0RyYNI5xODz7YPIeORSZAIIc=";

  # zainod is the server. The workspace's other members are libraries plus a
  # benchmark harness and two live-test suites that upstream deliberately keeps
  # out of its own default build.
  cargoBuildFlags = [
    "-p"
    "zainod"
  ];

  # Rust embeds absolute source paths for panic messages and backtraces, and
  # nix's build directory is named with a pid and a random number
  # (/builds/nix-69568-3116585407/...). So the path leaks into the binary and
  # every rebuild produces different bytes -- measured with `nix build
  # --rebuild`, which found exactly two differences: the vendored crate paths,
  # and the Mach-O LC_UUID that ld64 derives from a content hash and which
  # therefore only changed because the paths did.
  #
  # --remap-path-prefix rewrites them to a constant. It has to be exported here
  # rather than set in `env`, because $NIX_BUILD_TOP is only known once the
  # builder is running.
  #
  # This is why lightwalletd reproduces and the Rust packages do not:
  # buildGoModule passes -trimpath, and buildRustPackage has no equivalent.
  # Two flags because two compilers embed the path. rustc needs
  # --remap-path-prefix; the C sources that -sys crates compile through the
  # `cc` crate need -ffile-prefix-map, and rustc's flag does nothing for them.
  # Measured: the rust flag alone remapped 1077 paths and left 81, all of them
  # __FILE__ strings from aws-lc-sys and lmdb-sys.
  preBuild = ''
    remap="$NIX_BUILD_TOP=/zcash-nix-build"
    export RUSTFLAGS="''${RUSTFLAGS:-} --remap-path-prefix=$remap"
    export CFLAGS="''${CFLAGS:-} -ffile-prefix-map=$remap"
    export CXXFLAGS="''${CXXFLAGS:-} -ffile-prefix-map=$remap"
  '';

  doCheck = false;

  nativeBuildInputs = [
    protobuf
    rustPlatform.bindgenHook
  ];

  env = {
    PROTOC = "${protobuf}/bin/protoc";

    # zaino-state's build.rs stamps the binary with build info, falling back to
    # `git rev-parse` when these are unset. There is no git in the sandbox and
    # no .git in the source -- it arrives as a tarball -- so without these the
    # build dies with `git failed: No such file or directory`. Putting git into
    # the derivation would "fix" it by letting a build shell out to a host tool,
    # which is the thing that makes a derivation stop being reproducible.
    #
    # The value is src.rev rather than a copied-out commit sha, so it is exactly
    # the ref that was built and moves with the pin automatically. A second copy
    # of the revision here is a copy nix-update would not know to bump.
    ZAINO_GIT_COMMIT_ID = src.rev;
    ZAINO_GIT_BRANCH = src.rev;
  };

  passthru.smokeArgs = [ "--version" ];

  meta = {
    description = "Indexer and proxy server for the Zcash protocol";
    homepage = "https://github.com/zingolabs/zaino";
    license = lib.licenses.asl20;
    mainProgram = "zainod";
    # Every platform here has been built AND had its binary run. x86_64-linux
    # and aarch64-linux by CI; aarch64-darwin on a maintainer's machine, which
    # is the weakest of the three and stays that way until macOS runners are
    # affordable (CI_MACOS in .github/workflows/discover.yml).
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

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

  # zaino-state's build.rs also stamps the binary with whoami::username(), and
  # on darwin that is whichever _nixbld<N> the daemon hands the build. Two
  # builds got different users and produced different binaries; when N went
  # from one digit to two the string outgrew rustc's immediate encoding, moved
  # to rodata, and shifted the entire text section by four bytes. It hid from
  # `strings` for exactly that reason -- an 8-byte value lives in mov/movk
  # immediates -- which is how it was first ruled out and then found by
  # disassembly.
  #
  # whoami reads getpwuid, so no env var neutralises it. The patch gives
  # build.rs an override in the same shape as its existing ZAINO_GIT_* ones;
  # --replace-fail makes the build stop the day upstream changes the line.
  postPatch = ''
    substituteInPlace packages/zaino-state/build.rs \
      --replace-fail 'whoami::username().unwrap_or_default()' \
                     'std::env::var("ZAINO_BUILD_USER").unwrap_or_else(|_| whoami::username().unwrap_or_default())'
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
    # Read by the override patched into build.rs above.
    ZAINO_BUILD_USER = "nix";
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

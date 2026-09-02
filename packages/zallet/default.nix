# zallet — the RPC wallet that replaces zcashd's embedded wallet.
#
# WHY THIS IS TWO DERIVATIONS AND A COPY:
#
# `zallet` is only a launcher. It reads the config's `backend` key and `exec`s a
# sibling `zallet-<backend>` binary, looked up next to its own executable first
# and then on PATH; with no config it uses the default, "zebra". So a package
# containing the launcher alone builds cleanly, installs cleanly, and cannot run.
#
# The backend lives in backends/zebra, which upstream deliberately made its own
# workspace root with its own lockfile: librocksdb-sys declares `links =
# "rocksdb"`, so two zebra-state versions cannot coexist in one resolution graph
# (zcash/zallet#540). Its own workspace means its own vendor and its own hash --
# that is a fact about the software, not a choice made here.
#
# The two are combined by COPYING rather than symlinkJoin: the launcher finds
# its backend through env::current_exe(), which resolves symlinks, so a
# symlinked bin/ would send it back to the launcher's own store path where no
# sibling exists. Real files in one directory are what the lookup requires.
#
# Version bumps: `just update zallet` updates the launcher; the backend shares
# `version` and `src` with it, so both move together as upstream ships them.
{
  lib,
  stdenvNoCC,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
  pkg-config,
}:
let
  version = "0.1.0-beta.3";

  src = fetchFromGitHub {
    owner = "zcash";
    repo = "zallet";
    tag = "v${version}";
    hash = "sha256-MyfjXpxnNojsT3BjFvtk5x2ODODxdgYIiGkYXvot1YI=";
  };

  # Shared by both builds: upstream's Dockerfile installs clang/libclang for
  # bindgen and the *-sys C/C++ dependencies, plus protobuf for tonic.
  common = {
    inherit version src;
    doCheck = false;
    nativeBuildInputs = [
      protobuf
      pkg-config
      rustPlatform.bindgenHook
    ];
    env.PROTOC = "${protobuf}/bin/protoc";
  };

  launcher = rustPlatform.buildRustPackage (
    common
    // {
      pname = "zallet-launcher";
      cargoHash = "sha256-WGF10fXWNfEUD4tStKXasi6XVnAntc2KGMItrYbI0v8=";
      cargoBuildFlags = [
        "-p"
        "zallet"
      ];
    }
  );

  backend = rustPlatform.buildRustPackage (
    common
    // {
      pname = "zallet-zebra";
      sourceRoot = "${src.name}/backends/zebra";
      cargoHash = "sha256-vGYOZlp0MQNld94WWhMYVflzMZ0pIHA/eXu8KeK3eG4=";
    }
  );
in
stdenvNoCC.mkDerivation {
  pname = "zallet";
  inherit version;

  # This derivation only copies two other derivations' binaries together, so it
  # has nothing to unpack -- but it still carries `src`, because src.rev is how
  # check-staleness.sh and update.yml learn what this package is pinned to. A
  # package that cannot state its own provenance is a package the staleness
  # gate cannot check, which is worse than one that is merely out of date.
  inherit src;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${launcher}/bin/zallet $out/bin/zallet
    cp ${backend}/bin/zallet-zebra $out/bin/zallet-zebra
    runHook postInstall
  '';

  # The launcher does not answer --version itself: it passes every argument
  # through to the backend via exec. So a green smoke check here proves the
  # thing that actually matters for this package -- that both halves shipped and
  # the sibling lookup resolves -- rather than merely that a binary can print.
  # A launcher packaged without its backend passes `nix build` and fails here.
  passthru.smokeArgs = [ "--version" ];
  # What repro.yml rebuilds. Rebuilding this derivation only re-runs the two
  # `cp`s above, which reproduce trivially while saying nothing about the
  # compilers underneath.
  passthru.parts = [
    launcher
    backend
  ];

  meta = {
    description = "RPC wallet replacing the deprecated zcashd embedded wallet";
    homepage = "https://github.com/zcash/zallet";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "zallet";
    # Every platform here has been built AND had its binary run, by CI on all
    # three (.github/workflows/discover.yml decides the runners).
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

# zinder — the Zcash Foundation's service-oriented Zcash indexer.
#
# Indexes the chain once from a Zebra node and serves it to many wallets through
# both its native WalletQuery gRPC API and a drop-in lightwalletd compatibility
# surface. nixpkgs has no indexer for the post-zcashd stack at all.
#
# Version bumps: `just update zinder`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
let
  version = "0.6.0";
in
rustPlatform.buildRustPackage {
  pname = "zinder";
  inherit version;

  src = fetchFromGitHub {
    owner = "ZcashFoundation";
    repo = "zinder";
    tag = "v${version}";
    hash = "sha256-mWywB29eIjB2ZxKB2/UCiGrFBUJJe8OMV5O1Cj+eLnM=";
  };

  cargoHash = "sha256-Fc6S08nUMPnGAR75/Jq7NAH8KsehKVDG/H2lpK8gCjg=";

  # Upstream's documented wallet-serving topology is four independent runtimes on
  # one host: ingest owns canonical storage, projector derives the wallet view,
  # query serves native clients, and compat-lightwalletd serves existing ones.
  # The other workspace services are a benchmark harness, an explorer plane and a
  # cipherscan adapter — none of them part of that topology.
  cargoBuildFlags = [
    "-p"
    "zinder-ingest"
    "-p"
    "zinder-projector"
    "-p"
    "zinder-query"
    "-p"
    "zinder-compat-lightwalletd"
  ];

  doCheck = false;

  nativeBuildInputs = [
    protobuf
    rustPlatform.bindgenHook
  ];

  env.PROTOC = "${protobuf}/bin/protoc";

  # zinder-query is the native serving plane and the one an operator points a
  # wallet at, so it is the package's mainProgram.
  passthru.smokeArgs = [ "--version" ];

  meta = {
    description = "Service-oriented Zcash indexer with native and lightwalletd APIs";
    homepage = "https://github.com/ZcashFoundation/zinder";
    license = lib.licenses.mit;
    mainProgram = "zinder-query";
    # aarch64-darwin is proved on a maintainer's machine, x86_64-linux by CI.
    # aarch64-linux is NOT listed: no runner has ever built it, and a platform
    # nobody has compiled is a claim, not a fact. It goes back in the moment a
    # build there is green -- see CI_ALL_PLATFORMS in .github/workflows/discover.yml.
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
  };
}

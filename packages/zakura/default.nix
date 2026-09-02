# zakura — a Zcash full node built for scale.
#
# A fork of Zebra, so this derivation is deliberately near-identical to
# packages/zebra: same protobuf + bindgen build inputs, same reasons. Where the
# two differ, the difference is real rather than stylistic.
#
# Version bumps: `just update zakura`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
let
  version = "1.3.1";
in
rustPlatform.buildRustPackage {
  pname = "zakura";
  inherit version;

  src = fetchFromGitHub {
    owner = "zakura-core";
    repo = "zakura";
    tag = "v${version}";
    hash = "sha256-Qboofl36wAeCFJeDcM7nPL1nYXrt9cd39Q6fUmxxBFw=";
  };

  cargoHash = "sha256-wK4iFs/KvOZP+JG6xtcyWv8W1iURTD4HUxPTGQ2ItFU=";

  # The crate is `zakura`; the binaries it produces are zakurad and the two
  # state-repair tools, which are the operator's recovery path and belong
  # alongside the node rather than in a separate package.
  cargoBuildFlags = [
    "-p"
    "zakura"
  ];

  # `indexer` is off in upstream's default build and required by zallet: it
  # adds a spending-transaction index to the state database (the on-disk
  # format version carries `+indexer`), which zallet's backend, compiled with
  # the same feature, reads directly. A node without it produces a database
  # the wallet cannot use, and services.zcash.zallet would be a lie.
  buildFeatures = [ "indexer" ];

  # Node integration tests: they want live peers and real chain state.
  doCheck = false;

  nativeBuildInputs = [
    protobuf
    rustPlatform.bindgenHook
  ];

  env.PROTOC = "${protobuf}/bin/protoc";

  passthru.smokeArgs = [ "--version" ];

  meta = {
    description = "Zcash full node, built for scale";
    homepage = "https://github.com/zakura-core/zakura";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "zakurad";
    # Every platform here has been built AND had its binary run, by CI on all
    # three (.github/workflows/discover.yml decides the runners).
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

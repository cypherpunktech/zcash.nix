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
  version = "1.3.0";
in
rustPlatform.buildRustPackage {
  pname = "zakura";
  inherit version;

  src = fetchFromGitHub {
    owner = "zakura-core";
    repo = "zakura";
    tag = "v${version}";
    hash = "sha256-5bYRYINP7GEE1EtwrbUPo/W1kzlIxQqGpSAWwETN1Js=";
  };

  cargoHash = "sha256-SEwQzAWYMaI5hJoAgqHAx37qGIe1pQCvze+QImM+iOI=";

  # The crate is `zakura`; the binaries it produces are zakurad and the two
  # state-repair tools, which are the operator's recovery path and belong
  # alongside the node rather than in a separate package.
  cargoBuildFlags = [
    "-p"
    "zakura"
  ];

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

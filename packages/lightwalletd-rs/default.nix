# lightwalletd-rs — the Go lightwalletd's job, in Rust.
#
# The same role and the same flags as packages/lightwalletd: a caching proxy
# between a full node's JSON-RPC and shielded light wallets' gRPC. Packaged
# beside it rather than instead of it: an operator choosing between the two
# implementations of the CompactTxStreamer service should be able to run
# either from here, with the same module shape.
#
# Its optional `readstate` feature reads a co-located zebrad's state database
# directly, as zallet's backend does. Off, as upstream ships it: it pulls the
# whole zebra crate tree and RocksDB into the build, and the default RPC
# backend is the one every existing lightwalletd deployment already uses.
#
# Version bumps: `just update lightwalletd-rs`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
let
  version = "0.1.1";
in
rustPlatform.buildRustPackage {
  pname = "lightwalletd-rs";
  inherit version;

  src = fetchFromGitHub {
    owner = "jpgonzalezra";
    repo = "lightwalletd-rs";
    tag = "v${version}";
    hash = "sha256-bF4elAXr4OUizlGiIEKkRa4Gatko3TirxViwtDGqwm8=";
  };

  cargoHash = "sha256-HI01uBfZffRDyNJuSim5leYq+UdR+bylqGfhJhWAffU=";

  # Integration tests drive a darkside node; not a sandbox thing.
  doCheck = false;

  # tonic-prost-build compiles proto/*.proto at build time. build.rs also
  # stamps GIT_COMMIT from `git rev-parse`, and is written to leave it empty
  # when there is no git -- which there is not, here -- so nothing to patch.
  nativeBuildInputs = [ protobuf ];
  env.PROTOC = "${protobuf}/bin/protoc";

  # No --version: clap is configured without one upstream. --help exercises
  # argument parsing and exits 0, which is what a smoke check needs.
  passthru.smokeArgs = [ "--help" ];

  # Upstream signs release tags (ssh). See packages/zinder for what this
  # buys and scripts/verify-upstream.sh for what is checked.
  passthru.upstreamSigners = ./allowed_signers;

  meta = {
    description = "Rust lightwalletd: caching gRPC proxy for Zcash shielded light wallets";
    homepage = "https://github.com/jpgonzalezra/lightwalletd-rs";
    license = lib.licenses.mit;
    mainProgram = "lightwalletd-rs";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

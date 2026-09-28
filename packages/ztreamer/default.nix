# ztreamer — a light-wallet server with a Zcash full node inside it.
#
# ztreamerd embeds zakura as a library: one process syncs the chain, builds a
# compact index in LMDB, and serves CompactTxStreamer over gRPC. There is no
# separate node to run beside it, which is why there is no stack module
# composing the two -- the composition already happened upstream, in Rust.
#
# What that embedding is built against matters: not zakura-core's release but
# the author's own fork of it (distractedm1nd/zakura, branch `indexing`, a few
# commits of "api wrappers for embedding" ahead of upstream). Cargo.lock pins
# that fork at a commit, and cargoHash covers it, so the build is exactly as
# reproducible as any other here; it is just not zakura-core's code, and a
# zakura release does not reach this package until the fork rebases.
#
# No release has been cut, so this is rev-pinned in nixpkgs' `0-unstable-`
# form, as zpay is; `just update ztreamer` moves it to the branch head.
#
# LICENSE: upstream has none yet. Labelled unfreeRedistributable -- no grant
# to modify, redistributed anyway by the maintainers' decision -- so it is
# cached and imaged like every other package. Consumers using the overlay
# still need allowUnfreePredicate. A LICENSE upstream changes this line.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
let
  version = "0.1.0-unstable-2026-09-25";
in
rustPlatform.buildRustPackage {
  pname = "ztreamer";
  inherit version;

  src = fetchFromGitHub {
    owner = "distractedm1nd";
    repo = "ztreamer";
    rev = "b7b42d2345859e4589214829e40d6b5fea84729f";
    hash = "sha256-P3HvMDwS0BVRYPlfar6JaEHK4jpC6Ukr08c3WWS9Cz4=";
  };

  cargoHash = "sha256-8MLspNnBXHF4a/VcTDSZhqv+UAZjIITSgsh/fmDC8e8=";

  cargoBuildFlags = [
    "-p"
    "ztreamerd"
  ];

  # The workspace's tests are the embedded node's: peers and chain state.
  doCheck = false;

  # The embedded zakura brings zebra's build needs with it: protobuf for the
  # gRPC protocols (ztreamer's own CompactTxStreamer definition too, via
  # tonic-prost-build) and bindgen for rocksdb. LMDB comes bundled with heed.
  nativeBuildInputs = [
    protobuf
    rustPlatform.bindgenHook
  ];

  env.PROTOC = "${protobuf}/bin/protoc";

  passthru.smokeArgs = [ "--version" ];

  meta = {
    description = "Light-wallet server (CompactTxStreamer) with an embedded zakura node";
    homepage = "https://github.com/distractedm1nd/ztreamer";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "ztreamerd";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

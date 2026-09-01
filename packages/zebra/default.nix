# zebra — the Zcash Foundation's Zcash full node.
#
# WHY THIS EXISTS: nixpkgs' only Zcash node is `zcash` 5.4.2, i.e. zcashd, which
# is sunset. Zebra is the maintained replacement and has no nixpkgs attribute at
# all. This derivation is the anchor of the repo.
#
# Version bumps: `just update zebra`. Never hand-write a hash — set it to
# lib.fakeHash, build, and copy the real one out of the error.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
let
  version = "6.3.0";
in
rustPlatform.buildRustPackage {
  pname = "zebra";
  inherit version;

  src = fetchFromGitHub {
    owner = "ZcashFoundation";
    repo = "zebra";
    # `tag`, not `rev`: the hash below is what actually pins the bytes, so the
    # field's job is to say which release this is. A moved tag changes the hash
    # and fails the build loudly rather than silently building something else.
    tag = "v${version}";
    hash = "sha256-EBsibjSdKLaYB/Tr8q6jzr6QJiix8cG1HD2QeuBJG1k=";
  };

  # cargoHash (fetchCargoVendor), not cargoLock.lockFile: the lockfiles across
  # this repo's packages carry git dependencies, which fetchCargoVendor resolves
  # on its own where cargoLock would demand a hand-maintained outputHashes map.
  # One mechanism for all six packages.
  cargoHash = "sha256-74fx7YjxAUaL0sFBJcVVt0pMEf1iuvK1IG9Rg78gH38=";

  # The workspace also builds zebra-utils' developer tools. They are
  # feature-gated, useful to Zebra maintainers rather than node operators, and
  # would be dead weight in the closure. The node is the point.
  cargoBuildFlags = [
    "-p"
    "zebrad"
  ];

  # Zebra's suite is node integration testing: it wants live network peers and
  # real chain state, neither of which exists in the sandbox. The smoke check
  # that runs the binary is this package's actual proof.
  doCheck = false;

  nativeBuildInputs = [
    protobuf
    # librocksdb-sys runs bindgen. The hook sets LIBCLANG_PATH without dragging
    # all of LLVM into the build. These two are exactly what zebra's own
    # docker/Dockerfile apt-installs: libclang-dev and protobuf-compiler.
    rustPlatform.bindgenHook
  ];

  env.PROTOC = "${protobuf}/bin/protoc";

  passthru.smokeArgs = [ "--version" ];

  meta = {
    description = "Zcash Foundation's independent, consensus-compatible Zcash node";
    homepage = "https://zfnd.org/zebra/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "zebrad";
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

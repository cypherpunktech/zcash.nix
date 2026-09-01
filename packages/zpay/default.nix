# zpay — a Zcash-native payments facilitator.
#
# x402 and MPP wire adapters over one protocol-neutral core, settling shielded
# ZEC. zspend-runtime is the wallet half: it signs transactions under a bounded
# payment_authorization grant, and is useless without the facilitator, so both
# binaries ship together.
#
# PINNED BY COMMIT, not tag: upstream has cut no releases. That is why the
# version carries the commit date in nixpkgs' `-unstable-` form, why
# update.yml asks nix-update for `branch` rather than `stable` here, and why
# check-staleness.sh measures this package against its commit age instead of a
# release. All three branch on the same field, src.rev.
#
# Version bumps: `just update zpay`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
}:
rustPlatform.buildRustPackage {
  pname = "zpay";
  version = "0.1.0-unstable-2026-07-21";

  src = fetchFromGitHub {
    owner = "gustavovalverde";
    repo = "zpay";
    rev = "94828c784ae1fa086d2a9604f03a532df8afdda9";
    hash = "sha256-haFXrByBawdBlANKkScLkco+Zr+9t8naW4Tuw7aJHDo=";
  };

  # This lockfile carries 27 git dependencies. fetchCargoVendor resolves them
  # itself; cargoLock.lockFile would have needed 27 hand-maintained
  # outputHashes entries, each free to rot independently.
  cargoHash = "sha256-fSsAPwIYh/jvotAUvemLpiPe2KXtLc2GbN1uHzbMb/4=";

  # The facilitator and its signing counterpart. zpay-demo is a demo.
  cargoBuildFlags = [
    "-p"
    "zpay-runtime"
    "-p"
    "zspend-runtime"
  ];

  # zinder-client, reached as a git dependency, carries
  #   #[doc = include_str!("../../../docs/reference/server-side-wallet-pattern.md")]
  # which escapes its own crate directory. Plain cargo survives it by checking
  # the whole zinder repository out into ~/.cargo/git, so the path resolves;
  # fetchCargoVendor copies each git dependency as a bare crate directory, so
  # it does not, and rustc stops with "couldn't read ... No such file".
  #
  # This cannot be fixed by moving a pin. Upstream zinder has already replaced
  # that line with an in-crate ../README.md, but zpay's lockfile pins the
  # revision that still has it, and the commit pinned above is zpay's newest --
  # there is nothing later to move to.
  #
  # The file is documentation text: nothing compiles against its contents, so a
  # placeholder naming the real document builds correctly without
  # misrepresenting what the crate does. The `[ -e ]` guard is the point -- when
  # a pin bump makes this unnecessary, the build fails loudly here instead of
  # silently carrying a workaround nobody re-examines.
  preBuild = ''
    placed=0
    for crateDir in "$NIX_BUILD_TOP"/*-vendor/source-git-*/zinder-client-*; do
      [ -d "$crateDir" ] || continue
      # include_str! resolves from src/, so src/../../../docs lands three levels
      # up: the vendor root, not the crate.
      docDir="$crateDir/../../docs/reference"
      mkdir -p "$docDir"
      printf '%s\n' "See docs/reference/server-side-wallet-pattern.md in the zinder repository." \
        > "$docDir/server-side-wallet-pattern.md"
      placed=$((placed + 1))
    done
    if [ "$placed" -eq 0 ]; then
      echo "zcash.nix: no vendored zinder-client found; this workaround no longer applies and should be deleted" >&2
      exit 1
    fi
    echo "zcash.nix: placed zinder-client doc placeholder ($placed)"
  '';

  doCheck = false;

  nativeBuildInputs = [
    protobuf
    rustPlatform.bindgenHook
  ];

  env.PROTOC = "${protobuf}/bin/protoc";

  passthru.smokeArgs = [ "--version" ];

  meta = {
    description = "Zcash-native payments facilitator speaking x402 and MPP";
    homepage = "https://github.com/gustavovalverde/zpay";
    license = lib.licenses.mit;
    mainProgram = "zpay-runtime";
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

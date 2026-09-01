# lightwalletd — the light-client backend service for Zcash.
#
# WHY THIS EXISTS, given nixpkgs already has one: nixpkgs ships 0.4.19, five
# releases behind upstream's 0.5.4. lightwalletd is the most widely deployed
# service in this ecosystem and the one wallets actually talk to, so running it
# five releases stale is not a small thing. This is the only package here that
# duplicates a nixpkgs attribute, and it does so on currency rather than
# absence -- if nixpkgs catches up, this package should be reconsidered rather
# than kept out of habit.
#
# The only Go package in the repo, so buildGoModule and a vendorHash rather
# than buildRustPackage and a cargoHash. Same discipline: lib.fakeHash, build,
# copy the real one from the error.
#
# Version bumps: `just update lightwalletd`.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "0.5.4";
in
buildGoModule {
  pname = "lightwalletd";
  inherit version;

  src = fetchFromGitHub {
    owner = "zcash";
    repo = "lightwalletd";
    tag = "v${version}";
    hash = "sha256-vlfC/2yuHx9wiOczyUfBmuI5KdLyonACVlwtUowSuDA=";
  };

  vendorHash = "sha256-DT1R6C6AoXR0FpyVTzw9VcF0DaPbvqvkrVsYg+6bP2g=";

  # Upstream's Makefile fills these from `git describe --tags` and friends. A
  # derivation has no git and no .git -- the source is a tarball -- so without
  # this the binary reports an empty version and `lightwalletd version` prints
  # nothing useful, which is exactly what the smoke check reads. The value
  # comes from `version` above, so there is no second copy to drift.
  #
  # GitCommit, Branch, BuildDate and BuildUser are deliberately left at their
  # defaults: they exist to describe a developer's working tree, and inventing
  # values for them here would be stating things that are not true of this
  # build.
  ldflags = [
    "-s"
    "-w"
    "-X github.com/zcash/lightwalletd/common.Version=v${version}"
  ];

  # The suite wants a live zcashd/zebrad to talk to.
  doCheck = false;

  # `version` is a subcommand here, not a flag -- lightwalletd is a cobra app.
  passthru.smokeArgs = [ "version" ];

  meta = {
    description = "Light-client backend service for Zcash wallets";
    homepage = "https://github.com/zcash/lightwalletd";
    license = lib.licenses.mit;
    mainProgram = "lightwalletd";
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

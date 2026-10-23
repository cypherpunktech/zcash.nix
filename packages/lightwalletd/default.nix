# lightwalletd — the light-client backend service for Zcash.
#
# WHY THIS EXISTS, given nixpkgs already has one: nixpkgs ships 0.4.19, several
# releases behind upstream's 0.6.0. lightwalletd is the most widely deployed
# service in this ecosystem and the one wallets actually talk to, so running it
# several releases stale is not a small thing. This is the only package here that
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
  fetchurl,
  go,
}:
let
  version = "0.6.0";

  # 0.6.0's go.mod requires go >= 1.26.10; nixpkgs-unstable has at most 1.26.9 while
  # 1.26.10 sits in master (NixOS/nixpkgs#576200) behind a world rebuild. The
  # throw turns this into an eval error the day the pin catches up, so the
  # override is deleted rather than kept as an unexamined second Go.
  go' =
    if lib.versionAtLeast go.version "1.26.10" then
      throw "lightwalletd: nixpkgs now has go ${go.version}; delete the go override"
    else
      go.overrideAttrs rec {
        version = "1.26.10";
        src = fetchurl {
          url = "https://go.dev/dl/go${version}.src.tar.gz";
          hash = "sha256-/WPog7ovK/ypPBZGsx6+9j4rHk0rMXyXidl2po2B828=";
        };
      };
in
(buildGoModule.override { go = go'; }) {
  pname = "lightwalletd";
  inherit version;

  src = fetchFromGitHub {
    owner = "zcash";
    repo = "lightwalletd";
    tag = "v${version}";
    hash = "sha256-Qi5tjG2aw5NBBFKav5SY3Opj0XBEbPmzy6vmKke81jE=";
  };

  vendorHash = "sha256-LyWbitsjw6YXxGnxd53SCkD6AL5p8YY6hLQJxgVIIRw=";

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
    # Every platform here has been built AND had its binary run, by CI on all
    # three (.github/workflows/discover.yml decides the runners).
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

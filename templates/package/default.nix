# <name> — one line on what it is and who makes it.
#
# Why it is packaged the way it is: anything a reader would otherwise have to
# rediscover -- an MSRV, a build script that shells out, a feature upstream
# leaves off, a platform that does not build and why.
#
# Version bumps: `just update <name>`.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  # Add what the build needs, e.g. protobuf, and nothing it does not.
}:
let
  version = "0.0.0";
in
rustPlatform.buildRustPackage {
  pname = "<name>";
  inherit version;

  src = fetchFromGitHub {
    owner = "<owner>";
    repo = "<repo>";
    tag = "v${version}";
    # Build once with the fake hash and copy the real one out of the error.
    # Whole, never truncated, never guessed.
    hash = lib.fakeHash;
  };

  cargoHash = lib.fakeHash;

  # Upstream tests want live peers and chain state; say so if you turn them
  # off, and say what the smoke check covers instead.
  doCheck = false;

  # The argv that proves the binary runs. No default on purpose: a package
  # that cannot answer this is not proven.
  passthru.smokeArgs = [ "--version" ];

  # If upstream signs its release tags, pin the key here; see CONTRIBUTING.md.
  # passthru.upstreamSigners = ./allowed_signers;

  meta = {
    description = "";
    homepage = "https://github.com/<owner>/<repo>";
    # What upstream grants -- a repository with no LICENSE is `unfree`.
    license = lib.licenses.mit;
    mainProgram = "<binary>";
    # Only systems where the binary has BEEN RUN. Claim, then let CI prove or
    # remove.
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

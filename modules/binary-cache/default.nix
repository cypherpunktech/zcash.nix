# services.zcash.binaryCache — this repository's binary cache, as a NixOS option.
#
# flake.nix advertises the cache through nixConfig, which Nix honours only for
# a trusted user; for anyone else `--accept-flake-config` is silently ignored,
# and the first sign is zebra compiling for half an hour. nix.settings is the
# route that always works, and NixOS is where these modules run anyway.
# Opt-in: a module a stranger imports must not add a trust root on its own.
# The URL and key are read from flake.nix's nixConfig, so each exists once.
_self:
{ config, lib, ... }:
let
  inherit (import ../../flake.nix) nixConfig;
in
{
  options.services.zcash.binaryCache.enable = lib.mkEnableOption ''
    cypherpunktech.cachix.org as a substituter. Using it means trusting the CI
    that pushes to it and the maintainers who hold its token; SECURITY.md says
    what that trust covers
  '';

  config = lib.mkIf config.services.zcash.binaryCache.enable {
    nix.settings = {
      substituters = nixConfig.extra-substituters;
      trusted-public-keys = nixConfig.extra-trusted-public-keys;
    };
  };
}

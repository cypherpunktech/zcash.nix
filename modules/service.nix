# What every service here shares, whatever its shape.
#
# Two shapes exist. Nodes and indexers are MULTI-INSTANCE: `services.zcash.
# zebra.<instance>`, one unit `zebra-<instance>` and one state directory
# `/var/lib/zebra-<instance>` per entry, because a mainnet and a testnet node
# on one host is the ordinary setup for anyone developing against them (the
# same shape as nixpkgs' services.bitcoind.<name>). Wallets are single: one
# wallet per machine is the sane default, and their state is a wallet file,
# not a chain. Both shapes take the options below and resolve identity the
# same way, so the difference between them is the attrsOf and nothing else.
#
# Identity: `user = null` means DynamicUser -- an allocated uid that owns the
# state directory and nothing else. A name means a static system user, which
# is the ONLY way two services can share a directory: zallet reads a node's
# state database, zinder's four runtimes share one storage tree. That is a
# real reduction in isolation, so it is an explicit option with a default of
# none, never something a module does silently.
{
  lib,
  self,
  pkgs,
  name,
  description,
}:
rec {
  options = {
    enable = lib.mkEnableOption description;

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.${name};
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.${name}";
      description = "The ${name} package to run.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Further command-line arguments, appended verbatim.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Run as this static system user (created if needed) instead of an
        allocated `DynamicUser`. Set it when another service must read this
        one's state directory, and give both the same user; otherwise leave
        it, an allocated identity is strictly more isolated.
      '';
    };
  };

  # serviceConfig for the identity an instance chose, plus its state directory.
  identity =
    cfg: stateDirectory:
    (import ./hardening.nix)
    // {
      StateDirectory = stateDirectory;
      StateDirectoryMode = "0700";
    }
    // (
      if cfg.user == null then
        { DynamicUser = true; }
      else
        {
          DynamicUser = false;
          User = cfg.user;
          Group = cfg.user;
        }
    );

  # The users a set of instances asks for, as a users.users / users.groups
  # pair. Two instances naming the same user merge into one definition.
  users =
    instances:
    let
      static = lib.unique (lib.filter (u: u != null) (map (cfg: cfg.user) (lib.attrValues instances)));
    in
    {
      users = lib.genAttrs static (u: {
        isSystemUser = true;
        group = u;
      });
      groups = lib.genAttrs static (_: { });
    };

  # The enabled instances of a multi-instance service.
  enabled = instances: lib.filterAttrs (_: cfg: cfg.enable) instances;

  portOf = addr: lib.toInt (lib.last (lib.splitString ":" addr));
}

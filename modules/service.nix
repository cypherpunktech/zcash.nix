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

    package = lib.mkPackageOption self.packages.${pkgs.stdenv.hostPlatform.system} name {
      pkgsText = "zcash-nix.packages.\${system}";
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

  # A secret the unit needs -- a TLS key, an RPC credential file. Three rules
  # follow from what a secret is, and each helper below is one of them.
  #
  # Its option is a STRING, never `types.path`: a path literal (`./tls.key`)
  # type-checks as a path and is copied into /nix/store, world-readable,
  # forever. As a string it is a type error. `notInStore` closes the two ways
  # around that, `"${./tls.key}"` and pkgs.writeText.
  #
  # It reaches the unit through LoadCredential=, never on argv or in the
  # store: pid 1 reads the operator's file as root and places a copy under
  # /run/credentials/<unit>.service/ that only the service's group can read
  # (root:<group>, 0440, in a directory nobody else may enter). That is also
  # the only way a DynamicUser can read a file at all -- its uid does not
  # exist until the unit starts, so nothing can be chowned to it in advance
  # -- which is why every other secret-delivery path here failed on first
  # read with EACCES. Inside ExecStart the directory is `%d` or
  # `$CREDENTIALS_DIRECTORY`; a config file that needs the literal path
  # takes it from `credentialPath`.
  secretFile =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/lightwalletd-tls.key";
      description = ''
        ${description}

        A path outside the Nix store, readable by root: systemd hands the
        service its own private copy, so the file's owner and mode do not
        matter and it never touches the store or the unit file.
      '';
    };

  credentials = files: {
    LoadCredential = lib.mapAttrsToList (id: file: "${id}:${file}") (
      lib.filterAttrs (_: file: file != null) files
    );
  };

  credentialPath = unit: id: "/run/credentials/${unit}.service/${id}";

  notInStore = what: file: {
    assertion = file == null || !lib.hasPrefix builtins.storeDir file;
    message = ''
      ${what} points into the Nix store, which is world-readable. Point it
      at a file outside the store, e.g. config.sops.secrets.<name>.path or
      config.age.secrets.<name>.path; root readability is all it needs.
    '';
  };

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

  # The one capability a listener can need: binding below 1024. hardening.nix
  # empties the bounding set, so a public lightwalletd on :443 -- what
  # wallets expect -- would fail with EACCES and nothing would say why.
  # Derived from the address the operator set, so the grant exists exactly
  # where the port demands it and nowhere else.
  bindCaps =
    addr:
    lib.optionalAttrs (portOf addr < 1024) {
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    };

  portOf = addr: lib.toInt (lib.last (lib.splitString ":" addr));
  # "127.0.0.1:8232" -> "127.0.0.1"; "[::1]:8232" -> "::1".
  hostOf =
    addr:
    lib.removePrefix "[" (
      lib.removeSuffix "]" (lib.concatStringsSep ":" (lib.init (lib.splitString ":" addr)))
    );
  loopback =
    addr:
    lib.any (p: lib.hasPrefix p (hostOf addr)) [
      "127."
      "::1"
      "localhost"
    ];
}

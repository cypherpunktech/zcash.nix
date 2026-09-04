# services.zcash.zaino.<instance> — Zingo Labs' Zcash indexer, as a systemd service.
#
# Not built on ../node.nix: zaino is not a node. It is an indexer that talks to
# one, its config sections are entirely different, and it takes `-c` on a
# `start` subcommand with its own schema. Forcing it through the node factory
# would mean adding options there that only one caller uses -- an abstraction
# serving two masters.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "zaino";
  service = import ../service.nix {
    inherit
      lib
      self
      pkgs
      name
      ;
    description = "Zaino, an indexer for the Zcash blockchain";
  };
  instances = service.enabled config.services.zcash.zaino;
  toml = pkgs.formats.toml { };

  instance =
    { name, config, ... }:
    let
      stateDir = "/var/lib/zaino-${name}";
      unit = "zaino-${name}";
    in
    {
      options = service.options // {
        node = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "zebra-mainnet";
          description = ''
            Unit name of the zebra or zakura instance on this host that this
            indexer follows, `<node>-<instance>`. This unit then starts after
            the node's RPC answers, restarts when the node does, and
            authenticates to its RPC with the node's cookie, which systemd
            hands over as a credential so the two keep separate users. The
            node's addresses still come from `settings.validator_settings`.
          '';
        };

        settings = lib.mkOption {
          inherit (toml) type;
          default = { };
          example = lib.literalExpression ''
            {
              grpc_settings.listen_address = "127.0.0.1:8137";
              validator_settings.validator_jsonrpc_listen_address = "127.0.0.1:8232";
            }
          '';
          description = ''
            Contents of `zainod.toml`, as a Nix attribute set. Generate a
            reference with `zainod generate-config -o -`.

            `storage.database.path` defaults to the instance's state directory.
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open the gRPC port in the firewall.

            Off by default. An indexer answers questions about which
            transactions concern which viewing keys; who can ask it is a
            privacy decision, not a convenience one.
          '';
        };
      };

      config.settings = {
        # Its own default is a home-directory cache, which ProtectHome hides.
        storage.database.path = lib.mkDefault stateDir;
        # The node rewrites its cookie on every start; the credential is a
        # copy taken at this unit's start, and partOf below keeps the two in
        # step.
        validator_settings.validator_cookie_path = lib.mkIf (config.node != null) (
          service.credentialPath unit "validator-cookie"
        );
      };
    };
in
{
  options.services.zcash.zaino = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instance);
    default = { };
    description = "Zaino indexer instances, each its own unit and state directory.";
  };

  config = lib.mkIf (instances != { }) {
    systemd.services = lib.mapAttrs' (
      instanceName: cfg:
      lib.nameValuePair "zaino-${instanceName}" {
        description = "Zaino Zcash indexer (${instanceName})";
        documentation = [ "https://github.com/zingolabs/zaino" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ] ++ lib.optional (cfg.node != null) "${cfg.node}.service";
        wants = [ "network-online.target" ] ++ lib.optional (cfg.node != null) "${cfg.node}.service";
        partOf = lib.optional (cfg.node != null) "${cfg.node}.service";
        serviceConfig =
          service.identity cfg "zaino-${instanceName}"
          // service.credentials {
            validator-cookie = lib.mapNullable (node: "/var/lib/${node}/.cookie") cfg.node;
          }
          // {
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe cfg.package)
                "start"
                "--config"
                (toml.generate "zainod-${instanceName}.toml" cfg.settings)
              ]
              ++ cfg.extraArgs
            );
          };
      }
    ) instances;

    users = service.users instances;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      cfg:
      lib.optional cfg.openFirewall (
        service.portOf (cfg.settings.grpc_settings.listen_address or "127.0.0.1:8137")
      )
    ) (lib.attrValues instances);
  };
}

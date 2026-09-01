# services.zcash.zaino — Zingo Labs' Zcash indexer, as a systemd service.
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
  cfg = config.services.zcash.zaino;
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/zaino";
  configFile = toml.generate "zainod.toml" cfg.settings;
in
{
  options.services.zcash.zaino = {
    enable = lib.mkEnableOption "Zaino, an indexer for the Zcash blockchain";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.zaino;
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.zaino";
      description = "The zaino package to run.";
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
        Contents of `zainod.toml`, as a Nix attribute set. Generate a reference
        with `zainod generate-config -o -`.

        `storage.database.path` defaults to the service's StateDirectory.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the gRPC port in the firewall.

        Off by default. An indexer answers questions about which transactions
        concern which viewing keys; who can ask it is a privacy decision, not a
        convenience one.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Its own default is a home-directory cache, which ProtectHome hides.
    services.zcash.zaino.settings.storage.database.path = lib.mkDefault stateDir;

    systemd.services.zaino = {
      description = "Zaino Zcash indexer";
      documentation = [ "https://github.com/zingolabs/zaino" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = (import ../hardening.nix) // {
        ExecStart = "${lib.getExe cfg.package} start --config ${configFile}";
        DynamicUser = true;
        StateDirectory = "zaino";
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (
        let
          addr = cfg.settings.grpc_settings.listen_address or "127.0.0.1:8137";
        in
        lib.toInt (lib.last (lib.splitString ":" addr))
      )
    ];
  };
}

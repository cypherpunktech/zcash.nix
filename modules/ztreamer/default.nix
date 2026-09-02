# services.zcash.ztreamer — a light-wallet server with its own node inside.
#
# Not built on ../node.nix, although the node is in there: ztreamerd takes
# the zakura TOML as `--zakura-config` and everything else as flags, with no
# `start` subcommand. What the node factory knows about (the [state] and [rpc]
# defaults that ProtectHome would otherwise break) is restated here for the
# embedded node, because the embedded node has exactly the same problem.
#
# Two things listen on behalf of two different publics: the embedded node's
# peer port, for the Zcash network, and the CompactTxStreamer gRPC port, for
# wallets. They get separate firewall options rather than one `openFirewall`
# that would have to mean both.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.ztreamer;
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/ztreamer";
  configFile = toml.generate "zakura.toml" cfg.settings;

  portOf = addr: lib.toInt (lib.last (lib.splitString ":" addr));
in
{
  options.services.zcash.ztreamer = {
    enable = lib.mkEnableOption "ztreamer, a CompactTxStreamer server with an embedded zakura node";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.ztreamer;
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.ztreamer";
      description = "The ztreamer package to run.";
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      example = lib.literalExpression ''
        {
          network.network = "Testnet";
          rpc.listen_addr = "127.0.0.1:18232";
        }
      '';
      description = ''
        Configuration of the embedded zakura node, as `zakura.toml` in Nix
        form. `state.cache_dir` defaults to the service's StateDirectory and
        should normally be left alone.
      '';
    };

    grpcListen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9067";
      description = "Address the CompactTxStreamer gRPC server listens on.";
    };

    metricsListen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9999";
      description = "Address the Prometheus metrics endpoint listens on.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--fetch-workers"
        "8"
      ];
      description = ''
        Further `ztreamerd` flags, chiefly the indexing tuning knobs
        (`--fetch-workers`, `--max-pending-bytes`, ...). See `ztreamerd --help`.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the gRPC port in the firewall: this is the port wallets connect
        to, and the one a public light-wallet server exposes. Off by default,
        as for every indexer here -- who may ask which transactions concern
        which keys is a privacy decision.
      '';
    };

    openPeerPort = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the embedded node's peer-to-peer port so other Zcash nodes can
        connect inbound. Never the RPC port, and never the metrics port.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.zcash.ztreamer.settings = {
      state.cache_dir = lib.mkDefault stateDir;
      rpc.cookie_dir = lib.mkDefault stateDir;
    };

    systemd.services.ztreamer = {
      description = "ztreamer CompactTxStreamer server with embedded zakura node";
      documentation = [ "https://github.com/distractedm1nd/ztreamer" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = (import ../hardening.nix) // {
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "--zakura-config"
            configFile
            "--index-dir"
            "${stateDir}/index"
            "--grpc-listen"
            cfg.grpcListen
            "--metrics-listen"
            cfg.metricsListen
          ]
          ++ cfg.extraArgs
        );
        DynamicUser = true;
        StateDirectory = "ztreamer";
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts =
      lib.optional cfg.openFirewall (portOf cfg.grpcListen)
      ++ lib.optional cfg.openPeerPort (portOf (cfg.settings.network.listen_addr or "[::]:8233"));
  };
}

# services.zcash.ztreamer.<instance> — a light-wallet server with its own node inside.
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
  name = "ztreamer";
  service = import ../service.nix {
    inherit
      lib
      self
      pkgs
      name
      ;
    description = "ztreamer, a CompactTxStreamer server with an embedded zakura node";
  };
  instances = service.enabled config.services.zcash.ztreamer;
  toml = pkgs.formats.toml { };

  instance =
    { name, ... }:
    let
      stateDir = "/var/lib/ztreamer-${name}";
    in
    {
      options = service.options // {
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
            form. `state.cache_dir` defaults to the instance's state directory
            and should normally be left alone.
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

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open the gRPC port in the firewall: this is the port wallets
            connect to, and the one a public light-wallet server exposes. Off
            by default, as for every indexer here -- who may ask which
            transactions concern which keys is a privacy decision.
          '';
        };

        openPeerPort = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open the embedded node's peer-to-peer port so other Zcash nodes
            can connect inbound. Never the RPC port, and never the metrics
            port.
          '';
        };
      };

      config.settings = {
        state.cache_dir = lib.mkDefault stateDir;
        rpc.cookie_dir = lib.mkDefault stateDir;
      };
    };
in
{
  options.services.zcash.ztreamer = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instance);
    default = { };
    description = "ztreamer instances, each its own unit, embedded node and state directory.";
  };

  config = lib.mkIf (instances != { }) {
    systemd.services = lib.mapAttrs' (
      instanceName: cfg:
      lib.nameValuePair "ztreamer-${instanceName}" {
        description = "ztreamer CompactTxStreamer server with embedded zakura node (${instanceName})";
        documentation = [ "https://github.com/distractedm1nd/ztreamer" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = service.identity cfg "ztreamer-${instanceName}" // {
          ExecStart = lib.escapeShellArgs (
            [
              (lib.getExe cfg.package)
              "--zakura-config"
              (toml.generate "zakura-${instanceName}.toml" cfg.settings)
              "--index-dir"
              "/var/lib/ztreamer-${instanceName}/index"
              "--grpc-listen"
              cfg.grpcListen
              "--metrics-listen"
              cfg.metricsListen
            ]
            ++ cfg.extraArgs
          );
        };
      }
    ) instances;

    users = service.users instances;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      cfg:
      lib.optional cfg.openFirewall (service.portOf cfg.grpcListen)
      ++ lib.optional cfg.openPeerPort (service.portOf (cfg.settings.network.listen_addr or "[::]:8233"))
    ) (lib.attrValues instances);
  };
}

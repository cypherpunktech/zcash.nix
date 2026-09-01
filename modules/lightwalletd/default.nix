# services.zcash.lightwalletd — the light-client backend, as a systemd service.
#
# lightwalletd is configured by flags rather than a config file, so this module
# maps options to flags instead of generating TOML. The awkward part it has to
# handle honestly is TLS: lightwalletd REQUIRES either a certificate or an
# explicit --no-tls-very-insecure, and the flag is named that way on purpose.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.lightwalletd;
in
{
  options.services.zcash.lightwalletd = {
    enable = lib.mkEnableOption "lightwalletd, the Zcash light-client backend";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.lightwalletd;
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.lightwalletd";
      description = "The lightwalletd package to run.";
    };

    grpcBindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9067";
      description = "Address to serve gRPC on. Loopback by default: exposing this is a deliberate act.";
    };

    httpBindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:9068";
      description = "Address to serve HTTP on.";
    };

    rpcHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host of the backing zebrad/zakura node's RPC.";
    };

    rpcPort = lib.mkOption {
      type = lib.types.port;
      default = 8232;
      description = "Port of the backing node's RPC.";
    };

    zcashConfPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a `zcash.conf` to read RPC credentials from.

        Prefer this over passing credentials as flags: everything in a unit's
        ExecStart is world-readable through `systemctl cat` and `/proc`.
      '';
    };

    tls = {
      certFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "TLS certificate. Required unless `insecureNoTLS` is set.";
      };
      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "TLS key. Required unless `insecureNoTLS` is set.";
      };
    };

    insecureNoTLS = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run without TLS, passing `--no-tls-very-insecure`.

        Wallets connecting to this server send their viewing keys' query
        patterns over the wire. Without TLS those are readable by anything on
        the path, which for a privacy coin defeats a large part of the point.
        Only reasonable behind a terminating reverse proxy on the same host, or
        in a test.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line arguments.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the gRPC port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.insecureNoTLS || (cfg.tls.certFile != null && cfg.tls.keyFile != null);
        message = ''
          services.zcash.lightwalletd needs either tls.certFile and tls.keyFile,
          or insecureNoTLS = true set deliberately. lightwalletd will not start
          without one of them, and silently defaulting to no TLS would hide a
          decision that belongs to you.
        '';
      }
    ];

    systemd.services.lightwalletd = {
      description = "Zcash lightwalletd light-client backend";
      documentation = [ "https://github.com/zcash/lightwalletd" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = (import ../hardening.nix) // {
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "--grpc-bind-addr"
            cfg.grpcBindAddr
            "--http-bind-addr"
            cfg.httpBindAddr
            "--rpchost"
            cfg.rpcHost
            "--rpcport"
            (toString cfg.rpcPort)
            "--data-dir"
            "/var/lib/lightwalletd"
            # Default is ./server.log, which ProtectSystem=strict makes
            # unwritable. Journald is where a systemd service's logs belong.
            "--log-file"
            "/dev/stdout"
          ]
          ++ lib.optionals (cfg.zcashConfPath != null) [
            "--zcash-conf-path"
            cfg.zcashConfPath
          ]
          ++ lib.optionals cfg.insecureNoTLS [ "--no-tls-very-insecure" ]
          ++ lib.optionals (!cfg.insecureNoTLS) [
            "--tls-cert"
            (toString cfg.tls.certFile)
            "--tls-key"
            (toString cfg.tls.keyFile)
          ]
          ++ cfg.extraArgs
        );
        DynamicUser = true;
        StateDirectory = "lightwalletd";
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (lib.toInt (lib.last (lib.splitString ":" cfg.grpcBindAddr)))
    ];
  };
}

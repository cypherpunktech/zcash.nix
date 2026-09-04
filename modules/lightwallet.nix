# The shared shape of a lightwalletd-style service.
#
# Two implementations of the CompactTxStreamer proxy live here, the Go
# original and lightwalletd-rs, and to a systemd unit they are one program:
# flags rather than a config file, a gRPC listener that must stay on loopback
# unless someone decides otherwise, an HTTP (metrics) listener, a backing
# node's JSON-RPC reached by host/port with credentials from a zcash.conf, an
# on-disk block cache, and TLS that must be either configured or refused in so
# many words. The options are therefore defined once. What differs is
# spelling -- each implementation names the same flag differently -- and one
# behaviour: the Go one exits at startup without credentials, the Rust one
# does not. Both are parameters, so a difference in the FORCES shows up here
# as data rather than as a second module drifting from the first.
#
# Multi-instance: `services.zcash.lightwalletd.<instance>`, see ./service.nix.
{
  self,
  name,
  description,
  documentation,
  # The implementation's spelling of each flag this module sets.
  flags,
  # The daemon logs only to a file named by this flag (null: it logs to
  # stderr like a daemon should). Under systemd stdout is journald's stream
  # SOCKET, and open(2) on a socket is ENXIO, so `--log-file /dev/stdout`
  # dies at every start -- and looks "active" for the second before it does.
  # A pipe reopens fine: the daemon's stdout becomes one, cat forwards it to
  # the journal, and pipefail keeps the daemon's exit status for Restart=.
  logFileFlag ? null,
  # Whether the daemon refuses to start with no credential source at all.
  requiresCredentials,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  service = import ./service.nix {
    inherit
      lib
      self
      pkgs
      name
      description
      ;
  };
  instances = service.enabled config.services.zcash.${name};

  instance = {
    options = service.options // {
      grpcBindAddr = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:9067";
        description = "Address to serve gRPC on. Loopback by default: exposing this is a deliberate act.";
      };

      httpBindAddr = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1:9068";
        description = "Address to serve HTTP (metrics) on.";
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

      # The only credential source. Both daemons also take the password as a
      # flag; that option does not exist here because a flag lands in the
      # unit file, which is in the world-readable store. A file handed over
      # as a credential is the password-from-file flag both were missing.
      zcashConfPath = service.secretFile ''
        A `zcash.conf` with `rpcuser=` and `rpcpassword=` lines for the
        backing node's RPC.
      '';

      tls = {
        certFile = service.secretFile "TLS certificate. Required unless `insecureNoTLS` is set.";
        keyFile = service.secretFile "TLS key. Required unless `insecureNoTLS` is set.";
      };

      insecureNoTLS = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run without TLS, passing `--no-tls-very-insecure`.

          Wallets connecting to this server send their viewing keys' query
          patterns over the wire. Without TLS those are readable by anything
          on the path, which for a privacy coin defeats a large part of the
          point. Only reasonable behind a terminating reverse proxy on the
          same host, or in a test.
        '';
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the gRPC port in the firewall.";
      };
    };
  };
in
{
  options.services.zcash.${name} = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instance);
    default = { };
    description = "${description}: one entry per instance, each its own unit and block cache.";
  };

  config = lib.mkIf (instances != { }) {
    assertions = lib.concatMap (
      instanceName:
      let
        cfg = instances.${instanceName};
        opt = "services.zcash.${name}.${instanceName}";
      in
      [
        {
          # Found by running the Go one: without a credential source it exits
          # at once with "required file ./zcash.conf does not exist", which
          # under systemd is a restart loop and a unit that looks configured.
          assertion = !requiresCredentials || cfg.zcashConfPath != null;
          message = ''
            ${opt} needs zcashConfPath: ${name} exits at startup without RPC
            credentials, looking for ./zcash.conf in a working directory it
            cannot write to.
          '';
        }
        {
          assertion = cfg.insecureNoTLS || (cfg.tls.certFile != null && cfg.tls.keyFile != null);
          message = ''
            ${opt} needs either tls.certFile and tls.keyFile, or insecureNoTLS
            = true set deliberately. ${name} will not start without one of
            them, and silently defaulting to no TLS would hide a decision that
            belongs to you.
          '';
        }
        (service.notInStore "${opt}.zcashConfPath" cfg.zcashConfPath)
        (service.notInStore "${opt}.tls.certFile" cfg.tls.certFile)
        (service.notInStore "${opt}.tls.keyFile" cfg.tls.keyFile)
      ]
    ) (lib.attrNames instances);

    systemd.services = lib.mapAttrs' (
      instanceName: cfg:
      lib.nameValuePair "${name}-${instanceName}" {
        description = "${description} (${instanceName})";
        inherit documentation;
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig.RequiresMountsFor = [ "/var/lib/${name}-${instanceName}" ];
        serviceConfig =
          service.identity cfg "${name}-${instanceName}"
          // service.bindCaps cfg.grpcBindAddr
          // service.credentials {
            zcash-conf = cfg.zcashConfPath;
            tls-cert = cfg.tls.certFile;
            tls-key = cfg.tls.keyFile;
          }
          // {
            ExecStart =
              let
                # %d: the unit's credentials directory, expanded by systemd.
                argv = lib.escapeShellArgs (
                  [
                    (lib.getExe cfg.package)
                    flags.grpcBind
                    cfg.grpcBindAddr
                    flags.httpBind
                    cfg.httpBindAddr
                    flags.rpcHost
                    cfg.rpcHost
                    flags.rpcPort
                    (toString cfg.rpcPort)
                    "--data-dir"
                    "/var/lib/${name}-${instanceName}"
                  ]
                  ++ lib.optionals (logFileFlag != null) [
                    logFileFlag
                    "/dev/stdout"
                  ]
                  ++ lib.optionals (cfg.zcashConfPath != null) [
                    flags.zcashConf
                    "%d/zcash-conf"
                  ]
                  ++ lib.optionals cfg.insecureNoTLS [ "--no-tls-very-insecure" ]
                  ++ lib.optionals (!cfg.insecureNoTLS) [
                    "--tls-cert"
                    "%d/tls-cert"
                    "--tls-key"
                    "%d/tls-key"
                  ]
                  ++ cfg.extraArgs
                );
              in
              if logFileFlag == null then
                argv
              else
                lib.escapeShellArgs [
                  pkgs.runtimeShell
                  "-c"
                  "set -o pipefail; ${argv} | cat"
                ];
          };
      }
    ) instances;

    users = service.users instances;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      cfg: lib.optional cfg.openFirewall (service.portOf cfg.grpcBindAddr)
    ) (lib.attrValues instances);
  };
}

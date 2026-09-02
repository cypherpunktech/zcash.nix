# The shared shape of a lightwalletd-style service.
#
# Two implementations of the CompactTxStreamer proxy live here, the Go
# original and lightwalletd-rs, and to a systemd unit they are one program:
# flags rather than a config file, a gRPC listener that must stay on loopback
# unless someone decides otherwise, an HTTP (metrics) listener, a backing
# node's JSON-RPC reached by host/port or a zcash.conf, an on-disk block cache,
# and TLS that must be either configured or refused in so many words. The
# options are therefore defined once. What differs is spelling -- each
# implementation names the same flag differently -- and one behaviour: the Go
# one exits at startup without credentials, the Rust one does not. Both are
# parameters, so a difference in the FORCES shows up here as data rather than
# as a second module drifting from the first.
#
# Multi-instance: `services.zcash.lightwalletd.<instance>`, see ./service.nix.
{
  self,
  name,
  description,
  documentation,
  # The implementation's spelling of each flag this module sets.
  flags,
  # Flags always passed, e.g. to redirect a log file into journald.
  extraFlags ? [ ],
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

      zcashConfPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a `zcash.conf` to read RPC credentials from. **Preferred**
          over the flags below, because everything in a unit's ExecStart is
          readable by any local user through `systemctl cat` and `/proc`.
        '';
      };

      rpcUser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "RPC username. Requires `rpcPassword`. Prefer `zcashConfPath`.";
      };

      rpcPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          RPC password, passed as a command-line flag.

          This lands in the unit file and in the process's argv, both readable
          by any local user. It exists because neither implementation offers a
          password-from-file flag, and it is documented rather than hidden.
          Use `zcashConfPath` unless you have a reason not to.
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
    assertions = lib.concatMap (instanceName: [
      {
        # Found by running the Go one: without a credential source it exits at
        # once with "required file ./zcash.conf does not exist", which under
        # systemd is a restart loop and a unit that looks configured.
        assertion =
          let
            cfg = instances.${instanceName};
          in
          !requiresCredentials
          || cfg.zcashConfPath != null
          || (cfg.rpcUser != null && cfg.rpcPassword != null);
        message = ''
          services.zcash.${name}.${instanceName} needs RPC credentials: set
          zcashConfPath (preferred), or both rpcUser and rpcPassword. ${name}
          exits at startup without them, looking for ./zcash.conf in a working
          directory it cannot write to.
        '';
      }
      {
        assertion =
          let
            cfg = instances.${instanceName};
          in
          cfg.insecureNoTLS || (cfg.tls.certFile != null && cfg.tls.keyFile != null);
        message = ''
          services.zcash.${name}.${instanceName} needs either tls.certFile and
          tls.keyFile, or insecureNoTLS = true set deliberately. ${name} will
          not start without one of them, and silently defaulting to no TLS
          would hide a decision that belongs to you.
        '';
      }
    ]) (lib.attrNames instances);

    systemd.services = lib.mapAttrs' (
      instanceName: cfg:
      lib.nameValuePair "${name}-${instanceName}" {
        description = "${description} (${instanceName})";
        inherit documentation;
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = service.identity cfg "${name}-${instanceName}" // {
          ExecStart = lib.escapeShellArgs (
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
            ++ extraFlags
            ++ lib.optionals (cfg.zcashConfPath != null) [
              flags.zcashConf
              (toString cfg.zcashConfPath)
            ]
            ++ lib.optionals (cfg.rpcUser != null) [
              flags.rpcUser
              cfg.rpcUser
            ]
            ++ lib.optionals (cfg.rpcPassword != null) [
              flags.rpcPassword
              cfg.rpcPassword
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
        };
      }
    ) instances;

    users = service.users instances;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      cfg: lib.optional cfg.openFirewall (service.portOf cfg.grpcBindAddr)
    ) (lib.attrValues instances);
  };
}

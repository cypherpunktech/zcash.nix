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
  cfg = config.services.zcash.${name};
  stateDir = "/var/lib/${name}";
in
{
  options.services.zcash.${name} = {
    enable = lib.mkEnableOption description;

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.${name};
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.${name}";
      description = "The ${name} package to run.";
    };

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
        Path to a `zcash.conf` to read RPC credentials from. **Preferred** over
        the flags below, because everything in a unit's ExecStart is readable
        by any local user through `systemctl cat` and `/proc`.
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

        This lands in the unit file and in the process's argv, both readable by
        any local user. It exists because neither implementation offers a
        password-from-file flag, and it is documented rather than hidden. Use
        `zcashConfPath` unless you have a reason not to.
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
        # Found by running the Go one: without a credential source it exits at
        # once with "required file ./zcash.conf does not exist", which under
        # systemd is a restart loop and a unit that looks configured.
        assertion =
          !requiresCredentials
          || cfg.zcashConfPath != null
          || (cfg.rpcUser != null && cfg.rpcPassword != null);
        message = ''
          services.zcash.${name} needs RPC credentials: set zcashConfPath
          (preferred), or both rpcUser and rpcPassword. ${name} exits at
          startup without them, looking for ./zcash.conf in a working directory
          it cannot write to.
        '';
      }
      {
        assertion = cfg.insecureNoTLS || (cfg.tls.certFile != null && cfg.tls.keyFile != null);
        message = ''
          services.zcash.${name} needs either tls.certFile and tls.keyFile,
          or insecureNoTLS = true set deliberately. ${name} will not start
          without one of them, and silently defaulting to no TLS would hide a
          decision that belongs to you.
        '';
      }
    ];

    systemd.services.${name} = {
      inherit description documentation;
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = (import ./hardening.nix) // {
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
            stateDir
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
        DynamicUser = true;
        StateDirectory = name;
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (lib.toInt (lib.last (lib.splitString ":" cfg.grpcBindAddr)))
    ];
  };
}

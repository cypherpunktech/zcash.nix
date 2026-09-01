# services.zcash.zpay — the payments facilitator, as a systemd service.
#
# zpay is configured entirely by ZPAY_* environment variables rather than a
# config file, so this module is a freeform environment map plus the shared
# hardening. `environment` is not typed per variable for the same reason
# zebra's `settings` is not typed per key: upstream adds variables and a
# mirrored list here would rot.
#
# WHAT THIS DELIBERATELY DOES NOT START: zspend-runtime, the other binary in
# the package. It signs transactions under a bounded payment_authorization
# grant -- it holds spend authority. Starting a signer because someone enabled
# a payments frontend would be a surprising thing for a module to do, so
# running it is left as an explicit act, the same way zallet's beta gate is.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.zpay;
in
{
  options.services.zcash.zpay = {
    enable = lib.mkEnableOption "zpay, a Zcash-native payments facilitator";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.zpay;
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.zpay";
      description = "The zpay package to run.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        ZPAY_NETWORK = "main";
        ZPAY_SERVER__BIND_ADDR = "127.0.0.1:8080";
      };
      description = ''
        `ZPAY_*` variables passed to the runtime. Run
        `zpay-runtime --print-config` to see what it resolved.

        These land in the unit file, readable by any local user. Anything
        secret belongs in `environmentFile`, not here.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file of `KEY=value` lines, read by systemd at start.

        This is where credentials go. The file is read by systemd as root
        before the service drops to its own user, so it can live outside the
        service's own state directory and be readable only by root.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the HTTP listener port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.zpay = {
      description = "zpay Zcash payments facilitator";
      documentation = [ "https://github.com/gustavovalverde/zpay" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      inherit (cfg) environment;

      serviceConfig = (import ../hardening.nix) // {
        ExecStart = "${cfg.package}/bin/zpay-runtime";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        DynamicUser = true;
        StateDirectory = "zpay";
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (
        let
          addr = cfg.environment.ZPAY_SERVER__BIND_ADDR or "127.0.0.1:8080";
        in
        lib.toInt (lib.last (lib.splitString ":" addr))
      )
    ];
  };
}

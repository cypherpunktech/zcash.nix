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
  service = import ../service.nix {
    inherit lib self pkgs;
    name = "zpay";
    description = "zpay, a Zcash-native payments facilitator";
  };
  bindAddr = cfg.environment.ZPAY_SERVER__BIND_ADDR or "127.0.0.1:8080";
in
{
  # Single-instance: a payments facilitator is one per machine.
  options.services.zcash.zpay = service.options // {

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

    # EnvironmentFile= is read by systemd as root, so it is already what
    # service.credentials gives a file-taking daemon; only the type and the
    # store check are shared.
    environmentFile = service.secretFile ''
      A file of `KEY=value` lines, read by systemd at start. This is where
      credentials go.
    '';

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the HTTP listener port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [ (service.notInStore "services.zcash.zpay.environmentFile" cfg.environmentFile) ];

    systemd.services.zpay = {
      description = "zpay Zcash payments facilitator";
      documentation = [ "https://github.com/gustavovalverde/zpay" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      inherit (cfg) environment;
      unitConfig.RequiresMountsFor = [ "/var/lib/zpay" ];

      serviceConfig =
        service.identity cfg "zpay"
        // service.bindCaps bindAddr
        // {
          ExecStart = lib.escapeShellArgs ([ "${cfg.package}/bin/zpay-runtime" ] ++ cfg.extraArgs);
          EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ (service.portOf bindAddr) ];

    users = service.users { inherit cfg; };
  };
}

# services.zcash.zebra — run Zebra as a hardened systemd service.
#
# The binary is the easy half. What people get wrong is the unit around it: a
# consensus node holding tens of gigabytes of chain state, reachable from the
# internet, running as root because the example in a blog post did.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.zebra;
  toml = pkgs.formats.toml { };

  # Freeform settings rather than an option per config key: zebrad's schema has
  # dozens of fields across ten sections and gains more each release. Mirroring
  # it here would be a second copy that rots quietly the first time upstream
  # adds a field. `settings` accepts whatever zebrad accepts; the options below
  # exist only where the module has to *do* something with the value.
  configFile = toml.generate "zebrad.toml" cfg.settings;
in
{
  options.services.zcash.zebra = {
    enable = lib.mkEnableOption "Zebra, the Zcash Foundation's Zcash node";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.zebra;
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.zebra";
      description = "The zebra package to run.";
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      example = lib.literalExpression ''
        {
          network.network = "Testnet";
          rpc.listen_addr = "127.0.0.1:8232";
        }
      '';
      description = ''
        Contents of `zebrad.toml`, as a Nix attribute set.

        See <https://docs.rs/zebrad/latest/zebrad/config/struct.ZebradConfig.html>.
        `state.cache_dir` defaults to the service's StateDirectory and should
        normally be left alone.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the peer-to-peer port in the firewall.

        Off by default, and deliberately covers only the P2P listener. The RPC
        port is never opened: it is an administrative interface, and a node
        that exposes it to the internet is a node someone else is driving.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # StateDirectory gives /var/lib/zebra; the node must be told to put its
    # database there rather than in a home directory that ProtectHome hides.
    services.zcash.zebra.settings = {
      state.cache_dir = lib.mkDefault "/var/lib/zebra";
      rpc.cookie_dir = lib.mkDefault "/var/lib/zebra";
    };

    systemd.services.zebra = {
      description = "Zebra Zcash node";
      documentation = [ "https://zebra.zfnd.org/" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = (import ../hardening.nix) // {
        ExecStart = "${lib.getExe cfg.package} --config ${configFile} start";
        # DynamicUser: the node needs an identity to own its state and nothing
        # more. An allocated uid and a StateDirectory give exactly that,
        # without this module creating a permanent account on the host.
        DynamicUser = true;
        StateDirectory = "zebra";
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (
        let
          addr = cfg.settings.network.listen_addr or "[::]:8233";
          port = lib.last (lib.splitString ":" addr);
        in
        lib.toInt port
      )
    ];
  };
}

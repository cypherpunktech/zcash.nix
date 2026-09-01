# The shared shape of a Zcash full node service.
#
# Zebra and Zakura are the same program in the ways that matter to a systemd
# unit: a TOML config passed with -c, a `start` subcommand, a chain-state
# directory that must live somewhere the daemon can actually write, and an RPC
# port that must never be firewalled open by default. Zakura is a Zebra fork,
# so this is a real shared structure rather than two things that happen to
# resemble each other today.
#
# What is NOT shared stays in the per-node file: package, config filename, and
# the documentation URL. If a future node diverges in structure rather than in
# those values, it should get its own module instead of an option added here to
# make one abstraction serve two masters.
{
  self,
  name,
  description,
  documentation,
  defaultPeerPort,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.${name};
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/${name}";

  # Freeform settings rather than an option per config key: these schemas are
  # dozens of fields across ten sections and gain more each release. Mirroring
  # one here would be a second copy that rots the first time upstream adds a
  # field. Options exist below only where the module must act on the value.
  configFile = toml.generate "${name}.toml" cfg.settings;
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
        Contents of `${name}.toml`, as a Nix attribute set.
        `state.cache_dir` defaults to the service's StateDirectory and should
        normally be left alone.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the peer-to-peer port in the firewall.

        Deliberately covers only the P2P listener. The RPC port is never
        opened: it is an administrative interface, and a node exposing it to
        the internet is a node somebody else is driving.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # StateDirectory provides the directory; the daemon still has to be told to
    # use it, because its own default is a home-directory cache that
    # ProtectHome makes invisible.
    services.zcash.${name}.settings = {
      state.cache_dir = lib.mkDefault stateDir;
      rpc.cookie_dir = lib.mkDefault stateDir;
    };

    systemd.services.${name} = {
      inherit description documentation;
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = (import ./hardening.nix) // {
        ExecStart = "${lib.getExe cfg.package} --config ${configFile} start";
        # DynamicUser: the node needs an identity to own its state and nothing
        # else. An allocated uid plus a StateDirectory gives exactly that,
        # without this module creating a permanent account on the host.
        DynamicUser = true;
        StateDirectory = name;
        StateDirectoryMode = "0700";
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (
        let
          addr = cfg.settings.network.listen_addr or defaultPeerPort;
        in
        lib.toInt (lib.last (lib.splitString ":" addr))
      )
    ];
  };
}

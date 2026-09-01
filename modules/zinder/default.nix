# services.zcash.zinder — the Zcash Foundation's indexer, as systemd services.
#
# WHY THIS ONE IS SHAPED DIFFERENTLY:
#
# Zinder is not one daemon. Upstream's supported topology is four independent
# runtimes sharing one host filesystem: ingest owns canonical storage,
# projector derives the wallet view from it, query serves native clients, and
# compat-lightwalletd serves existing lightwalletd clients. They coordinate
# through that shared tree, not through a socket.
#
# That breaks DynamicUser, which every other module here uses. DynamicUser
# allocates a *different* uid per service, so four of them cannot share a
# directory: ingest would write state that projector cannot read. So this
# module creates one static `zinder` user that all four run as. That is a real
# reduction in isolation compared to the rest of the repo, forced by the
# software's design rather than chosen, and it is why it is written down here
# instead of being noticed later from a permissions error.
#
# The rest of the hardening still applies unchanged.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.zinder;
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/zinder";
  configFile = toml.generate "zinder.toml" cfg.settings;

  # The four release runtimes, in the order they depend on one another. ingest
  # must exist before projector has anything to derive from, and both before a
  # reader can answer with data.
  runtimes = [
    "ingest"
    "projector"
    "query"
    "compat-lightwalletd"
  ];

  mkRuntime = rt: {
    name = "zinder-${rt}";
    value = {
      description = "Zinder ${rt} runtime";
      documentation = [ "https://github.com/ZcashFoundation/zinder" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ lib.optional (rt != "ingest") "zinder-ingest.service";
      wants = [ "network-online.target" ];

      serviceConfig = (import ../hardening.nix) // {
        ExecStart = "${cfg.package}/bin/zinder-${rt} --config ${configFile}";
        # Static user, not DynamicUser: see the note at the top of this file.
        User = "zinder";
        Group = "zinder";
        StateDirectory = "zinder";
        StateDirectoryMode = "0700";
      };
    };
  };
in
{
  options.services.zcash.zinder = {
    enable = lib.mkEnableOption "Zinder, the Zcash Foundation's Zcash indexer";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.zinder;
      defaultText = lib.literalExpression "zcash-nix.packages.\${system}.zinder";
      description = "The zinder package to run.";
    };

    runtimes = lib.mkOption {
      type = lib.types.listOf (lib.types.enum runtimes);
      default = runtimes;
      description = ''
        Which of Zinder's runtimes to run on this host.

        The default is all four, which is upstream's supported single-host
        topology. Splitting them across machines is possible but then the
        shared storage tree becomes your problem, not this module's.
      '';
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      description = ''
        Contents of the shared `zinder.toml`, as a Nix attribute set. One file
        is passed to every runtime, because they must agree about the storage
        layout they share; giving each its own would make disagreement
        possible.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.zinder = {
      isSystemUser = true;
      group = "zinder";
      home = stateDir;
      description = "Zinder indexer";
    };
    users.groups.zinder = { };

    systemd.services = lib.listToAttrs (map mkRuntime cfg.runtimes);
  };
}

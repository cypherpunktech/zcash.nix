# services.zcash.zinder.<instance> — the Zcash Foundation's indexer, as systemd services.
#
# WHY THIS ONE IS SHAPED DIFFERENTLY:
#
# Zinder is not one daemon. Upstream's supported topology is four independent
# runtimes sharing one host filesystem: ingest owns canonical storage,
# projector derives the wallet view from it, query serves native clients, and
# compat-lightwalletd serves existing lightwalletd clients. They coordinate
# through that shared tree, not through a socket.
#
# That rules out DynamicUser, which allocates a *different* uid per service:
# ingest would write state that projector cannot read. So an instance's `user`
# (see ../service.nix) defaults to a static `zinder-<instance>` that all four
# runtimes run as, and may not be null. That is a real reduction in isolation
# compared to the rest of the repo, forced by the software's design rather
# than chosen, and it is why it is written down here instead of being noticed
# later from a permissions error. The rest of the hardening applies unchanged.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "zinder";
  service = import ../service.nix {
    inherit
      lib
      self
      pkgs
      name
      ;
    description = "Zinder, the Zcash Foundation's Zcash indexer";
  };
  instances = service.enabled config.services.zcash.zinder;
  toml = pkgs.formats.toml { };

  # The four release runtimes, in the order they depend on one another. ingest
  # must exist before projector has anything to derive from, and both before a
  # reader can answer with data.
  runtimes = [
    "ingest"
    "projector"
    "query"
    "compat-lightwalletd"
  ];

  instance =
    { name, ... }:
    {
      options = service.options // {
        runtimes = lib.mkOption {
          type = lib.types.listOf (lib.types.enum runtimes);
          default = runtimes;
          description = ''
            Which of Zinder's runtimes to run in this instance.
            The default is all four, which is upstream's supported single-host
            topology. Splitting them across machines is possible but then the
            shared storage tree becomes your problem, not this module's.
          '';
        };

        settings = lib.mkOption {
          inherit (toml) type;
          default = { };
          description = ''
            Contents of the instance's shared `zinder.toml`, as a Nix attribute
            set. One file is passed to every runtime, because they must agree
            about the storage layout they share; giving each its own would make
            disagreement possible.
          '';
        };
      };

      config.user = lib.mkDefault "zinder-${name}";
    };

  # One unit per (instance, runtime).
  units = lib.concatMap (
    instanceName:
    let
      cfg = instances.${instanceName};
      unit = "zinder-${instanceName}";
      configFile = toml.generate "${unit}.toml" cfg.settings;
    in
    map (rt: {
      name = "${unit}-${rt}";
      value = {
        description = "Zinder ${rt} runtime (${instanceName})";
        documentation = [ "https://github.com/ZcashFoundation/zinder" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ] ++ lib.optional (rt != "ingest") "${unit}-ingest.service";
        wants = [ "network-online.target" ];
        unitConfig.RequiresMountsFor = [ "/var/lib/${unit}" ];
        serviceConfig = service.identity cfg unit // {
          ExecStart = lib.escapeShellArgs (
            [
              "${cfg.package}/bin/zinder-${rt}"
              "--config"
              configFile
            ]
            ++ cfg.extraArgs
          );
        };
      };
    }) cfg.runtimes
  ) (lib.attrNames instances);
in
{
  options.services.zcash.zinder = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instance);
    default = { };
    description = "Zinder instances, each four runtimes sharing one state directory.";
  };

  config = lib.mkIf (instances != { }) {
    assertions = map (instanceName: {
      assertion = instances.${instanceName}.user != null;
      message = "services.zcash.zinder.${instanceName}: the four runtimes share a storage tree and need one static user; `user` may not be null.";
    }) (lib.attrNames instances);

    systemd.services = lib.listToAttrs units;

    users = service.users instances;
  };
}

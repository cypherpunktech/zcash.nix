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
#
# Multi-instance: `services.zcash.zebra.<instance>`, see ./service.nix.
{
  self,
  name,
  description,
  documentation,
  defaultPeerPort,
  # Default settings a fork has and the original does not, as a function of
  # the instance's state directory (zakura's network identity file). Zebra
  # rejects unknown fields, so these cannot simply be set for both.
  defaults ? (_: { }),
  # Address families beyond IPv4/IPv6 the daemon needs (zakura: iroh watches
  # interfaces over netlink, and dies at startup without it).
  addressFamilies ? [ ],
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
  toml = pkgs.formats.toml { };
  nodeName = name;
  hardening = import ./hardening.nix;

  # A submodule under attrsOf receives its key as `name` -- only when it asks
  # for it by that exact name, which is why this shadows the node's own.
  instance =
    { name, ... }:
    let
      stateDir = "/var/lib/${nodeName}-${name}";
    in
    {
      options = service.options // {
        # Freeform settings rather than an option per config key: these
        # schemas are dozens of fields across ten sections and gain more each
        # release. Mirroring one here would be a second copy that rots the
        # first time upstream adds a field. Options exist only where the
        # module must act on the value.
        settings = lib.mkOption {
          inherit (toml) type;
          default = { };
          example = lib.literalExpression ''
            {
              network.network = "Testnet";
              rpc.listen_addr = "127.0.0.1:18232";
            }
          '';
          description = ''
            Contents of `${nodeName}.toml`, as a Nix attribute set.
            `state.cache_dir` defaults to the instance's state directory and
            should normally be left alone.
          '';
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Open the peer-to-peer port in the firewall.

            Deliberately covers only the P2P listener. The RPC port is never
            opened: it is an administrative interface, and a node exposing it
            to the internet is a node somebody else is driving.
          '';
        };
      };

      # StateDirectory provides the directory; the daemon still has to be told
      # to use it, because its own default is a home-directory cache that
      # ProtectHome makes invisible.
      config.settings = {
        state.cache_dir = lib.mkDefault stateDir;
        rpc.cookie_dir = lib.mkDefault stateDir;
      }
      // lib.mapAttrsRecursive (_: lib.mkDefault) (defaults stateDir);
    };
in
{
  options.services.zcash.${name} = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule instance);
    default = { };
    example = lib.literalExpression ''
      {
        mainnet.enable = true;
        testnet = {
          enable = true;
          settings.network.network = "Testnet";
        };
      }
    '';
    description = "${description}: one entry per instance, each its own unit and state directory.";
  };

  config = lib.mkIf (instances != { }) {
    assertions = lib.mapAttrsToList (instanceName: cfg: {
      # The cookie is the RPC's only authentication. Off on loopback is a
      # local trust decision; off on an address the network can reach is a
      # node anyone who finds the port can drive.
      assertion =
        (cfg.settings.rpc.enable_cookie_auth or true)
        || service.loopback (cfg.settings.rpc.listen_addr or "127.0.0.1:0");
      message = "services.zcash.${name}.${instanceName}: rpc.enable_cookie_auth = false with rpc.listen_addr ${cfg.settings.rpc.listen_addr} is an unauthenticated RPC on the network.";
    }) instances;

    systemd.services = lib.mapAttrs' (
      instanceName: cfg:
      lib.nameValuePair "${name}-${instanceName}" {
        description = "${description} (${instanceName})";
        inherit documentation;
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        # A mainnet chain is hundreds of GB and routinely its own mount.
        # Without this, a late mount means StateDirectory creates the
        # directory on the root filesystem and the node resyncs into it.
        unitConfig.RequiresMountsFor = [ "/var/lib/${name}-${instanceName}" ];
        serviceConfig =
          service.identity cfg "${name}-${instanceName}"
          // lib.optionalAttrs (addressFamilies != [ ]) {
            RestrictAddressFamilies = hardening.RestrictAddressFamilies ++ addressFamilies;
          }
          # Where RPC is configured, "started" means "RPC answers", not
          # "process forked": systemd does not complete this unit's start job,
          # and so does not release anything ordered After= it, until
          # ExecStartPost exits. An indexer that follows this node would
          # otherwise race a daemon that binds RPC only after opening its
          # state and writing its cookie. Bounded by TimeoutStartSec, which is
          # sized for a state-format migration on mainnet; on a host with no
          # DNS zebrad never binds RPC (tests/zebra.nix) and the unit sits in
          # "activating (start-post)" until then, which is the truthful state.
          // lib.optionalAttrs (cfg.settings.rpc ? listen_addr) {
            ExecStartPost = pkgs.writeShellScript "${name}-${instanceName}-rpc-ready" ''
              until (exec 3<>/dev/tcp/${service.hostOf cfg.settings.rpc.listen_addr}/${toString (service.portOf cfg.settings.rpc.listen_addr)}) 2>/dev/null; do sleep 1; done
            '';
            TimeoutStartSec = "15min";
          }
          # Zebra's internal miner lowers its solver thread's priority (the
          # thread-priority crate: pthread_setschedparam, then setpriority for
          # the nice value), and the shared filter's ~@resources forbids both:
          # the node took SIGSYS on its first block. Read off the kernel's audit
          # line (syscall=141, setpriority) rather than guessed. Allowed only
          # where mining is on; a production node keeps the full filter.
          // lib.optionalAttrs (cfg.settings.mining.internal_miner or false) {
            SystemCallFilter = hardening.SystemCallFilter ++ [
              "sched_setscheduler"
              "setpriority"
            ];
          }
          // {
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe cfg.package)
                "--config"
                (toml.generate "${name}-${instanceName}.toml" cfg.settings)
                "start"
              ]
              ++ cfg.extraArgs
            );
          };
      }
    ) instances;

    users = service.users instances;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      cfg:
      lib.optional cfg.openFirewall (service.portOf (cfg.settings.network.listen_addr or defaultPeerPort))
    ) (lib.attrValues instances);
  };
}

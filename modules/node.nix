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
  # UDP listeners beyond the TCP peer port, as addresses resolved from an
  # instance's settings (zakura: P2P v2's QUIC endpoint). openFirewall opens
  # these too; without them a v2 node only ever dials out.
  udpPeerAddrs ? (_: [ ]),
  # Published chain-state snapshot manifests, as network -> storage mode ->
  # URL (zakura: zakura.com's). null for a node nobody publishes snapshots
  # of, which then gets no snapshot option at all.
  snapshotManifests ? null,
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

  # Runs as the node's ExecStartPre, so as its identity, inside its sandbox:
  # the archive can write nowhere but the state directory. Every step is
  # restartable. The download resumes, a checksum mismatch deletes it, and the
  # unpack goes to a scratch directory that becomes `state` in one rename, so
  # a node killed at any point either has no state or a whole one.
  restoreSnapshot = pkgs.writeShellApplication {
    name = "${name}-restore-snapshot";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      gnutar
      jq
      zstd
    ];
    text = ''
      manifest=$1 version=$2 cache=$3
      [[ -e $cache/state ]] && exit 0

      entry=$(curl -fsSL --retry 5 --retry-connrefused "$manifest" |
        jq -ce --arg v "$version" '
          (map(select(.${name}_version == $v)) + map(select(.roles // [] | index("latest"))))[0]')
      field() { jq -r ".$1" <<<"$entry"; }
      file=$(field filename)
      [[ $file =~ ^[A-Za-z0-9._-]+$ ]] || { echo "refusing snapshot filename '$file'" >&2; exit 1; }
      echo "restoring $file: height $(field height), written by ${name} $(field ${name}_version)"

      dl=$cache/snapshot
      mkdir -p "$dl"
      # Anything else here is a partial download of a snapshot since replaced.
      find "$dl" -mindepth 1 -maxdepth 1 ! -name "$file" -exec rm -rf {} +
      if (($(stat -c %s "$dl/$file" 2>/dev/null || echo 0) < $(field size_bytes))); then
        # 33: the server refused to resume, so the partial file is dead weight.
        curl -fL --retry 5 --retry-connrefused -C - -o "$dl/$file" "$(field url)" ||
          { rc=$?; ((rc != 33)) || rm -f "$dl/$file"; exit "$rc"; }
      fi
      sha256sum -c <<<"$(field sha256)  $dl/$file" || { rm -f "$dl/$file"; exit 1; }

      mkdir "$dl/unpacked"
      zstd -dc "$dl/$file" | tar -x -C "$dl/unpacked"
      mv "$dl/unpacked/state" "$cache/state"
      rm -rf "$dl"
    '';
  };

  # Its state is its memory: PartOf restarts it with the node, so "ready once
  # since start" starts over exactly when the node does. Root only to reach
  # systemctl; it has no capabilities and writes nowhere.
  watchdog = pkgs.writeShellApplication {
    name = "${name}-watchdog";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      systemd
    ];
    text = ''
      url=$1 stall_after=$2 unit=$3
      ready_once=0 failing_since=
      while true; do
        if curl -fsS -o /dev/null --max-time 10 "$url"; then
          ready_once=1 failing_since=
        elif ((ready_once)); then
          now=$(date +%s)
          failing_since=''${failing_since:-$now}
          if ((now - failing_since >= stall_after)); then
            echo "$unit has not been ready for ''${stall_after}s; restarting it"
            systemctl restart --no-block "$unit"
          fi
        fi
        sleep 15
      done
    '';
  };

  # A submodule under attrsOf receives its key as `name` -- only when it asks
  # for it by that exact name, which is why this shadows the node's own.
  instance =
    { name, config, ... }:
    let
      stateDir = "/var/lib/${nodeName}-${name}";
      network = lib.toLower (config.settings.network.network or "Mainnet");
      # A string ("pruned"), or a table keyed by the mode ({ pruned = {..}; }).
      storageMode =
        let
          mode = config.settings.state.storage_mode or "archive";
        in
        if lib.isString mode then mode else lib.head (lib.attrNames mode);
    in
    {
      options =
        service.options
        // {
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
                metrics.endpoint_addr = "127.0.0.1:9999"; # Prometheus, on loopback
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

              Deliberately covers only the P2P listeners. The RPC port is never
              opened: it is an administrative interface, and a node exposing it
              to the internet is a node somebody else is driving.
            '';
          };

          watchdog = {
            enable = lib.mkEnableOption ''
              restarting the node once it has stopped following the chain.
              Systemd's own restart covers a process that dies; this covers one
              that is alive and stuck. It polls the `/ready` health endpoint, so
              `settings.health.listen_addr` must be set, and acts only after the
              node has been ready once since it started: a node syncing from
              genesis is not ready for days, and restarting it would only make
              that longer'';

            stallAfter = lib.mkOption {
              type = lib.types.ints.positive;
              # Blocks arrive every 75 s on average, and /ready fails once the
              # tip is 5 min old, which honest gaps reach about once a day
              # (e^-4 of blocks). 30 min without a block is e^-24: a stall.
              default = 1800;
              description = "Seconds `/ready` must keep failing before the node is restarted.";
            };
          };
        }
        // lib.optionalAttrs (snapshotManifests != null) {
          snapshot = {
            enable = lib.mkEnableOption ''
              restoring a published chain-state snapshot when the state directory
              has none, instead of syncing from genesis. A node restored this way
              trusts the publisher for the history the snapshot contains; one
              synced from the network validates it. The archive is downloaded
              beside the state before it is unpacked, so the disk needs room for
              both once'';

            manifest = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = snapshotManifests.${network}.${storageMode} or null;
              defaultText = lib.literalMD "the publisher's manifest for `settings.network.network` and `settings.state.storage_mode`";
              description = ''
                URL of the snapshot manifest: a JSON array of entries with
                `url`, `filename`, `sha256`, `size_bytes`, `height`,
                `${nodeName}_version` and `roles`. The entry written by this
                instance's own version is preferred, since a database of another
                major format is rejected and resynced from genesis; failing
                that, the one marked `latest`.
              '';
            };
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
    # The cookie is the RPC's only authentication: zebra has no user/password
    # mode. Off on loopback is a local trust decision; off on an address the
    # network can reach is an RPC anyone who finds the port can drive. A
    # warning rather than an assertion, because lightwalletd on another host
    # has no cookie support and needs exactly this -- behind a firewall or a
    # private network, which is the operator's to arrange and this module's
    # to name.
    warnings = lib.concatLists (
      lib.mapAttrsToList (
        instanceName: cfg:
        lib.optional
          (
            !(cfg.settings.rpc.enable_cookie_auth or true)
            && !service.loopback (cfg.settings.rpc.listen_addr or "127.0.0.1:0")
          )
          "services.zcash.${name}.${instanceName}: rpc.enable_cookie_auth = false with rpc.listen_addr ${cfg.settings.rpc.listen_addr} is an unauthenticated RPC reachable from the network; make sure only the intended hosts can."
      ) instances
    );

    assertions = lib.concatLists (
      lib.mapAttrsToList (instanceName: cfg: [
        {
          assertion = cfg.watchdog.enable -> cfg.settings ? health.listen_addr;
          message = "services.zcash.${name}.${instanceName}.watchdog polls /ready: set settings.health.listen_addr.";
        }
        {
          assertion = (cfg.snapshot.enable or false) -> cfg.snapshot.manifest != null;
          message = "services.zcash.${name}.${instanceName}.snapshot: nothing is published for this network and storage mode; set snapshot.manifest.";
        }
      ]) instances
    );

    systemd.services =
      lib.mapAttrs' (
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
            # After the RPC block on purpose: a restore is hundreds of GB for an
            # archive node, so its start has no bound but the download. A failed
            # one retries under the unit's own Restart, resuming.
            // lib.optionalAttrs (cfg.snapshot.enable or false) {
              ExecStartPre = lib.escapeShellArgs [
                (lib.getExe restoreSnapshot)
                cfg.snapshot.manifest
                cfg.package.version
                cfg.settings.state.cache_dir
              ];
              TimeoutStartSec = "infinity";
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
              # Past this the kernel kills the node rather than the host: sshd
              # and the watchdog keep their tenth, and Restart brings it back.
              MemoryMax = lib.mkDefault "90%";
            };
        }
      ) instances
      // lib.mapAttrs' (
        instanceName: cfg:
        let
          unit = "${name}-${instanceName}";
        in
        lib.nameValuePair "${unit}-watchdog" {
          description = "Restarts ${unit} when it stops following the chain";
          wantedBy = [ "${unit}.service" ];
          after = [ "${unit}.service" ];
          partOf = [ "${unit}.service" ];
          serviceConfig = {
            ExecStart = lib.escapeShellArgs [
              (lib.getExe watchdog)
              "http://${cfg.settings.health.listen_addr}/ready"
              (toString cfg.watchdog.stallAfter)
              "${unit}.service"
            ];
            Restart = "on-failure";
            CapabilityBoundingSet = "";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        }
      ) (lib.filterAttrs (_: cfg: cfg.watchdog.enable) instances);

    users = service.users instances;

    networking.firewall.allowedTCPPorts = lib.concatMap (
      cfg:
      lib.optional cfg.openFirewall (service.portOf (cfg.settings.network.listen_addr or defaultPeerPort))
    ) (lib.attrValues instances);
    networking.firewall.allowedUDPPorts = lib.concatMap (
      cfg: lib.optionals cfg.openFirewall (map service.portOf (udpPeerAddrs cfg.settings))
    ) (lib.attrValues instances);
  };
}

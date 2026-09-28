# tests/zebra.nix for Zakura. Not redundant with it: Zakura's P2P layer is
# its own (iroh, with a netlink network monitor and a persisted identity
# key), which is exactly the part the shared hardening broke -- found first
# in the embedded copy inside ztreamer, because until this file existed no
# test ever ran zakurad at all.
#
# Also what a fleet node leans on: a snapshot restore, the v2 port, and the
# watchdog. The snapshot comes from a mirror on the machine itself, whose
# manifest marks a decoy with a bad checksum `latest`: a restore that picked
# it instead of the entry matching this build's version fails the checksum
# and never starts the node. The node is ephemeral, so the restored `state`
# is only checked, never opened.
_self: _: {
  name = "zcash-zakura";

  nodes.machine =
    { config, pkgs, ... }:
    let
      mirror =
        pkgs.runCommand "zakura-snapshot-mirror"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.zstd
            ];
          }
          ''
            mkdir -p $out unpacked/state
            echo restored > unpacked/state/marker
            tar -C unpacked -c state | zstd > $out/good.tar.zst
            jq -n \
              --arg sha "$(sha256sum $out/good.tar.zst | cut -d' ' -f1)" \
              --argjson size "$(stat -c %s $out/good.tar.zst)" \
              --arg version ${config.services.zcash.zakura.regtest.package.version} '[
                { filename: "decoy.tar.zst", url: "http://127.0.0.1:8000/good.tar.zst",
                  sha256: "0000000000000000000000000000000000000000000000000000000000000000", size_bytes: $size, height: 2,
                  zakura_version: "0.0.0-decoy", roles: ["latest"] },
                { filename: "good.tar.zst", url: "http://127.0.0.1:8000/good.tar.zst",
                  sha256: $sha, size_bytes: $size, height: 1,
                  zakura_version: $version, roles: ["daily"] }
              ]' > $out/snapshots.json
          '';
    in
    {
      services.zcash.zakura.regtest = {
        enable = true;
        openFirewall = true;
        snapshot = {
          enable = true;
          manifest = "http://127.0.0.1:8000/snapshots.json";
        };
        watchdog = {
          enable = true;
          stallAfter = 30;
        };
        settings.health.listen_addr = "127.0.0.1:8080";
      };

      systemd.services.snapshot-mirror = {
        wantedBy = [ "multi-user.target" ];
        before = [ "zakura-regtest.service" ];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server --bind 127.0.0.1 --directory ${mirror} 8000";
      };

      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.wait_for_unit("zakura-regtest.service")

    with subtest("restores the snapshot this version wrote, not the decoy"):
        marker = machine.succeed("cat /var/lib/zakura-regtest/state/marker").strip()
        assert marker == "restored", f"state/marker is {marker!r}"
        journal = machine.succeed("journalctl -b -u zakura-regtest.service --no-pager")
        assert "restoring good.tar.zst" in journal, f"no restore of good.tar.zst in:\n{journal}"
        leftovers = machine.succeed("ls -A /var/lib/zakura-regtest").split()
        assert "snapshot" not in leftovers, f"download dir left behind: {leftovers}"

    with subtest("answers JSON-RPC"):
        out = machine.succeed(
            "curl -s --fail --max-time 10 -H 'Content-Type: application/json' "
            "--data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getinfo\",\"params\":[]}' "
            "http://127.0.0.1:18232"
        )
        assert '"result"' in out, f"getinfo returned no result: {out}"

    with subtest("started once: no crash behind the start"):
        restarts = machine.succeed("systemctl show -p NRestarts --value zakura-regtest.service").strip()
        assert restarts == "0", f"zakura-regtest restarted {restarts} times"

    # State is private to the service (stat -L: see tests/zebra.nix).
    mode = machine.succeed("stat -Lc %a /var/lib/zakura-regtest").strip()
    assert mode == "700", f"/var/lib/zakura-regtest is mode {mode}, expected 700"

    with subtest("P2P v2 listens on UDP 8234, and the firewall lets it in"):
        machine.wait_until_succeeds("ss -Huln 'sport = :8234' | grep -q .", timeout=60)
        rules = machine.succeed("iptables -S nixos-fw")
        assert any("udp" in r and "8234" in r for r in rules.splitlines()), f"no udp 8234 rule in:\n{rules}"

    with subtest("the watchdog restarts a node that is alive but stuck"):
        machine.wait_until_succeeds("curl -sf --max-time 5 http://127.0.0.1:8080/ready", timeout=120)
        # One poll interval, so the watchdog has seen it ready.
        machine.sleep(16)
        pid = machine.succeed("systemctl show -p MainPID --value zakura-regtest.service").strip()
        machine.succeed(f"kill -STOP {pid}")
        machine.wait_until_succeeds(
            f"test \"$(systemctl show -p MainPID --value zakura-regtest.service)\" != {pid}",
            timeout=180,
        )
        machine.wait_until_succeeds("curl -sf --max-time 5 http://127.0.0.1:8080/ready", timeout=120)
  '';
}

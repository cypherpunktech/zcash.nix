# tests/zebra.nix for Zakura. Not redundant with it: Zakura's P2P layer is
# its own (iroh, with a netlink network monitor and a persisted identity
# key), which is exactly the part the shared hardening broke -- found first
# in the embedded copy inside ztreamer, because until this file existed no
# test ever ran zakurad at all.
_self: _: {
  name = "zcash-zakura";

  nodes.machine = {
    services.zcash.zakura.regtest.enable = true;
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("zakura-regtest.service")

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
  '';
}

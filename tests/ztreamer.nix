# Boots a machine with the ztreamer module and asserts the whole process
# comes up: the embedded zakura node, its JSON-RPC, and the CompactTxStreamer
# gRPC listener. The embedded node is configured by tests/fixtures/regtest.nix.
#
# The gRPC port is the part that is ztreamer's own. ztreamerd indexes the
# chain it has before it serves, so a listening 9067 means the historical
# pass ran to the tip -- genesis, here -- and the server started after it.
_self: _: {
  name = "zcash-ztreamer";

  nodes.machine = {
    services.zcash.ztreamer.regtest.enable = true;
    virtualisation.memorySize = 3072;
  };

  testScript = ''
    machine.wait_for_unit("ztreamer-regtest.service")
    machine.wait_until_succeeds("systemctl is-active --quiet ztreamer-regtest.service", timeout=60)

    with subtest("the embedded node is a whole node: it answers JSON-RPC"):
        machine.wait_for_open_port(18232)
        out = machine.succeed(
            "curl -s --fail --max-time 10 -H 'Content-Type: application/json' "
            "--data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getinfo\",\"params\":[]}' "
            "http://127.0.0.1:18232"
        )
        assert '"result"' in out, f"getinfo returned no result: {out}"

    # ztreamer's own server, up only once indexing reached the tip.
    machine.wait_for_open_port(9067, timeout=120)
    machine.wait_for_open_port(9999)

    with subtest("started once: no crash behind the start"):
        restarts = machine.succeed("systemctl show -p NRestarts --value ztreamer-regtest.service").strip()
        assert restarts == "0", f"ztreamer-regtest restarted {restarts} times"

    # The index landed inside the private state directory (stat -L: see
    # tests/zebra.nix for the DynamicUser symlink).
    machine.succeed("test -d /var/lib/ztreamer-regtest/index")
    mode = machine.succeed("stat -Lc %a /var/lib/ztreamer-regtest").strip()
    assert mode == "700", f"/var/lib/ztreamer-regtest is mode {mode}, expected 700"
  '';
}

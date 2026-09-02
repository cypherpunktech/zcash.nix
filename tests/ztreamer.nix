# Boots a machine with the ztreamer module and asserts the whole process
# comes up: the embedded zakura node, its JSON-RPC, and the CompactTxStreamer
# gRPC listener. Same shape as tests/zebra.nix, because the same daemon is
# inside; see there for why the empty peer lists are load-bearing.
#
# The gRPC port is the part that is ztreamer's own. ztreamerd indexes the
# chain it has before it serves, so a listening 9067 means the historical
# pass ran to the tip -- genesis, here -- and the server started after it.
self: _: {
  name = "zcash-ztreamer";

  nodes.machine =
    { ... }:
    {
      imports = [ self.nixosModules.ztreamer ];

      services.zcash.ztreamer = {
        enable = true;
        settings = {
          network = {
            network = "Regtest";
            initial_mainnet_peers = [ ];
            initial_testnet_peers = [ ];
            cache_dir = false;
          };
          rpc.listen_addr = "127.0.0.1:18232";
          rpc.enable_cookie_auth = false;
        };
      };

      virtualisation.memorySize = 3072;
    };

  testScript = ''
    machine.wait_for_unit("ztreamer.service")
    machine.wait_until_succeeds("systemctl is-active --quiet ztreamer.service", timeout=60)

    # The embedded node is a whole node: it answers JSON-RPC.
    machine.wait_for_open_port(18232)
    machine.succeed(
        "curl -s --fail --max-time 10 -H 'Content-Type: application/json' "
        "--data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getinfo\",\"params\":[]}' "
        "http://127.0.0.1:18232 | grep -q result"
    )

    # ztreamer's own server, up only once indexing reached the tip.
    machine.wait_for_open_port(9067, timeout=120)
    machine.wait_for_open_port(9999)

    props = machine.succeed(
        "systemctl show ztreamer.service "
        "-p DynamicUser -p ProtectSystem -p NoNewPrivileges -p CapabilityBoundingSet"
    )
    assert "DynamicUser=yes" in props, props
    assert "ProtectSystem=strict" in props, props
    assert "NoNewPrivileges=yes" in props, props
    assert "CapabilityBoundingSet=" in props, props

    # The index landed inside the private state directory (stat -L: see
    # tests/zebra.nix for the DynamicUser symlink).
    machine.succeed("test -d /var/lib/ztreamer/index")
    mode = machine.succeed("stat -Lc %a /var/lib/ztreamer").strip()
    assert mode == "700", f"/var/lib/ztreamer is mode {mode}, expected 700"
  '';
}

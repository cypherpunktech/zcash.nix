# tests/lightwalletd.nix for the Rust implementation: the same pairing with a
# Zebra node, the same unit assertions, through the same shared module. The
# two differences are the ones the module declares -- no credentials needed
# (zebra runs with cookie auth off), no log redirect -- and one that is
# ztreamer-style behaviour rather than configuration: lightwalletd-rs checks
# its backend at startup, so a green unit here means it reached the node.
self: _: {
  name = "zcash-lightwalletd-rs";

  nodes.machine =
    { ... }:
    {
      imports = [
        self.nixosModules.zebra
        self.nixosModules.lightwalletd-rs
      ];

      services.zcash.zebra = {
        enable = true;
        settings = {
          network = {
            network = "Regtest";
            initial_mainnet_peers = [ ];
            initial_testnet_peers = [ ];
            cache_dir = false;
          };
          state.ephemeral = true;
          rpc.listen_addr = "127.0.0.1:18232";
          rpc.enable_cookie_auth = false;
        };
      };

      services.zcash.lightwalletd-rs = {
        enable = true;
        rpcPort = 18232;
        insecureNoTLS = true;
      };

      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.wait_for_unit("zebra.service")
    machine.wait_for_open_port(18232)

    machine.wait_for_unit("lightwalletd-rs.service")
    machine.wait_until_succeeds("systemctl is-active --quiet lightwalletd-rs.service", timeout=60)
    machine.wait_for_open_port(9067)

    props = machine.succeed(
        "systemctl show lightwalletd-rs.service "
        "-p DynamicUser -p ProtectSystem -p NoNewPrivileges -p MemoryDenyWriteExecute"
    )
    assert "DynamicUser=yes" in props, props
    assert "ProtectSystem=strict" in props, props
    assert "NoNewPrivileges=yes" in props, props
    assert "MemoryDenyWriteExecute=yes" in props, props

    machine.succeed("test -d /var/lib/lightwalletd-rs")
    machine.succeed("journalctl -u lightwalletd-rs.service --no-pager | head -c 1 | grep -q .")
  '';
}

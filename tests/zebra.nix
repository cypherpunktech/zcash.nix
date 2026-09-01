# Boots a machine, enables the module, and asserts Zebra actually runs.
#
# This is the check the packages' smoke tests cannot be: `zebrad --version`
# proves a binary starts, and says nothing about whether the unit around it
# works. Almost every way a service module is wrong -- an unwritable state
# directory, a config the daemon rejects, a hardening flag that kills it on
# first syscall -- produces a package that passes smoke and a machine that does
# not boot a working node.
self: _: {
  name = "zcash-zebra";

  nodes.machine = {
    imports = [ self.nixosModules.zebra ];

    services.zcash.zebra = {
      enable = true;
      settings = {
        network = {
          network = "Regtest";
          # THE EMPTY SEED LISTS ARE LOAD-BEARING. A NixOS test VM has no
          # network, and zebrad blocks startup resolving seed peers: it loops
          # "empty peer list after DNS resolution, retrying after 5 seconds"
          # forever and never binds its RPC port, so the test times out while
          # the daemon looks perfectly healthy in the journal.
          #
          # Regtest does not save you from this on its own -- Zebra treats it
          # as a testnet variant and still resolves the testnet seeds.
          # Verified by running zebrad locally with exactly this config: RPC
          # answered getinfo on the first attempt.
          initial_mainnet_peers = [ ];
          initial_testnet_peers = [ ];
          cache_dir = false;
        };
        state.ephemeral = true;
        rpc.listen_addr = "127.0.0.1:18232";
        rpc.enable_cookie_auth = false;
      };
    };

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("zebra.service")

    # Running, not merely started-and-exited: a crash loop also "starts".
    machine.wait_until_succeeds("systemctl is-active --quiet zebra.service", timeout=60)

    # It answers RPC, which means it got through config parsing and opened its
    # state directory -- the two things a broken module actually breaks.
    machine.wait_for_open_port(18232)
    machine.succeed(
        "curl -s --fail --max-time 10 -H 'Content-Type: application/json' "
        "--data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getinfo\",\"params\":[]}' "
        "http://127.0.0.1:18232 | grep -q result"
    )

    # The hardening is asserted, not assumed. If a future edit drops
    # DynamicUser or relaxes ProtectSystem, this fails rather than quietly
    # shipping a node running as root.
    props = machine.succeed(
        "systemctl show zebra.service "
        "-p DynamicUser -p ProtectSystem -p NoNewPrivileges -p CapabilityBoundingSet"
    )
    assert "DynamicUser=yes" in props, props
    assert "ProtectSystem=strict" in props, props
    assert "NoNewPrivileges=yes" in props, props
    assert "CapabilityBoundingSet=" in props, props

    # State landed in the StateDirectory and is private to the service.
    machine.succeed("test -d /var/lib/zebra")
    machine.succeed("test $(stat -c %a /var/lib/zebra) = 700")

    # Not running as root.
    machine.fail("systemctl show zebra.service -p User | grep -q 'User=root'")
  '';
}

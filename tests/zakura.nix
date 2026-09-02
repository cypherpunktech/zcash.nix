# tests/zebra.nix for Zakura. Not redundant with it: Zakura's P2P layer is
# its own (iroh, with a netlink network monitor and a persisted identity
# key), which is exactly the part the shared hardening broke -- found first
# in the embedded copy inside ztreamer, because until this file existed no
# test ever ran zakurad at all.
#
# This is the check the packages' smoke tests cannot be: `zakurad --version`
# proves a binary starts, and says nothing about whether the unit around it
# works. Almost every way a service module is wrong -- an unwritable state
# directory, a config the daemon rejects, a hardening flag that kills it on
# first syscall -- produces a package that passes smoke and a machine that does
# not boot a working node.
self: _: {
  name = "zcash-zakura";

  nodes.machine =
    { ... }:
    {
      imports = [ self.nixosModules.zakura ];

      services.zcash.zakura.regtest = {
        enable = true;
        settings = {
          network = {
            network = "Regtest";
            # Empty seed lists: the VM has no network, and the daemon otherwise
            # loops on seed-peer DNS forever. See tests/zebra.nix; the embedded
            # zakura in tests/ztreamer.nix ran to RPC with exactly this config.
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
    machine.wait_for_unit("zakura-regtest.service")

    # Running, not merely started-and-exited: a crash loop also "starts".
    machine.wait_until_succeeds("systemctl is-active --quiet zakura-regtest.service", timeout=60)

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
        "systemctl show zakura-regtest.service "
        "-p DynamicUser -p ProtectSystem -p NoNewPrivileges -p CapabilityBoundingSet"
    )
    assert "DynamicUser=yes" in props, props
    assert "ProtectSystem=strict" in props, props
    assert "NoNewPrivileges=yes" in props, props
    assert "CapabilityBoundingSet=" in props, props

    # State landed in the StateDirectory and is private to the service.
    machine.succeed("test -d /var/lib/zakura-regtest")

    # -L is load-bearing, and the reason is worth knowing: under DynamicUser
    # systemd puts the real directory at /var/lib/private/zakura-regtest and makes
    # /var/lib/zakura-regtest a symlink to it. `stat` does not follow symlinks by
    # default, so without -L this reads the symlink's own mode, which is always
    # 777, and the assertion fails while the actual directory is 0700.
    #
    # The value is interpolated into the message rather than compared inside
    # the shell: `test $(...) = 700` fails without ever saying what it saw,
    # which cost a CI round trip to work out.
    mode = machine.succeed("stat -Lc %a /var/lib/zakura-regtest").strip()
    assert mode == "700", f"/var/lib/zakura-regtest is mode {mode}, expected 700"

    # Not running as root.
    machine.fail("systemctl show zakura-regtest.service -p User | grep -q 'User=root'")
  '';
}

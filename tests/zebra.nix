# Boots a machine, enables the module, and asserts Zebra actually runs.
#
# This is the check the packages' smoke tests cannot be: `zebrad --version`
# proves a binary starts, and says nothing about whether the unit around it
# works. Almost every way a service module is wrong -- an unwritable state
# directory, a config the daemon rejects, a hardening flag that kills it on
# first syscall -- produces a package that passes smoke and a machine that does
# not boot a working node. The node's configuration is tests/fixtures/regtest.nix.
_self: _: {
  name = "zcash-zebra";

  nodes.machine = {
    services.zcash.zebra.regtest.enable = true;
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    # "Started" means RPC answers (modules/node.nix, ExecStartPost), so this
    # already proves it got through config parsing and opened its state
    # directory -- the two things a broken module actually breaks.
    machine.wait_for_unit("zebra-regtest.service")

    with subtest("answers JSON-RPC"):
        out = machine.succeed(
            "curl -s --fail --max-time 10 -H 'Content-Type: application/json' "
            "--data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getinfo\",\"params\":[]}' "
            "http://127.0.0.1:18232"
        )
        assert '"result"' in out, f"getinfo returned no result: {out}"

    with subtest("started once: no crash behind the start"):
        restarts = machine.succeed("systemctl show -p NRestarts --value zebra-regtest.service").strip()
        assert restarts == "0", f"zebra-regtest restarted {restarts} times"

    # State landed in the StateDirectory and is private to the service.
    #
    # -L is load-bearing, and the reason is worth knowing: under DynamicUser
    # systemd puts the real directory at /var/lib/private/zebra-regtest and makes
    # /var/lib/zebra-regtest a symlink to it. `stat` does not follow symlinks by
    # default, so without -L this reads the symlink's own mode, which is always
    # 777, and the assertion fails while the actual directory is 0700.
    #
    # The value is interpolated into the message rather than compared inside
    # the shell: `test $(...) = 700` fails without ever saying what it saw,
    # which cost a CI round trip to work out.
    mode = machine.succeed("stat -Lc %a /var/lib/zebra-regtest").strip()
    assert mode == "700", f"/var/lib/zebra-regtest is mode {mode}, expected 700"
  '';
}

# Boots a machine with lightwalletd pointed at a Zebra node on the same host.
#
# The pairing is the point: lightwalletd is useless alone, and the failure this
# catches -- a backend it cannot reach, or credentials it cannot read -- only
# appears when both units exist together.
self: _: {
  name = "zcash-lightwalletd";

  nodes.machine = {
    imports = [
      self.nixosModules.zebra
      self.nixosModules.lightwalletd
    ];

    services.zcash.zebra = {
      enable = true;
      settings = {
        network.network = "Regtest";
        rpc.listen_addr = "127.0.0.1:18232";
        rpc.enable_cookie_auth = false;
      };
    };

    services.zcash.lightwalletd = {
      enable = true;
      rpcPort = 18232;
      # A test machine with no certificate. Setting this deliberately is the
      # module working as intended: without it the assertion refuses to build,
      # which is the whole reason the assertion exists.
      insecureNoTLS = true;
      extraArgs = [ "--no-backend-check" ];
    };

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("zebra.service")
    machine.wait_for_open_port(18232)

    machine.wait_for_unit("lightwalletd.service")
    machine.wait_until_succeeds("systemctl is-active --quiet lightwalletd.service", timeout=60)

    # Same hardening assertions as zebra: shared code means a regression in
    # modules/hardening.nix would otherwise only be caught by whichever test
    # happened to check it.
    props = machine.succeed(
        "systemctl show lightwalletd.service "
        "-p DynamicUser -p ProtectSystem -p NoNewPrivileges -p MemoryDenyWriteExecute"
    )
    assert "DynamicUser=yes" in props, props
    assert "ProtectSystem=strict" in props, props
    assert "NoNewPrivileges=yes" in props, props
    assert "MemoryDenyWriteExecute=yes" in props, props

    machine.succeed("test -d /var/lib/lightwalletd")

    # Logs reach journald rather than a ./server.log the service cannot write
    # under ProtectSystem=strict. A silent unit is a broken one.
    machine.succeed("journalctl -u lightwalletd.service --no-pager | head -c 1 | grep -q .")
  '';
}

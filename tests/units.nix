# One machine with every service module enabled, asserting the properties that
# must hold for all of them.
#
# Why this exists alongside the per-service tests: zebra, ztreamer, the two
# lightwalletds and (in tests/stack.nix, against a self-mining Regtest chain)
# zaino can be driven to a healthy state in a VM, but zinder and zallet cannot
# without an initialised wallet or a real chain. Writing "wait_for_unit" tests
# for those would produce tests that fail for reasons unrelated to the module.
#
# What CAN be asserted for all of them, and is exactly where module bugs live:
# that the units are well-formed, that nothing runs as root, and that the
# hardening in modules/hardening.nix actually reached every service. Those are
# checked here mechanically. Two shapes are exercised on purpose: zebra runs
# two instances (the reason the modules are multi-instance), and one of them
# shares a static user with zallet (the reason `user` exists), so the identity
# rules of modules/service.nix are asserted rather than assumed.
_self: _: {
  name = "zcash-units";

  nodes.machine = {
    imports = [ ./fixtures/credentials.nix ];

    services.zcash = {
      zebra.mainnet.enable = true;
      # A second instance, sharing its identity with the wallet that reads
      # its state database.
      zebra.shared = {
        enable = true;
        user = "zcash-shared";
      };
      zakura.main.enable = true;
      zaino.main.enable = true;
      zinder.main.enable = true;
      ztreamer.main.enable = true;
      lightwalletd.main = {
        enable = true;
        insecureNoTLS = true;
        zcashConfPath = "/var/lib/test-secrets/zcash.conf";
      };
      lightwalletd-rs.main = {
        enable = true;
        insecureNoTLS = true;
      };
      zallet = {
        enable = true;
        acceptBetaRisk = true;
        user = "zcash-shared";
      };
      zpay.enable = true;
    };

    virtualisation.memorySize = 3072;
  };

  testScript =
    { nodes, ... }:
    ''
      dynamic = [
          "zebra-mainnet", "zakura-main", "zaino-main", "ztreamer-main",
          "lightwalletd-main", "lightwalletd-rs-main", "zpay",
      ]
      static = {
          "zebra-shared": "zcash-shared",
          "zallet": "zcash-shared",
          "zinder-main-ingest": "zinder-main",
          "zinder-main-projector": "zinder-main",
          "zinder-main-query": "zinder-main",
          "zinder-main-compat-lightwalletd": "zinder-main",
      }
      services = dynamic + list(static)

      # Well-formed units. systemd-analyze verify catches a malformed ExecStart,
      # an unknown directive, and a typo in a hardening option -- all of which a
      # module can emit while still evaluating cleanly.
      for s in services:
          machine.succeed(f"systemd-analyze verify {s}.service")

      # Nothing runs as root. This is the single assertion most worth having:
      # every other hardening directive is a refinement on top of it.
      for s in services:
          out = machine.succeed(f"systemctl show {s}.service -p User -p DynamicUser")
          assert "User=root" not in out, f"{s} runs as root: {out}"

      # The shared hardening reached every service. If modules/hardening.nix is
      # edited, or a module stops importing it, this fails for all of them at
      # once rather than for whichever service someone remembered to test.
      for s in services:
          out = machine.succeed(
              f"systemctl show {s}.service "
              "-p ProtectSystem -p NoNewPrivileges -p CapabilityBoundingSet "
              "-p MemoryDenyWriteExecute -p RestrictNamespaces -p ProtectHome"
          )
          assert "ProtectSystem=strict" in out, f"{s}: {out}"
          assert "NoNewPrivileges=yes" in out, f"{s}: {out}"
          assert "CapabilityBoundingSet=\n" in out + "\n", f"{s} has capabilities: {out}"
          assert "MemoryDenyWriteExecute=yes" in out, f"{s}: {out}"
          assert "RestrictNamespaces=yes" in out, f"{s}: {out}"
          assert "ProtectHome=yes" in out, f"{s}: {out}"

      # Identity, as modules/service.nix defines it: no `user` means an
      # allocated DynamicUser; a `user` means that static user, created, and
      # DynamicUser off. zinder's four runtimes default to one static user
      # because they share a storage tree; a node and a wallet given the same
      # name share it -- which is the whole point of the option.
      for s in dynamic:
          out = machine.succeed(f"systemctl show {s}.service -p DynamicUser")
          assert "DynamicUser=yes" in out, f"{s} should use DynamicUser: {out}"

      for s, user in static.items():
          out = machine.succeed(f"systemctl show {s}.service -p DynamicUser -p User")
          assert "DynamicUser=no" in out, f"{s} must not use DynamicUser: {out}"
          assert f"User={user}" in out, f"{s} should run as {user}: {out}"
          machine.succeed(f"id -u {user}")

      # Two instances of one node are two units with two state directories.
      machine.succeed("test /var/lib/zebra-mainnet != /var/lib/zebra-shared")
      for s in ["zebra-mainnet", "zebra-shared"]:
          out = machine.succeed(f"systemctl show {s}.service -p StateDirectory")
          assert f"StateDirectory={s}" in out, out

      # Nothing listens off loopback except a node's peer port. Every RPC, gRPC
      # and metrics listener in these modules defaults to 127.0.0.1, and every
      # module says so in prose; this is what notices a future default, or a
      # future daemon, quietly changing that. A snapshot of what came up in
      # this boot (ss -H: no header; column 4 is the local address:port).
      listeners = machine.succeed("ss -ltnH | awk '{print $4}'").split()
      exposed = [l for l in listeners if not l.startswith(("127.", "[::1]")) and not l.endswith(":8233")]
      assert not exposed, f"listening off loopback: {exposed}"

      # And no module opened a firewall port by default: asserted from the
      # evaluated configuration, where the claim is exact.
      assert ${builtins.toJSON nodes.machine.networking.firewall.allowedTCPPorts} == [], "a module opened a firewall port by default"
    '';
}

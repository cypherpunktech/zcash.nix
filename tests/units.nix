# One machine with every service module enabled, asserting the properties that
# must hold for all of them.
#
# Why this exists alongside the per-service tests: zebra and lightwalletd can
# be driven to a healthy state in a VM, but zaino, zinder and zallet cannot
# without a synced chain or an initialised wallet. Writing "wait_for_unit" tests
# for those would produce tests that fail for reasons unrelated to the module.
#
# What CAN be asserted for all of them, and is exactly where module bugs live:
# that the units are well-formed, that nothing runs as root, and that the
# hardening in modules/hardening.nix actually reached every service. Those are
# checked here mechanically, so a module added later is covered the moment
# someone adds it to this list -- and the deviations are asserted too, so
# zinder's static user cannot silently spread to the others.
self: _: {
  name = "zcash-units";

  nodes.machine = {
    imports = [ self.nixosModules.default ];

    services.zcash = {
      zebra.enable = true;
      zakura.enable = true;
      zaino.enable = true;
      zinder.enable = true;
      lightwalletd = {
        enable = true;
        insecureNoTLS = true;
        rpcUser = "test";
        rpcPassword = "test";
      };
      zallet = {
        enable = true;
        acceptBetaRisk = true;
      };
      zpay.enable = true;
      ztreamer.enable = true;
      lightwalletd-rs = {
        enable = true;
        insecureNoTLS = true;
      };
    };

    virtualisation.memorySize = 3072;
  };

  testScript = ''
    services = [
        "zebra", "zakura", "zaino", "lightwalletd", "zallet", "zpay", "ztreamer",
        "lightwalletd-rs", "zinder-ingest", "zinder-projector", "zinder-query",
        "zinder-compat-lightwalletd",
    ]

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

    # The documented deviation, asserted so it stays a deviation. Zinder's four
    # runtimes share a storage tree and therefore share one static user;
    # everything else gets its own DynamicUser identity. If a future edit
    # flipped zebra to a static user, or zinder to DynamicUser (which would
    # break its shared state), this catches it.
    for s in ["zebra", "zakura", "zaino", "lightwalletd", "zallet", "zpay", "ztreamer", "lightwalletd-rs"]:
        out = machine.succeed(f"systemctl show {s}.service -p DynamicUser")
        assert "DynamicUser=yes" in out, f"{s} should use DynamicUser: {out}"

    for s in ["zinder-ingest", "zinder-projector", "zinder-query", "zinder-compat-lightwalletd"]:
        out = machine.succeed(f"systemctl show {s}.service -p DynamicUser -p User")
        assert "DynamicUser=no" in out, f"{s} must not use DynamicUser (shared state): {out}"
        assert "User=zinder" in out, f"{s} should run as the shared zinder user: {out}"
  '';
}

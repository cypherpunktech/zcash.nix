# tests/lightwalletd.nix for the Rust implementation: the same pairing with a
# Zebra node, the same credential and TLS files, through the same shared
# module. The differences are the ones the module declares -- it starts
# without credentials, so zcashConfPath here proves the file is read rather
# than needed; no log redirect -- and one that is behaviour rather than
# configuration: lightwalletd-rs checks its backend at startup, so a green
# unit here means it reached the node.
_self:
{ pkgs, ... }:
let
  certs = import (pkgs.path + "/nixos/tests/common/acme/server/snakeoil-certs.nix");
in
{
  name = "zcash-lightwalletd-rs";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ./fixtures/credentials.nix ];

      services.zcash.zebra.regtest.enable = true;

      services.zcash.lightwalletd-rs.main = {
        enable = true;
        rpcPort = 18232;
        zcashConfPath = "/var/lib/test-secrets/zcash.conf";
        tls.certFile = "/var/lib/test-secrets/tls.crt";
        tls.keyFile = "/var/lib/test-secrets/tls.key";
      };

      environment.systemPackages = [ pkgs.openssl ];
      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.wait_for_unit("zebra-regtest.service")
    machine.wait_for_unit("lightwalletd-rs-main.service")
    machine.wait_until_succeeds("systemctl is-active --quiet lightwalletd-rs-main.service", timeout=60)
    machine.wait_for_open_port(9067)

    with subtest("secrets reach the unit as credentials, and nowhere else"):
        unit = machine.succeed("systemctl cat lightwalletd-rs-main.service")
        for line in unit.splitlines():
            if "test-secrets" in line:
                assert line.startswith("LoadCredential="), f"secret path outside LoadCredential: {line}"

    with subtest("serves TLS with the configured certificate"):
        out = machine.succeed(
            "openssl s_client -connect ${certs.domain}:9067 -servername ${certs.domain} </dev/null 2>&1"
        )
        assert "Verify return code: 0 (ok)" in out, out

    with subtest("started once: it reached the node on the first try"):
        restarts = machine.succeed("systemctl show -p NRestarts --value lightwalletd-rs-main.service").strip()
        assert restarts == "0", f"lightwalletd-rs-main restarted {restarts} times"

    machine.succeed("test -d /var/lib/lightwalletd-rs-main")
    machine.succeed("journalctl -u lightwalletd-rs-main.service --no-pager | head -c 1 | grep -q .")
  '';
}

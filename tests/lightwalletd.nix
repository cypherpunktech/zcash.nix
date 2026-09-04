# Boots a machine with lightwalletd pointed at a Zebra node on the same host.
#
# The pairing is the point: lightwalletd is useless alone, and the failure this
# catches -- a backend it cannot reach, or credentials it cannot read -- only
# appears when both units exist together. Credentials and TLS key are real
# files handed over as systemd credentials (tests/fixtures/credentials.nix): the
# module's secret path is the one a hardened unit breaks on, so it is the one
# the test walks. The node is tests/fixtures/regtest.nix.
self:
{ pkgs, ... }:
let
  certs = import (pkgs.path + "/nixos/tests/common/acme/server/snakeoil-certs.nix");
in
{
  name = "zcash-lightwalletd";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ./fixtures/credentials.nix ];

      services.zcash.zebra.regtest.enable = true;

      services.zcash.lightwalletd.main = {
        enable = true;
        rpcPort = 18232;
        zcashConfPath = "/var/lib/test-secrets/zcash.conf";
        tls.certFile = "/var/lib/test-secrets/tls.crt";
        tls.keyFile = "/var/lib/test-secrets/tls.key";
        extraArgs = [ "--no-backend-check" ];
      };

      # The CompactTxStreamer schema, from the protocol's reference source.
      environment.systemPackages = [ pkgs.grpcurl ];
      environment.etc."walletrpc".source = "${
        self.packages.${pkgs.stdenv.hostPlatform.system}.lightwalletd.src
      }/walletrpc";

      virtualisation.memorySize = 2048;
    };

  testScript = ''
    machine.wait_for_unit("zebra-regtest.service")
    machine.wait_for_unit("lightwalletd-main.service")
    machine.wait_until_succeeds("systemctl is-active --quiet lightwalletd-main.service", timeout=60)

    with subtest("secrets reach the unit as credentials, and nowhere else"):
        unit = machine.succeed("systemctl cat lightwalletd-main.service")
        assert "rpcpassword" not in unit, unit
        for line in unit.splitlines():
            if "test-secrets" in line:
                assert line.startswith("LoadCredential="), f"secret path outside LoadCredential: {line}"
        owner, mode = machine.succeed(
            "stat -c '%U %a' /run/credentials/lightwalletd-main.service/tls-key"
        ).split()
        assert owner != "root" and mode == "400", f"credential is {owner} {mode}, expected the service's user and 400"

    with subtest("serves wallets over TLS with the configured certificate"):
        out = machine.succeed(
            "grpcurl -import-path /etc/walletrpc -proto service.proto "
            "${certs.domain}:9067 cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo"
        )
        assert '"version"' in out, out
        machine.fail("grpcurl -plaintext -import-path /etc/walletrpc -proto service.proto "
                     "${certs.domain}:9067 cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo")

    with subtest("started once: no crash behind the start"):
        restarts = machine.succeed("systemctl show -p NRestarts --value lightwalletd-main.service").strip()
        assert restarts == "0", f"lightwalletd-main restarted {restarts} times"

    machine.succeed("test -d /var/lib/lightwalletd-main")

    # Logs reach journald rather than a ./server.log the service cannot write
    # under ProtectSystem=strict. A silent unit is a broken one.
    machine.succeed("journalctl -u lightwalletd-main.service --no-pager | head -c 1 | grep -q .")
  '';
}

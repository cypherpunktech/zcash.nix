# The deployment topology: a node on one machine, lightwalletd on another,
# a wallet on a third. Every other test binds everything to loopback, which
# is where the modules' defaults point -- and so nothing else exercises an
# address the network can reach, the firewall option, or the hardening's
# effect on a listener other machines connect to.
#
# What it proves: openFirewall opens the gRPC port and nothing else (the
# metrics listener is deliberately bound to all interfaces here and must stay
# unreachable), TLS is served on the wire to a stranger, and a node with an
# RPC on the network -- cookie auth off, since lightwalletd has no other way
# to authenticate and zebra has no other mode -- is what the module warns
# about and still allows. Addresses come from the test framework, not from
# guesses.
self:
{ pkgs, ... }:
let
  certs = import "${pkgs.path}/nixos/tests/common/acme/server/snakeoil-certs.nix";
in
{
  name = "zcash-lightwalletd-remote";

  nodes = {
    node = {
      services.zcash.zebra.regtest = {
        enable = true;
        settings.rpc.listen_addr = "0.0.0.0:18232";
      };
      networking.firewall.allowedTCPPorts = [ 18232 ];
      virtualisation.memorySize = 2048;
    };

    wallet =
      { nodes, ... }:
      {
        imports = [ ./fixtures/credentials.nix ];
        services.zcash.lightwalletd.main = {
          enable = true;
          rpcHost = nodes.node.networking.primaryIPAddress;
          rpcPort = 18232;
          grpcBindAddr = "0.0.0.0:9067";
          httpBindAddr = "0.0.0.0:9068";
          openFirewall = true;
          zcashConfPath = "/var/lib/test-secrets/zcash.conf";
          tls.certFile = "/var/lib/test-secrets/tls.crt";
          tls.keyFile = "/var/lib/test-secrets/tls.key";
        };
      };

    client =
      { nodes, pkgs, ... }:
      {
        # The certificate names acme.test; to this machine that is the wallet host.
        networking.extraHosts = "${nodes.wallet.networking.primaryIPAddress} ${certs.domain}";
        environment.systemPackages = [ pkgs.grpcurl ];
        environment.etc."walletrpc".source = "${
          self.packages.${pkgs.stdenv.hostPlatform.system}.lightwalletd.src
        }/walletrpc";
      };
  };

  testScript = ''
    start_all()
    node.wait_for_unit("zebra-regtest.service")
    wallet.wait_for_unit("lightwalletd-main.service")
    client.wait_for_unit("multi-user.target")

    with subtest("a wallet reaches lightwalletd over TLS, and it reached the node"):
        out = client.wait_until_succeeds(
            "grpcurl -cacert ${certs.ca.cert} -import-path /etc/walletrpc -proto service.proto "
            "${certs.domain}:9067 cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLightdInfo",
            timeout=120,
        )
        assert '"chainName"' in out, out

    with subtest("openFirewall opened the gRPC port and nothing else"):
        client.fail("curl -s --max-time 5 http://${certs.domain}:9068/")

    with subtest("started once: no crash behind the start"):
        restarts = wallet.succeed("systemctl show -p NRestarts --value lightwalletd-main.service").strip()
        assert restarts == "0", f"lightwalletd-main restarted {restarts} times"
  '';
}

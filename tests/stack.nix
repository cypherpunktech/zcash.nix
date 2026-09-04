# The stack: a node that makes blocks, an indexer that indexes them, and a
# wallet-facing query that returns the right answer.
#
# Every other test here proves a service STARTS. This one proves an indexer
# INDEXES, which needs a chain that grows, which needs no network: Zebra's
# Regtest with its internal miner (a build feature this repository turns on,
# see packages/zebra) produces a block every few seconds from nothing. zaino
# follows it over Zebra's indexer gRPC and JSON-RPC and serves
# CompactTxStreamer; the assertion is the one a light wallet would make,
# GetLatestBlock, and the answer must be a height above zero -- blocks that
# were mined here, indexed here, and served here, inside one VM.
#
# Run on a maintainer's Mac before it was a test: zebra mined 15 blocks in
# 75 seconds, zaino reported height 23 two minutes in. The timeouts below are
# that, with room.
self:
{ pkgs, ... }:
{
  name = "zcash-stack";

  nodes.machine =
    { ... }:
    {
      imports = [
        self.nixosModules.zebra
        self.nixosModules.zaino
      ];

      services.zcash.zebra.regtest = {
        enable = true;
        settings = {
          network = {
            network = "Regtest";
            initial_mainnet_peers = [ ];
            initial_testnet_peers = [ ];
            cache_dir = false;
            testnet_parameters.activation_heights.NU5 = 1;
          };
          state.ephemeral = true;
          # Cookie auth stays ON, as it would in production: zaino reads the
          # cookie through `node` below, and the test reads it as root.
          rpc = {
            listen_addr = "127.0.0.1:18232";
            indexer_listen_addr = "127.0.0.1:18230";
          };
          mining = {
            # Zebra's own documented Regtest address; the subsidy goes nowhere
            # anyone can spend, which is the point of a test chain.
            miner_address = "t27eWDgjFYJGVXmzrXeVjnb5J3uXDM9xH9v";
            internal_miner = true;
          };
        };
      };

      services.zcash.zaino.regtest = {
        enable = true;
        node = "zebra-regtest";
        settings = {
          backend = "rpc";
          network = "Regtest";
          grpc_settings.listen_address = "127.0.0.1:8137";
          validator_settings = {
            validator_grpc_listen_address = "127.0.0.1:18230";
            validator_jsonrpc_listen_address = "127.0.0.1:18232";
          };
        };
      };

      # zaino serves no gRPC reflection; the CompactTxStreamer schema comes
      # from lightwalletd's source, which is the protocol's reference.
      environment.systemPackages = [
        pkgs.grpcurl
        pkgs.jq
      ];
      environment.etc."walletrpc".source = "${
        self.packages.${pkgs.stdenv.hostPlatform.system}.lightwalletd.src
      }/walletrpc";

      virtualisation.memorySize = 3072;
    };

  testScript = ''
    machine.wait_for_unit("zebra-regtest.service")
    machine.wait_for_open_port(18232)
    machine.wait_for_open_port(18230)

    # The chain grows on its own. The cookie is `user:password` on one line,
    # which is what curl -u takes.
    machine.wait_until_succeeds(
        "curl -s -u \"$(cat /var/lib/zebra-regtest/.cookie)\" -H 'Content-Type: application/json' "
        "--data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getblockchaininfo\",\"params\":[]}' "
        "http://127.0.0.1:18232 | jq -e '.result.blocks > 0'",
        timeout=180,
    )

    machine.wait_for_unit("zaino-regtest.service")
    machine.wait_for_open_port(8137, timeout=180)

    # The indexer has indexed it: a wallet's first question, answered with a
    # height it could only know by following the chain.
    machine.wait_until_succeeds(
        "grpcurl -plaintext -import-path /etc/walletrpc -proto service.proto "
        "127.0.0.1:8137 cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock "
        "| jq -e '(.height | tonumber) > 0'",
        timeout=240,
    )

    # zaino started once. Ordered after a node whose "started" means "RPC
    # answers", it never ran against a node that was not there. Without that
    # ordering it crash-looped until zebra bound RPC, wait_for_unit passed
    # after any number of restarts, and this test could not tell.
    restarts = machine.succeed("systemctl show -p NRestarts --value zaino-regtest.service").strip()
    assert restarts == "0", f"zaino-regtest restarted {restarts} times before zebra was ready"
  '';
}

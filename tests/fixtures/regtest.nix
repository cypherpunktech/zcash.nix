# The node every test wants: a Regtest zebra, zakura or ztreamer with RPC on
# loopback and no way to reach the network, defined once as defaults. A test
# sets `enable = true` and whatever is specific to it; a disabled instance
# produces no unit, so carrying these defaults into every machine costs
# nothing.
#
# THE EMPTY SEED LISTS ARE LOAD-BEARING. A NixOS test VM has no network, and
# zebrad blocks startup resolving seed peers: it loops "empty peer list after
# DNS resolution, retrying after 5 seconds" forever and never binds its RPC
# port, so a test times out while the daemon looks perfectly healthy in the
# journal. Regtest does not save you from this on its own -- Zebra treats it
# as a testnet variant and still resolves the testnet seeds. Verified by
# running zebrad locally with exactly this config: RPC answered getinfo on
# the first attempt. Zakura is a fork of the same code; ztreamer embeds it.
#
# Cookie auth is off because these RPCs are driven by curl from the test, and
# by lightwalletd, which has no cookie support (zebra has no other
# authentication). tests/stack.nix turns it back on to prove the production
# shape, where zaino reads the cookie as a credential.
{ lib, ... }:
let
  node = {
    network = {
      network = "Regtest";
      initial_mainnet_peers = [ ];
      initial_testnet_peers = [ ];
      cache_dir = false;
    };
    rpc.listen_addr = "127.0.0.1:18232";
    rpc.enable_cookie_auth = false;
  };
  defaults = settings: lib.mapAttrsRecursive (_: lib.mkDefault) settings;
in
{
  services.zcash = {
    zebra.regtest.settings = defaults (node // { state.ephemeral = true; });
    zakura.regtest.settings = defaults (node // { state.ephemeral = true; });
    ztreamer.regtest.settings = defaults node;
  };
}

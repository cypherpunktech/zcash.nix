# services.zcash.zakura.<instance> — run Zakura as a hardened systemd service.
#
# Zakura is a Zebra fork and presents the same surface to a unit: `zakurad -c
# zakura.toml start`, a TOML schema with the same [network]/[state]/[rpc]
# sections, and the same chain-state directory problem. So it shares
# ../node.nix rather than restating it.
#
# Where it differs is its own P2P layer: an iroh endpoint with a long-term
# identity key, which by default lives in ~/.zakura (ProtectHome hides it)
# and whose network monitor opens a netlink socket (the shared address-family
# restriction kills it at startup, silently until tests/ztreamer.nix caught
# it in the embedded copy). Both are passed to the factory as what they are:
# a default and an allowance, not a second module.
self:
import ../node.nix {
  inherit self;
  name = "zakura";
  description = "Zakura, a Zcash full node built for scale";
  documentation = [ "https://github.com/zakura-core/zakura" ];
  defaultPeerPort = "[::]:8233";
  defaults = stateDir: {
    network.identity_dir = "${stateDir}/identity";
  };
  addressFamilies = [ "AF_NETLINK" ];
  # P2P v2 is QUIC, so UDP, on its own port. Open unless the stack is pinned
  # to legacy: an unset p2p_stack follows a per-network default that upstream
  # says will change between releases (mainnet: legacy until v2 is proven),
  # and a port with nothing bound to it costs nothing.
  udpPeerAddrs =
    settings:
    if (settings.network.p2p_stack or "default") == "legacy" then
      [ ]
    else
      [ (settings.network.zakura.listen_addr or "0.0.0.0:8234") ];
  snapshotManifests = {
    mainnet = {
      pruned = "https://zakura.valargroup.dev/mainnet-pruned/snapshots.json";
      archive = "https://zakura.valargroup.dev/mainnet/snapshots.json";
    };
    testnet.pruned = "https://zakura.valargroup.dev/testnet-pruned/snapshots.json";
  };
}

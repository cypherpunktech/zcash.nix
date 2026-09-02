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
}

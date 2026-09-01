# services.zcash.zebra — run Zebra as a hardened systemd service.
#
# The structure lives in ../node.nix, shared with Zakura, which is a Zebra fork
# and identical in every way a systemd unit can see.
self:
import ../node.nix {
  inherit self;
  name = "zebra";
  description = "Zebra, the Zcash Foundation's Zcash node";
  documentation = [ "https://zebra.zfnd.org/" ];
  defaultPeerPort = "[::]:8233";
}

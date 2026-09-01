# services.zcash.zakura — run Zakura as a hardened systemd service.
#
# Zakura is a Zebra fork and presents the same surface to a unit: `zakurad -c
# zakura.toml start`, a TOML schema with the same [network]/[state]/[rpc]
# sections, and the same chain-state directory problem. So it shares
# ../node.nix rather than restating it.
#
# It does carry sections Zebra does not -- [network.zakura] and
# [zcashd_compat] -- but `settings` is freeform, so those need no code here.
# That is the payoff of not enumerating a schema: a fork's extra sections cost
# nothing.
self:
import ../node.nix {
  inherit self;
  name = "zakura";
  description = "Zakura, a Zcash full node built for scale";
  documentation = [ "https://github.com/zakura-core/zakura" ];
  defaultPeerPort = "[::]:8233";
}

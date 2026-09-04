# services.zcash.lightwalletd-rs — the Rust lightwalletd, as a systemd service.
#
# Shares ../lightwallet.nix with the Go lightwalletd: same options, same unit.
# It logs to stderr by itself, so nothing needs redirecting, and it starts
# without credentials (it simply calls the node's RPC unauthenticated, which
# works against a node with cookie auth off), so that assertion is not applied.
self:
import ../lightwallet.nix {
  inherit self;
  name = "lightwalletd-rs";
  description = "lightwalletd-rs, the Rust Zcash light-client backend";
  documentation = [ "https://github.com/jpgonzalezra/lightwalletd-rs" ];
  flags = {
    grpcBind = "--grpc-bind";
    httpBind = "--metrics-bind";
    rpcHost = "--rpc-host";
    rpcPort = "--rpc-port";
    zcashConf = "--zcash-conf";
  };
  requiresCredentials = false;
}

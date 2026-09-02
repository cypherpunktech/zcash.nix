# services.zcash.lightwalletd — the Go lightwalletd, as a systemd service.
#
# Shares ../lightwallet.nix with lightwalletd-rs. The Go flag spellings, the
# log redirect (its default is ./server.log, which ProtectSystem=strict makes
# unwritable; journald is where a service's logs belong), and the fact that it
# refuses to start without credentials are what is specific to it.
self:
import ../lightwallet.nix {
  inherit self;
  name = "lightwalletd";
  description = "lightwalletd, the Zcash light-client backend";
  documentation = [ "https://github.com/zcash/lightwalletd" ];
  flags = {
    grpcBind = "--grpc-bind-addr";
    httpBind = "--http-bind-addr";
    rpcHost = "--rpchost";
    rpcPort = "--rpcport";
    zcashConf = "--zcash-conf-path";
    rpcUser = "--rpcuser";
    rpcPassword = "--rpcpassword";
  };
  extraFlags = [
    "--log-file"
    "/dev/stdout"
  ];
  requiresCredentials = true;
}

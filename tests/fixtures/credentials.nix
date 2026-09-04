# Throwaway key material for the VM tests, installed the way an operator
# installs the real thing: root-owned files outside the Nix store, named to
# the services through their *File options and handed over by systemd as
# credentials. That path is where a hardened unit actually fails -- a
# DynamicUser reading a root-owned key under ProtectSystem=strict -- so the
# tests must walk it rather than set insecureNoTLS and look away.
#
# The certificates are nixpkgs' own snakeoil set for `acme.test`: nothing
# private is committed to this repository and no test generates a key. The
# zcash.conf credentials are arbitrary; the test nodes run with cookie auth
# off, and the Go lightwalletd needs a file to read before it will start.
#
# This directory holds fixtures, not tests: flake.nix turns every tests/*.nix
# into a VM test, and a subdirectory is what its filter skips.
{ pkgs, ... }:
let
  certs = import "${pkgs.path}/nixos/tests/common/acme/server/snakeoil-certs.nix";
in
{
  system.activationScripts.testSecrets.text = ''
    install -Dm600 ${certs.${certs.domain}.key} /var/lib/test-secrets/tls.key
    install -Dm644 ${certs.${certs.domain}.cert} /var/lib/test-secrets/tls.crt
    install -Dm600 /dev/null /var/lib/test-secrets/zcash.conf
    printf 'rpcuser=test\nrpcpassword=test\n' > /var/lib/test-secrets/zcash.conf
  '';

  # The certificate names acme.test; that is this machine, and its CA is one
  # the machine trusts, so a client here verifies the way a wallet would.
  networking.extraHosts = "127.0.0.1 ${certs.domain}";
  security.pki.certificateFiles = [ certs.ca.cert ];
}

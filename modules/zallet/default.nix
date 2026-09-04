# services.zcash.zallet — the RPC wallet, as a systemd service.
#
# THIS MODULE IS DELIBERATELY HARDER TO TURN ON THAN THE OTHERS.
#
# Zallet is a wallet. It holds spending keys, and upstream's own first line of
# `--help` is "A prototype wallet. Don't rely on this for privacy or with
# significant funds yet!". Upstream also refuses to generate an example config
# without a flag literally named
# `--this-is-beta-code-and-you-will-need-to-recreate-the-example-later`.
#
# A packaging repository that wrapped that in a friendly one-line `enable =
# true` would be laundering a warning the authors went out of their way to make
# unmissable. So this module mirrors their gate: `acceptBetaRisk` must be set
# deliberately, exactly as lightwalletd's `insecureNoTLS` must be.
#
# It also cannot initialise a wallet for you, and does not pretend to. The
# encryption identity, the mnemonic and its backup confirmation are
# irreversible, key-bearing operations that must be run by a human with
# somewhere safe to put the result:
#
#   zallet -d /var/lib/zallet generate-encryption-identity
#   zallet -d /var/lib/zallet init-wallet-encryption
#   zallet -d /var/lib/zallet generate-mnemonic
#   zallet -d /var/lib/zallet confirm-backup
#
# A module that ran those on first boot would generate keys nobody backed up
# and call it convenience.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zcash.zallet;
  service = import ../service.nix {
    inherit lib self pkgs;
    name = "zallet";
    description = "Zallet, the Zcash RPC wallet (BETA — see the warnings in this module)";
  };
  stateDir = "/var/lib/zallet";
in
{
  # Single-instance, unlike the nodes and indexers: one wallet per machine.
  # `user` matters here more than anywhere: zallet's backend reads the node's
  # state database directly, so it must run as the same user as that node.
  options.services.zcash.zallet = service.options // {

    acceptBetaRisk = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Acknowledge that Zallet is beta software holding spending keys, and
        that upstream advises against using it for significant funds.

        Required. This module will not build without it, mirroring upstream's
        own refusal to proceed unprompted.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = stateDir;
      description = ''
        Wallet data directory. Must already contain an initialised wallet —
        see the commands in the header of this module. The service starts a
        wallet; it does not create one.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments passed before the `start` subcommand.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acceptBetaRisk;
        message = ''
          services.zcash.zallet.enable is set, but acceptBetaRisk is not.

          Zallet is beta software that holds spending keys; its own authors
          advise against significant funds. Set
          services.zcash.zallet.acceptBetaRisk = true to confirm you have read
          that, and make sure the wallet at ${cfg.dataDir} is already
          initialised — this service starts a wallet, it does not create one.
        '';
      }
    ];

    systemd.services.zallet = {
      description = "Zallet Zcash RPC wallet";
      documentation = [ "https://github.com/zcash/zallet" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = lib.unique [
        stateDir
        cfg.dataDir
      ];

      # The 0700 state directory service.identity applies is about tidiness
      # everywhere else. Here it is about spending keys, and the wallet's own
      # encryption is not a reason to relax it.
      serviceConfig = service.identity cfg "zallet" // {
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "--datadir"
            cfg.dataDir
          ]
          ++ cfg.extraArgs
          ++ [ "start" ]
        );
      };
    };

    users = service.users { inherit cfg; };
  };
}

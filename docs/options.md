## services\.zcash\.binaryCache\.enable

Whether to enable cypherpunktech\.cachix\.org as a substituter\. Using it means trusting the CI
that pushes to it and the maintainers who hold its token; SECURITY\.md says
what that trust covers
\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/binary-cache/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/binary-cache/default.nix)



## services\.zcash\.lightwalletd



lightwalletd, the Zcash light-client backend: one entry per instance, each its own unit and block cache\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.enable



Whether to enable lightwalletd, the Zcash light-client backend\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.package



The lightwalletd package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.lightwalletd
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.grpcBindAddr



Address to serve gRPC on\. Loopback by default: exposing this is a deliberate act\.



*Type:*
string



*Default:*

```nix
"127.0.0.1:9067"
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.httpBindAddr



Address to serve HTTP (metrics) on\.



*Type:*
string



*Default:*

```nix
"127.0.0.1:9068"
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.insecureNoTLS



Run without TLS, passing ` --no-tls-very-insecure `\.

Wallets connecting to this server send their viewing keys’ query
patterns over the wire\. Without TLS those are readable by anything
on the path, which for a privacy coin defeats a large part of the
point\. Only reasonable behind a terminating reverse proxy on the
same host, or in a test\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.openFirewall



Open the gRPC port in the firewall\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.rpcHost



Host of the backing zebrad/zakura node’s RPC\.



*Type:*
string



*Default:*

```nix
"127.0.0.1"
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.rpcPort



Port of the backing node’s RPC\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
8232
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.tls\.certFile



TLS certificate\. Required unless ` insecureNoTLS ` is set\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.tls\.keyFile



TLS key\. Required unless ` insecureNoTLS ` is set\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd\.\<name>\.zcashConfPath



A ` zcash.conf ` with ` rpcuser= ` and ` rpcpassword= ` lines for the
backing node’s RPC\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/lightwalletd/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd/default.nix)



## services\.zcash\.lightwalletd-rs



lightwalletd-rs, the Rust Zcash light-client backend: one entry per instance, each its own unit and block cache\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.enable



Whether to enable lightwalletd-rs, the Rust Zcash light-client backend\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.package



The lightwalletd-rs package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.lightwalletd-rs
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.grpcBindAddr



Address to serve gRPC on\. Loopback by default: exposing this is a deliberate act\.



*Type:*
string



*Default:*

```nix
"127.0.0.1:9067"
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.httpBindAddr



Address to serve HTTP (metrics) on\.



*Type:*
string



*Default:*

```nix
"127.0.0.1:9068"
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.insecureNoTLS



Run without TLS, passing ` --no-tls-very-insecure `\.

Wallets connecting to this server send their viewing keys’ query
patterns over the wire\. Without TLS those are readable by anything
on the path, which for a privacy coin defeats a large part of the
point\. Only reasonable behind a terminating reverse proxy on the
same host, or in a test\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.openFirewall



Open the gRPC port in the firewall\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.rpcHost



Host of the backing zebrad/zakura node’s RPC\.



*Type:*
string



*Default:*

```nix
"127.0.0.1"
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.rpcPort



Port of the backing node’s RPC\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
8232
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.tls\.certFile



TLS certificate\. Required unless ` insecureNoTLS ` is set\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.tls\.keyFile



TLS key\. Required unless ` insecureNoTLS ` is set\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.lightwalletd-rs\.\<name>\.zcashConfPath



A ` zcash.conf ` with ` rpcuser= ` and ` rpcpassword= ` lines for the
backing node’s RPC\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/lightwalletd-rs/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/lightwalletd-rs/default.nix)



## services\.zcash\.zaino



Zaino indexer instances, each its own unit and state directory\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.enable



Whether to enable Zaino, an indexer for the Zcash blockchain\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.package



The zaino package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.zaino
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.node



Unit name of the zebra or zakura instance on this host that this
indexer follows, ` <node>-<instance> `\. This unit then starts after
the node’s RPC answers, restarts when the node does, and
authenticates to its RPC with the node’s cookie, which systemd
hands over as a credential so the two keep separate users\. The
node’s addresses still come from ` settings.validator_settings `\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"zebra-mainnet"
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.openFirewall



Open the gRPC port in the firewall\.

Off by default\. An indexer answers questions about which
transactions concern which viewing keys; who can ask it is a
privacy decision, not a convenience one\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.settings



Contents of ` zainod.toml `, as a Nix attribute set\. Generate a
reference with ` zainod generate-config -o /dev/stdout `\.

` storage.database.path ` defaults to the instance’s state directory\.
` metrics_endpoint = "127.0.0.1:9998" ` serves Prometheus metrics\.



*Type:*
TOML value



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  grpc_settings.listen_address = "127.0.0.1:8137";
  validator_settings.validator_jsonrpc_listen_address = "127.0.0.1:8232";
}

```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zaino\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/zaino/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zaino/default.nix)



## services\.zcash\.zakura



Zakura, a Zcash full node built for scale: one entry per instance, each its own unit and state directory\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  mainnet.enable = true;
  testnet = {
    enable = true;
    settings.network.network = "Testnet";
  };
}

```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zakura\.\<name>\.enable



Whether to enable Zakura, a Zcash full node built for scale\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zakura\.\<name>\.package



The zakura package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.zakura
```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zakura\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zakura\.\<name>\.openFirewall



Open the peer-to-peer port in the firewall\.

Deliberately covers only the P2P listener\. The RPC port is never
opened: it is an administrative interface, and a node exposing it
to the internet is a node somebody else is driving\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zakura\.\<name>\.settings



Contents of ` zakura.toml `, as a Nix attribute set\.
` state.cache_dir ` defaults to the instance’s state directory and
should normally be left alone\.



*Type:*
TOML value



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  network.network = "Testnet";
  rpc.listen_addr = "127.0.0.1:18232";
  metrics.endpoint_addr = "127.0.0.1:9999"; # Prometheus, on loopback
}

```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zakura\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/zakura/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zakura/default.nix)



## services\.zcash\.zallet\.enable



Whether to enable Zallet, the Zcash RPC wallet (BETA — see the warnings in this module)\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/zallet/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zallet/default.nix)



## services\.zcash\.zallet\.package



The zallet package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.zallet
```

*Declared by:*
 - [modules/zallet/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zallet/default.nix)



## services\.zcash\.zallet\.acceptBetaRisk



Acknowledge that Zallet is beta software holding spending keys, and
that upstream advises against using it for significant funds\.

Required\. This module will not build without it, mirroring upstream’s
own refusal to proceed unprompted\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/zallet/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zallet/default.nix)



## services\.zcash\.zallet\.dataDir



Wallet data directory\. Must already contain an initialised wallet —
see the commands in the header of this module\. The service starts a
wallet; it does not create one\.



*Type:*
string



*Default:*

```nix
"/var/lib/zallet"
```

*Declared by:*
 - [modules/zallet/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zallet/default.nix)



## services\.zcash\.zallet\.extraArgs



Extra arguments passed before the ` start ` subcommand\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/zallet/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zallet/default.nix)



## services\.zcash\.zallet\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/zallet/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zallet/default.nix)



## services\.zcash\.zebra



Zebra, the Zcash Foundation’s Zcash node: one entry per instance, each its own unit and state directory\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  mainnet.enable = true;
  testnet = {
    enable = true;
    settings.network.network = "Testnet";
  };
}

```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zebra\.\<name>\.enable



Whether to enable Zebra, the Zcash Foundation’s Zcash node\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zebra\.\<name>\.package



The zebra package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.zebra
```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zebra\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zebra\.\<name>\.openFirewall



Open the peer-to-peer port in the firewall\.

Deliberately covers only the P2P listener\. The RPC port is never
opened: it is an administrative interface, and a node exposing it
to the internet is a node somebody else is driving\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zebra\.\<name>\.settings



Contents of ` zebra.toml `, as a Nix attribute set\.
` state.cache_dir ` defaults to the instance’s state directory and
should normally be left alone\.



*Type:*
TOML value



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  network.network = "Testnet";
  rpc.listen_addr = "127.0.0.1:18232";
  metrics.endpoint_addr = "127.0.0.1:9999"; # Prometheus, on loopback
}

```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zebra\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/zebra/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zebra/default.nix)



## services\.zcash\.zinder



Zinder instances, each four runtimes sharing one state directory\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zinder\.\<name>\.enable



Whether to enable Zinder, the Zcash Foundation’s Zcash indexer\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zinder\.\<name>\.package



The zinder package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.zinder
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zinder\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zinder\.\<name>\.runtimes



Which of Zinder’s runtimes to run in this instance\.
The default is all four, which is upstream’s supported single-host
topology\. Splitting them across machines is possible but then the
shared storage tree becomes your problem, not this module’s\.



*Type:*
list of (one of “ingest”, “projector”, “query”, “compat-lightwalletd”)



*Default:*

```nix
[
  "ingest"
  "projector"
  "query"
  "compat-lightwalletd"
]
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zinder\.\<name>\.settings



Contents of the instance’s shared ` zinder.toml `, as a Nix attribute
set\. One file is passed to every runtime, because they must agree
about the storage layout they share; giving each its own would make
disagreement possible\.



*Type:*
TOML value



*Default:*

```nix
{ }
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zinder\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/zinder/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zinder/default.nix)



## services\.zcash\.zpay\.enable



Whether to enable zpay, a Zcash-native payments facilitator\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.zpay\.package



The zpay package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.zpay
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.zpay\.environment



` ZPAY_* ` variables passed to the runtime\. Run
` zpay-runtime --print-config ` to see what it resolved\.

These land in the unit file, readable by any local user\. Anything
secret belongs in ` environmentFile `, not here\.



*Type:*
attribute set of string



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  ZPAY_NETWORK = "main";
  ZPAY_SERVER__BIND_ADDR = "127.0.0.1:8080";
}
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.zpay\.environmentFile



A file of ` KEY=value ` lines, read by systemd at start\. This is where
credentials go\.

A path outside the Nix store, readable by root: systemd hands the
service its own private copy, so the file’s owner and mode do not
matter and it never touches the store or the unit file\.



*Type:*
null or string



*Default:*

```nix
null
```



*Example:*

```nix
"/run/secrets/lightwalletd-tls.key"
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.zpay\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.zpay\.openFirewall



Open the HTTP listener port in the firewall\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.zpay\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/zpay/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/zpay/default.nix)



## services\.zcash\.ztreamer



ztreamer instances, each its own unit, embedded node and state directory\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.enable



Whether to enable ztreamer, a CompactTxStreamer server with an embedded zakura node\.



*Type:*
boolean



*Default:*

```nix
false
```



*Example:*

```nix
true
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.package



The ztreamer package to use\.



*Type:*
package



*Default:*

```nix
zcash-nix.packages.${system}.ztreamer
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.extraArgs



Further command-line arguments, appended verbatim\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.grpcListen



Address the CompactTxStreamer gRPC server listens on\.



*Type:*
string



*Default:*

```nix
"127.0.0.1:9067"
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.metricsListen



Address the Prometheus metrics endpoint listens on\.



*Type:*
string



*Default:*

```nix
"127.0.0.1:9999"
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.openFirewall



Open the gRPC port in the firewall: this is the port wallets
connect to, and the one a public light-wallet server exposes\. Off
by default, as for every indexer here – who may ask which
transactions concern which keys is a privacy decision\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.openPeerPort



Open the embedded node’s peer-to-peer port so other Zcash nodes
can connect inbound\. Never the RPC port, and never the metrics
port\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.settings



Configuration of the embedded zakura node, as ` zakura.toml ` in Nix
form\. ` state.cache_dir ` defaults to the instance’s state directory
and should normally be left alone\.



*Type:*
TOML value



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  network.network = "Testnet";
  rpc.listen_addr = "127.0.0.1:18232";
}

```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



## services\.zcash\.ztreamer\.\<name>\.user



Run as this static system user (created if needed) instead of an
allocated ` DynamicUser `\. Set it when another service must read this
one’s state directory, and give both the same user; otherwise leave
it, an allocated identity is strictly more isolated\.



*Type:*
null or string



*Default:*

```nix
null
```

*Declared by:*
 - [modules/ztreamer/default\.nix](https://github.com/cypherpunktech/zcash.nix/blob/main/modules/ztreamer/default.nix)



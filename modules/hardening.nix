# systemd hardening shared by every service module here.
#
# It lives in one file because five copies would be five things free to drift,
# and because the interesting question about a hardening block is not "is it
# present" but "why is each line there" -- which is worth answering once.
#
# The shape assumes a network daemon that owns a state directory and needs
# nothing else: no privileges, no devices, no other users' files. Every service
# in this repository is that shape. A service that is not must override
# explicitly rather than quietly inherit something inappropriate.
{
  # Read/write only its own StateDirectory; the rest of the filesystem is
  # read-only, and /home, /root and /run/user are invisible. A chain-syncing
  # node has no business anywhere else.
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
  PrivateDevices = true;
  PrivateMounts = true;

  # No path from the service to more privilege than it starts with, and it
  # starts with none: an empty CapabilityBoundingSet means not even the
  # capabilities root would normally carry.
  NoNewPrivileges = true;
  CapabilityBoundingSet = "";
  AmbientCapabilities = "";
  RestrictSUIDSGID = true;

  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  ProtectControlGroups = true;
  ProtectClock = true;
  ProtectHostname = true;
  ProtectProc = "invisible";
  ProcSubset = "pid";

  # These daemons speak TCP over IPv4 and IPv6 and nothing else. Notably this
  # blocks AF_NETLINK and AF_PACKET, so a compromised process cannot enumerate
  # or reshape the host's networking.
  RestrictAddressFamilies = [
    "AF_INET"
    "AF_INET6"
  ];
  RestrictNamespaces = true;
  RestrictRealtime = true;
  LockPersonality = true;
  SystemCallArchitectures = "native";
  SystemCallFilter = [
    "@system-service"
    "~@privileged"
    "~@resources"
    "~@obsolete"
  ];

  # W^X. Safe for these specific programs because they are AOT-compiled Rust
  # and Go with no JIT; a service that gained a JIT would have to turn this off
  # deliberately, which is the right way to find out that it did.
  MemoryDenyWriteExecute = true;

  # State is private to the service. Chain state is not secret, but a wallet's
  # keys are, and the same default should cover both rather than depending on
  # someone noticing which is which.
  UMask = "0077";

  Restart = "on-failure";
  RestartSec = "10s";
}

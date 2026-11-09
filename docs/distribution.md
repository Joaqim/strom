# strom distribution over IPFS

strom moves game content over IPFS. Every game package carries the CIDs of
its data in `passthru.ipfsSources`, one publisher node assembles those CIDs
into a `/strom` directory and announces its current root under a stable
IPNS name, and consumers fetch content through HTTP gateways that range
from public infrastructure to a local mirror. This document describes the
architecture end to end: what the publisher does, what consumers of
increasing infrastructure weight look like, and how to run the common
private variant where one provider serves a LAN or VPN. The README's
"IPFS" section covers the adjacent mechanics -- adding a file to IPFS,
verifying retrievability, referencing a CID in a game package -- and is
not repeated here.

## The publisher role

Publishing assembles every game package's CID into one directory and
announces the directory's root under a stable name, so consumers can track
new content without knowing any individual CID in advance. The repo ships
one command for it:

```bash
nix run github:kraftwerk-gaming/strom#publish-ipns -- <ssh-target> [key-name]
```

`ssh-target` is anything ssh accepts: `user@host`, `host`, or
`ssh://user@host:port`. It addresses a machine running a kubo daemon; the
script (`scripts/publish-ipns.nix`) executes entirely on that remote host
over ssh and drives the daemon there through `sudo -u ipfs`. Two
environment overrides are forwarded to the remote: `STROM_IPFS_USER`
(default `ipfs`) and `STROM_IPFS_PATH` (default `/var/lib/ipfs`). The
optional `key-name` positional (default `strom`) selects the IPNS key.

A run does four things. First, key handling: if the IPNS key does not
exist, an ed25519 key is generated and the script prints the resulting
IPNS name together with the line consumers should set,
`services.strom-ipfs-mirror.ipnsName = "<name>";` -- this printed line is
the handoff between publisher and consumers. If the key exists, its
existing name is reused. Second, the MFS directory `/strom` is rebuilt
from scratch on every run (`ipfs files rm -r /strom`, then `mkdir`), and
each game's CIDs are copied in with `ipfs files cp`. Third, the new root
CID of the directory is computed. Fourth, the root is announced with
`ipfs name publish`, a DHT publish that takes roughly thirty seconds.

### Why publishing alone does not replicate content

The MFS root pin keeps the directory block alive and nothing else: it
references child content by CID without fetching or pinning it. A
publish run therefore moves no game data -- the child blocks live
wherever they were originally added and pinned. Content replication is a
separate, per-node act, and the repo ships `pin-ipfs` for it:

```bash
nix run github:kraftwerk-gaming/strom#pin-ipfs -- http://localhost:5001
nix run github:kraftwerk-gaming/strom#pin-ipfs -- http://localhost:5001 xenogears thief-gold
```

`pin-ipfs` (`scripts/pin-ipfs.nix`) calls `ipfs pin add` for every CID
listed in `passthru.ipfsSources` across all game packages, or the named
subset. Any node that runs it holds a full copy and serves it to the
swarm.

## Consumers

Consumption is a ladder ordered by infrastructure weight. Each tier
assumes the one above it and adds a piece: first a gateway to read
through, then a private one, then a node of your own.

### Tier 1: public gateways

The default. `fetchIpfs` (`lib/fetch-ipfs.nix`) races aria2c Range
requests across a set of public HTTP gateways (gateway.pinata.cloud,
nftstorage.link, ipfs.io, dweb.link, w3s.link), with a `fallbackUrl`
serving single files when every gateway fails. The nix fixed-output hash
gates integrity regardless of which gateway answered. This tier needs
zero infrastructure: builds work anywhere with internet access.

### Tier 2: a private gateway over LAN or VPN

The minimal operator scenario. One machine that already holds the
content -- the publisher node, or any node that has run `pin-ipfs` or the
mirror module below -- exposes its kubo HTTP gateway beyond loopback,
and build machines point at it. Consumers stay pure HTTP clients: no
consumer-side kubo, nothing to install or run.

Three deltas turn a loopback gateway into a LAN or VPN gateway.

The gateway bind. The mirror module binds the gateway to loopback
(`/ip4/127.0.0.1/tcp/<gatewayPort>`) through `mkDefault`, so an
operator-assigned `services.kubo.settings.Addresses.Gateway` always wins:

```nix
services.kubo.settings.Addresses.Gateway = "/ip4/<vpn-ip>/tcp/8330";
```

Prefer the VPN interface address over `/ip4/0.0.0.0/tcp/8330` wherever
the topology allows, so the gateway answers on exactly one network. On a
standalone kubo node that does not use the mirror module, the same
assignment applies directly.

The port. `gatewayPort` currently defaults to 8080, kubo's own
collision-prone port, kept only so a flake bump does not silently move
existing mirrors; while the effective gateway is the module-rendered
8080 address, every rebuild raises an evaluation warning, and a future
release will change the default. 8330 is the recommended value: it falls
inside the IANA-unassigned block 8323-8350, below the Linux ephemeral
port range (32768-60999 by default), and outside the common dev-server
ranges, so neither a registered service nor a kernel allocation can
claim it.

The firewall. The mirror module opens only the swarm port 4001 (TCP and
UDP); a gateway exposed beyond loopback additionally needs its port
opened, or the bind change silently does nothing off-loopback:

```nix
networking.firewall.allowedTCPPorts = [ 8330 ];
```

Consumers then prepend the gateway to their fetch path. `fetchIpfs`
reads `STROM_IPFS_GATEWAYS` (comma- or space-separated prefixes, no
trailing slash, no `/ipfs/`) ahead of the public gateway list, so the
private gateway is preferred when reachable and the public ones serve as
automatic failover:

```bash
STROM_IPFS_GATEWAYS=http://<vpn-ip>:8330 nix build .#xenogears
```

### Tier 3: the NixOS mirror module

Full replication. The module (`nixos/mirror-module.nix`, imported as
`strom.nixosModules.ipfs-mirror`) enables kubo with defaults tuned for a
mirror -- filestore enabled, `StorageMax` 100GB, resource manager
capped at 2GB, relays disabled, `Routing.Type = "dhtclient"` -- opens
the swarm ports, and creates a systemd timer that runs five minutes
after boot and then on the `interval` calendar (default hourly,
persistent across downtime). Each run resolves the IPNS name and
recursively pins everything underneath it, so the mirror picks up new
content automatically. The `ipnsName` default is the strom publisher's
name; a mirror of your own publication sets it to the name your
publisher printed (see the handoff above). The README's mirror-module
section shows the minimal configuration block.

### Tier 4: fully private operation

The routing caveat, stated plainly: `dhtclient` announces the node's
provider records to the public DHT, which is how peers find it by CID.
Exposing a gateway on a VPN is therefore not a private distribution --
the content remains discoverable and served through the public network.
Fully private operation means overriding routing, e.g.
`services.kubo.settings.Routing.Type = "none";` (the module's value is
`mkDefault`, so an operator assignment wins), combined with explicit
swarm peering between provider and consumers so retrieval happens only
over connections you dial: kubo's `Peering` configuration, or
`ipfs swarm connect` entries provisioned on each consumer. This is an
advanced tier, not the default path; every tier below it assumes public
DHT participation.

## Choosing a tier

If builds only sometimes run and the content is already published, stay
on public gateways. If builds run repeatedly on machines that share a
network with a holder of the content, expose that holder's gateway on
the VPN and set `STROM_IPFS_GATEWAYS` -- the cheapest large win, since
every fetch prefers the copy one hop away. If you want strom content to
survive independent of public gateway goodwill, run the mirror module.
Add tier 4 only when the distribution itself must stay off the public
network.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.strom-ipfs-mirror;
in
{
  options.services.strom-ipfs-mirror = {
    enable = lib.mkEnableOption "Mirror the strom IPFS content via IPNS";

    ipnsName = lib.mkOption {
      type = lib.types.str;
      default = "k51qzi5uqu5dgz69va1f3ha6b7hbdjgg3lz5qyq7kn4mx1vw6vxztc9445yr3a";
      description = ''
        IPNS name that the strom publisher writes to. The mirror periodically
        resolves it and recursively pins the resulting directory, so new
        content is picked up automatically.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "systemd OnCalendar expression for the periodic pin run.";
    };

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = ''
        TCP port for the kubo HTTP gateway. The module binds the gateway
        to loopback only (a mirror node serves content via the swarm port
        4001, not as a public gateway) and always renders the address
        explicitly via `mkDefault`, so an operator-assigned
        `services.kubo.settings.Addresses.Gateway` still wins.

        The current default is 8080, kubo's own port, kept only so that a
        flake bump does not silently move existing mirrors. It is
        deprecation-bearing: while the effective gateway is the
        module-rendered 8080 address, every rebuild raises an evaluation
        warning, and a future release will change the default.

        8330 is the recommended value: it falls inside the IANA-unassigned
        block 8323-8350 (no registered service claims it) and below the
        Linux ephemeral port range (32768-60999 by default), so neither a
        registered service nor a kernel allocation can claim the port --
        8080 is the canonical collision-prone HTTP-alt port where bind
        order decides who breaks. 8330 is also outside the common
        dev-server ranges (3000, 5000, 8000, 8080, 8888).

        When the service is enabled the module exports the gateway
        address as `STROM_IPFS_GATEWAYS` (mkDefault), so `fetchIpfs`
        prefers it over public gateways; set the variable yourself to
        override or extend the list. If you override
        `services.kubo.settings.Addresses.Gateway`, the exported
        address no longer matches your gateway, so you must also set
        `STROM_IPFS_GATEWAYS` yourself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.kubo = {
      enable = lib.mkDefault true;
      settings = {
        # Loopback gateway on an explicit, deprecation-warned port
        # (see services.strom-ipfs-mirror.gatewayPort).
        Addresses.Gateway = lib.mkDefault "/ip4/127.0.0.1/tcp/${toString cfg.gatewayPort}";
        Experimental.FilestoreEnabled = lib.mkDefault true;
        Datastore.StorageMax = lib.mkDefault "100GB";
        Swarm = {
          ConnMgr = {
            LowWater = lib.mkDefault 100;
            HighWater = lib.mkDefault 400;
            GracePeriod = lib.mkDefault "20s";
          };
          Transports.Network.TCP = lib.mkDefault true;
          Transports.Network.QUIC = lib.mkDefault true;
          ResourceMgr = {
            Enabled = lib.mkDefault true;
            MaxMemory = lib.mkDefault "2GB";
          };
          RelayClient.Enabled = lib.mkDefault false;
          RelayService.Enabled = lib.mkDefault false;
        };
        # dhtclient: announces our provider records (so peers can find us
        # by CID) but does not serve DHT routing queries for others.
        Routing.Type = lib.mkDefault "dhtclient";
      };
    };

    networking.firewall.allowedTCPPorts = [ 4001 ];
    networking.firewall.allowedUDPPorts = [ 4001 ]; # QUIC

    # The gateway this module just bound is the fastest source for
    # strom content on this machine: export it for fetchIpfs, which
    # prefixes injected gateways ahead of the public defaults
    # (lib/fetch-ipfs.nix). The export goes through `nix.envVars`
    # because fixed-output fetchers run under the nix-daemon, whose
    # environment is built from `nix.envVars`; the NixOS nix-daemon
    # module also flows these into session variables, so login
    # shells see them too. mkDefault so an operator's own list wins.
    nix.envVars.STROM_IPFS_GATEWAYS =
      lib.mkDefault "http://127.0.0.1:${toString cfg.gatewayPort}";

    systemd.services.strom-ipfs-pin = {
      description = "Pin /ipns/${cfg.ipnsName} (strom mirror)";
      after = [ "ipfs.service" ];
      wants = [ "ipfs.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "ipfs";
        Group = "ipfs";
      };
      script = ''
        ${config.services.kubo.package}/bin/ipfs pin add --progress --recursive /ipns/${cfg.ipnsName}
      '';
    };

    systemd.timers.strom-ipfs-pin = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };

    warnings =
      lib.mkIf
        (
          cfg.gatewayPort == 8080
          && config.services.kubo.settings.Addresses.Gateway == "/ip4/127.0.0.1/tcp/8080"
        )
        [
          "strom-ipfs-mirror: the gateway port is 8080, kubo's collision-prone default (bind-race with common HTTP-alt services). 8330 is the recommended port — set services.strom-ipfs-mirror.gatewayPort = 8330; to migrate. A future release will change the default."
        ];
  };
}

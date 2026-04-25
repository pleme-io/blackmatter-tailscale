# module/nixos/default.nix — NixOS Tailscale module
#
# Provides blackmatter.components.tailscale.* options that map to the
# underlying services.tailscale and networking.firewall configuration.
{ config, lib, ... }:
let
  cfg = config.blackmatter.components.tailscale;

  # Map role to useRoutingFeatures value
  routingFeatures =
    if cfg.role == "client" then "client"
    else "server";

  # Build extraUpFlags from structured options
  buildUpFlags = let
    hostnameFlag = lib.optional (cfg.hostname != null)
      "--hostname=${cfg.hostname}";

    routeFlags = lib.optional (cfg.advertisedRoutes != [])
      "--advertise-routes=${lib.concatStringsSep "," cfg.advertisedRoutes}";

    exitNodeFlag = lib.optional (cfg.role == "exit-node")
      "--advertise-exit-node";

    acceptRouteFlag = lib.optional cfg.acceptRoutes
      "--accept-routes";

    dnsFlag = [ "--accept-dns=${lib.boolToString cfg.acceptDns}" ];
  in
    hostnameFlag ++ routeFlags ++ exitNodeFlag ++ acceptRouteFlag ++ dnsFlag ++ cfg.extraFlags;
in
{
  options.blackmatter.components.tailscale = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the Tailscale daemon on this node — i.e. join the tailnet
        mesh. When enabled the node has a tailnet IP (100.x.y.z) and
        can be reached by peers; when disabled there is no tailscaled
        and no tailnet membership.

        This is INDEPENDENT of `acceptDns` below. A node can be on the
        mesh without consulting Tailscale's DNS resolver.
      '';
    };

    role = lib.mkOption {
      type = lib.types.enum [ "client" "subnet-router" "exit-node" ];
      default = "client";
      description = "Node role: client, subnet-router, or exit-node.";
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override Tailscale hostname (null = system hostname).";
    };

    advertisedRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Subnets to advertise (for subnet-router or exit-node roles).";
    };

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = cfg.role == "client";
      defaultText = lib.literalExpression ''true when role == "client"'';
      description = "Accept routes advertised by other Tailscale nodes.";
    };

    acceptDns = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Accept Tailscale MagicDNS configuration on this node — i.e. let
        Tailscale install its resolver (100.100.100.100) for the
        tailnet's MagicDNS suffix and add that suffix as a search
        domain. With this true:

          ssh rio          # bare name resolves via MagicDNS

        With this false the node is on the mesh but has no idea what
        the bare name `rio` refers to — only raw tailnet IPs work, or
        you must declare host entries elsewhere.

        On NixOS this passes `--accept-dns=true` to `tailscale up` and
        Tailscale rewrites systemd-resolved / resolv.conf scoped
        resolvers. Subnet routers typically leave this false because
        their loopback /etc/resolv.conf is what advertised peers see;
        client/dev nodes that want bare-name resolution flip this on.
      '';
    };

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to SOPS secret containing Tailscale auth key (null = interactive auth).";
    };

    firewall = {
      trustInterface = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add tailscale0 to trusted firewall interfaces.";
      };

      allowWireguard = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open UDP port 41641 for WireGuard traffic.";
      };
    };

    ssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Tailscale SSH server (allows `tailscale ssh` access without OpenSSH port forwarding).";
      };
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional flags passed to `tailscale up`.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = routingFeatures;
      extraUpFlags = buildUpFlags ++ lib.optional cfg.ssh.enable "--ssh";
    } // lib.optionalAttrs (cfg.authKeyFile != null) {
      authKeyFile = cfg.authKeyFile;
    };

    networking.firewall = lib.mkMerge [
      (lib.mkIf cfg.firewall.trustInterface {
        trustedInterfaces = [ "tailscale0" ];
      })
      (lib.mkIf cfg.firewall.allowWireguard {
        allowedUDPPorts = [ 41641 ];
      })
    ];
  };
}

# module/darwin/default.nix — macOS Tailscale module
#
# Provides the same blackmatter.components.tailscale.* option interface as
# the NixOS module. On Darwin, services.tailscale is limited — role,
# advertisedRoutes, and firewall options are accepted but enforced via
# `tailscale up` CLI post-rebuild, not declaratively.
{ config, lib, pkgs, ... }:
let
  cfg = config.blackmatter.components.tailscale;
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
      description = "Node role (documentation-only on Darwin — enforce via `tailscale up` CLI).";
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override Tailscale hostname (documentation-only on Darwin).";
    };

    advertisedRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Subnets to advertise (documentation-only on Darwin).";
    };

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = cfg.role == "client";
      defaultText = lib.literalExpression ''true when role == "client"'';
      description = "Accept routes from other nodes (documentation-only on Darwin).";
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

        On Darwin this maps to nix-darwin's
        `services.tailscale.overrideLocalDns`, which adds Tailscale's
        resolver to the macOS DNS chain. macOS scoped resolvers keep
        per-domain routing intact, so a WireGuard-pushed supplemental
        resolver (e.g. dnsmasq for `.quero.cloud`) continues to win
        for its own scope.
      '';
    };

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Not supported on Darwin (interactive auth via `sudo tailscale up`).";
    };

    firewall = {
      trustInterface = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "No-op on Darwin (Tailscale manages its own firewall rules).";
      };

      allowWireguard = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "No-op on Darwin (Tailscale manages its own firewall rules).";
      };
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional flags (documentation-only on Darwin).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      overrideLocalDns = cfg.acceptDns;
    };

    environment.systemPackages = [ pkgs.tailscale ];
  };
}

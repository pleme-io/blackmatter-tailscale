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
    enable = lib.mkEnableOption "Tailscale VPN";

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
      description = "Accept Tailscale MagicDNS. Maps to overrideLocalDns on Darwin.";
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

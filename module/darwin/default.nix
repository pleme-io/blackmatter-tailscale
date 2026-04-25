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

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "tag:fleet" "tag:dev" ];
      description = ''
        Tailnet tags this Mac advertises (documentation-only on Darwin —
        nix-darwin's services.tailscale doesn't pass flags to
        `tailscale up`). Apply once interactively:

          sudo tailscale up --advertise-tags=tag:fleet,tag:dev

        Tag ownership is controlled by the tailnet ACL managed in
        `pangea-architectures/workspaces/pleme-io-tailnet`.
      '';
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
        Accept Tailscale MagicDNS configuration on this node, mapped on
        Darwin to nix-darwin's `services.tailscale.overrideLocalDns`.

        WARNING — on Darwin this is the destructive switch: it sets
        `networking.dns = [ "100.100.100.100" ]`, replacing the
        system's primary DNS resolver entirely. Local mDNS, dnsmasq
        served by a sibling VPN, and search-domain magic on other
        scopes will all break unless you also re-add them.

        For bare-name resolution (`ssh rio`) prefer
        `magicDnsSearchSuffix` below — that path piggybacks on the
        `/etc/resolver/ts.net` entry nix-darwin already creates and
        leaves the rest of the DNS chain alone.
      '';
    };

    magicDnsSearchSuffix = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tail41c897.ts.net";
      description = ''
        Tailnet MagicDNS suffix to add as a system-wide DNS search
        domain. With this set, bare names like `rio` resolve to
        `rio.<suffix>`, which `/etc/resolver/ts.net` (created by
        nix-darwin's services.tailscale) then routes to MagicDNS at
        100.100.100.100.

        This is the SAFE path to bare-name resolution — it appends a
        search domain instead of replacing the system DNS resolver, so
        every other scoped resolver (mDNS, sibling-VPN dnsmasq) keeps
        working unchanged. Find your tailnet's suffix in
        `tailscale dns status`.

        Null = no search-domain wiring; bare names won't resolve and
        you must use raw tailnet IPs or full FQDNs.
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

    # When opting into search-domain wiring on Darwin, push the suffix
    # via `networksetup -setsearchdomains` for the typical built-in
    # network services. nix-darwin's networking.search is a no-op unless
    # at least one entry exists in knownNetworkServices, since macOS
    # stores search domains per-network-service in SCPreferences (NOT
    # in /etc/resolv.conf, which the system ignores). Default to the
    # two services every Apple Silicon machine has out of the box;
    # nodes with extra interfaces (NordVPN, Ethernet adapters) can
    # extend this list at the profile level.
    networking.search = lib.mkIf (cfg.magicDnsSearchSuffix != null)
      [ cfg.magicDnsSearchSuffix ];

    networking.knownNetworkServices = lib.mkIf (cfg.magicDnsSearchSuffix != null)
      (lib.mkDefault [ "Wi-Fi" "Thunderbolt Bridge" ]);
  };
}

# module/darwin/default.nix — macOS Tailscale module
#
# Provides the same blackmatter.components.tailscale.* option interface
# as the NixOS module and enforces it declaratively. nix-darwin's
# services.tailscale only handles tailscaled lifecycle on macOS — it
# does not push `tailscale up` flags. We close that gap here with a
# system activation hook that re-runs `tailscale up` with the typed
# flag set after every `darwin-rebuild`. `tailscale up` is idempotent:
# applying the same flag set repeatedly is a no-op.
{ config, lib, pkgs, ... }:
let
  cfg = config.blackmatter.components.tailscale;

  # Shared helper — same flag set NixOS uses, so a node with identical
  # `blackmatter.components.tailscale.*` config gets identical tailnet
  # state regardless of OS.
  buildUpFlags = import ../lib/up-flags.nix { inherit lib; } cfg;

  # `tailscale up` invocation as a flat shell-quoted string. authKeyFile
  # is platform-specific so it's appended here, not in the shared helper.
  upInvocation =
    "${pkgs.tailscale}/bin/tailscale up "
    + lib.escapeShellArgs (
      (lib.optional (cfg.authKeyFile != null) "--auth-key=file:${cfg.authKeyFile}")
      ++ buildUpFlags
    );
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
      description = ''
        Node role: `client` (default), `subnet-router` (advertises
        `advertisedRoutes`), or `exit-node` (advertises itself as a
        tailnet-wide egress).
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override Tailscale hostname (null = system hostname).";
    };

    advertisedRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Subnets to advertise via `--advertise-routes=`. Used by
        subnet-router or exit-node roles. Applied declaratively at
        every rebuild.
      '';
    };

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "tag:fleet" "tag:dev" ];
      description = ''
        Tailnet tags this node advertises (rendered as
        `--advertise-tags=` to `tailscale up` at activation time). Tag
        ownership is controlled by the tailnet ACL — nodes can advertise
        any tag, but only owners can authorize it. Manage the ACL via
        `pangea-architectures/workspaces/pleme-io-tailnet`.
      '';
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
      description = ''
        Path to a file containing a Tailscale auth key. Wired into
        `tailscale up --auth-key=file:<path>` at activation time so
        first-boot enrollment is automatic. Use a SOPS-rendered path
        (e.g. `config.sops.secrets."tailscale/auth-key".path`) — the
        file must be readable by root, since the activation hook runs
        as root.

        Null = interactive auth (operator runs `sudo tailscale login`
        manually). Set this to make the node fully declarative.
      '';
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

    ssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable Tailscale SSH (`tailscale up --ssh`). Defaults to
          false — every pleme node already runs OpenSSH with key-based
          auth, and Tailscale SSH's check-mode breaks non-interactive
          flows (scp, rsync, git over ssh) unless the ACL explicitly
          skips it for the source identity.
        '';
      };
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional flags appended to `tailscale up`.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      overrideLocalDns = cfg.acceptDns;
    };

    environment.systemPackages = [ pkgs.tailscale ];

    # Re-apply the typed config to the live tailscaled on every
    # `darwin-rebuild`. Mirrors nixpkgs' tailscaled-autoconnect.service
    # on NixOS. The brief polling loop covers the first-boot race where
    # tailscaled's launchd plist is loaded but the daemon hasn't yet
    # bound its local API socket.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "[blackmatter-tailscale] applying declarative config..."
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        ${pkgs.tailscale}/bin/tailscale status >/dev/null 2>&1 && break
        sleep 1
      done
      ${upInvocation} || \
        echo "[blackmatter-tailscale] tailscale up failed; tailscaled may not be ready yet — re-run darwin-rebuild"
    '';

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

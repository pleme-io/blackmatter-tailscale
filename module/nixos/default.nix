# module/nixos/default.nix — NixOS Tailscale module
#
# Provides blackmatter.components.tailscale.* options that map to the
# underlying services.tailscale and networking.firewall configuration.
{ config, lib, pkgs, ... }:
let
  cfg = config.blackmatter.components.tailscale;

  # Map role to useRoutingFeatures value
  routingFeatures =
    if cfg.role == "client" then "client"
    else "server";

  # Shared helper — same flag set used on Darwin for full declarative parity.
  buildUpFlags = import ../lib/up-flags.nix { inherit lib; } cfg;
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

    tags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "tag:fleet" "tag:server" ];
      description = ''
        Tailnet tags to advertise on first login (rendered as
        `--advertise-tags=` to `tailscale up`). Tag ownership is
        controlled by the tailnet ACL — nodes can advertise any tag,
        but only owners can authorize it. Manage the ACL via
        `pangea-architectures/workspaces/pleme-io-tailnet`.

        Tags drive ACL grants in the typed policy: `tag:fleet`
        receives the fleet-mesh SSH/cluster grants; `tag:server`
        receives extra reachability for K3s API and friends.
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
        Accept Tailscale MagicDNS configuration on this node — i.e.
        pass `--accept-dns=true` to `tailscale up`. Tailscale then
        rewrites systemd-resolved / resolv.conf so the tailnet's
        MagicDNS resolver answers for `<host>.<suffix>` and the
        suffix itself becomes a search domain.

        Subnet routers typically leave this false because their
        loopback /etc/resolv.conf is what advertised peers see;
        client/dev nodes that want bare-name resolution flip this
        on, OR set `magicDnsSearchSuffix` for a less invasive path
        that only adds the search domain without rewriting resolvers.
      '';
    };

    magicDnsSearchSuffix = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tail41c897.ts.net";
      description = ''
        Tailnet MagicDNS suffix to add as a system-wide DNS search
        domain via `networking.search`. With this set, bare names
        like `rio` resolve to `rio.<suffix>` and reach MagicDNS via
        whatever resolver chain is already in place for `*.ts.net`.

        This is a less invasive alternative to acceptDns=true on
        nodes that already have a working resolver chain for
        `*.ts.net` (e.g. via static records or a sibling resolver).
        For most NixOS nodes acceptDns=true is the simpler path.

        Null = no search-domain wiring.
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
        description = ''
          Enable Tailscale SSH (`tailscale up --ssh`). When true,
          tailscaled answers port 22 for connections that arrive over
          the tailnet and applies the tailnet ACL as the authorization
          source of truth.

          The fleet default is true. The canonical SSH path for
          pleme-io is:

            tailnet ACL  →  authorized identity  →  tailscale SSH on :22

          Adding/revoking SSH access is one edit to
          `pangea-architectures/workspaces/pleme-io-tailnet/spec.yaml`
          plus `nix run .#deploy` — no fleet-wide pubkey distribution,
          no rebuilds. The ACL in that workspace permits both
          `autogroup:admin → tag:fleet` (operator SSO identity) and
          `tag:fleet → tag:fleet` (device-to-device automation),
          always with `action: accept` so non-interactive flows
          (scp, rsync, git over ssh, `nixos-rebuild --target-host`)
          keep working — `action: check` is forbidden by the
          synthesis specs.

          Tailscale SSH only intercepts :22 for *tailnet-source*
          connections. Hosts that also run `services.openssh.enable
          = true` continue to answer LAN-side and WireGuard-direct
          connections with regular sshd + key auth — that is the
          fleet's break-glass path (rio in particular is configured
          this way; if Tailscale auth ever wedges, recover via
          LAN/VPN with fleet-keys).

          Set false on a node only if it must NOT participate in the
          tailnet-ACL-governed SSH plane (rare; a sandbox or
          throwaway VM that for some reason runs tailscaled but
          should not accept SSH from the fleet).
        '';
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
      extraUpFlags = buildUpFlags;
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

    networking.search = lib.mkIf (cfg.magicDnsSearchSuffix != null)
      [ cfg.magicDnsSearchSuffix ];

    # Re-apply the typed config on every nixos-rebuild. nixpkgs'
    # tailscaled-autoconnect.service early-exits when tailscaled is
    # already authed, so changes to tags / advertisedRoutes /
    # acceptRoutes after first auth never get pushed by it.
    #
    # We use `tailscale up` (not `tailscale set`) because the
    # `--advertise-tags` flag is only on `set` from Tailscale 1.96+,
    # and we need to support older deployed versions too. `up` accepts
    # the full flag set on every release. On an already-authed device
    # `tailscale up <flags>` updates persisted prefs without re-auth
    # when the originating identity owns the requested tags (e.g. an
    # autogroup:admin user logged in for first auth). Same flags =
    # no-op, drift = re-applied. Mirrors the Darwin activation hook so
    # both platforms converge identically.
    systemd.services.blackmatter-tailscale-configure = {
      description = "Apply blackmatter-tailscale typed config to running tailscaled";
      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
      wants = [ "tailscaled.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          ${pkgs.tailscale}/bin/tailscale status >/dev/null 2>&1 && break
          sleep 1
        done
        ${pkgs.tailscale}/bin/tailscale up ${lib.escapeShellArgs buildUpFlags} || \
          echo "[blackmatter-tailscale] tailscale up failed; tailscaled may not be ready"
      '';
    };
  };
}

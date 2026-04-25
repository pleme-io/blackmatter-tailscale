# module/lib/up-flags.nix — shared `tailscale up` flag builder
#
# Single source of truth for how the typed `blackmatter.components.tailscale`
# options translate to `tailscale up --foo=bar` flags. Consumed by both
# the NixOS and Darwin modules so the two platforms produce identical
# flag lists from identical config.
#
# Returns a list of flag strings (no `tailscale up` prefix). Caller adds
# the binary path and the auth-key flag (if any) — the auth key path is
# platform-specific (sops-nix on NixOS vs sops-nix-darwin / akeyless-nix
# on Darwin) so this helper stays platform-agnostic.
{ lib }:

cfg:

let
  hostnameFlag = lib.optional (cfg.hostname != null)
    "--hostname=${cfg.hostname}";

  routeFlags = lib.optional (cfg.advertisedRoutes != [])
    "--advertise-routes=${lib.concatStringsSep "," cfg.advertisedRoutes}";

  tagFlags = lib.optional (cfg.tags != [])
    "--advertise-tags=${lib.concatStringsSep "," cfg.tags}";

  exitNodeFlag = lib.optional (cfg.role == "exit-node")
    "--advertise-exit-node";

  acceptRouteFlag = lib.optional cfg.acceptRoutes
    "--accept-routes";

  dnsFlag = [ "--accept-dns=${lib.boolToString cfg.acceptDns}" ];

  sshFlag = lib.optional ((cfg.ssh.enable or false) == true)
    "--ssh";
in
  hostnameFlag
  ++ routeFlags
  ++ tagFlags
  ++ exitNodeFlag
  ++ acceptRouteFlag
  ++ dnsFlag
  ++ sshFlag
  ++ cfg.extraFlags

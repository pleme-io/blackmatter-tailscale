# blackmatter-tailscale

Cross-platform Tailscale VPN module for NixOS and nix-darwin.

## Overview

Provides a unified `blackmatter.components.tailscale` option interface for both NixOS and Darwin. Supports node roles (client, subnet-router, exit-node), route advertisement, MagicDNS, firewall rules, and auth key files. On NixOS, all options are fully declarative. On Darwin, some options are documentation-only and must be enforced via `tailscale up` CLI.

## Flake Outputs

- `nixosModules.default` -- NixOS module at `blackmatter.components.tailscale`
- `darwinModules.default` -- Darwin module at `blackmatter.components.tailscale`

## Usage

```nix
{
  inputs.blackmatter-tailscale.url = "github:pleme-io/blackmatter-tailscale";
}
```

```nix
# NixOS
blackmatter.components.tailscale = {
  enable = true;
  role = "subnet-router";
  advertisedRoutes = [ "10.0.0.0/24" ];
  acceptDns = true;
  firewall.trustInterface = true;
};

# Darwin
blackmatter.components.tailscale = {
  enable = true;
  acceptDns = true;
};
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `role` | enum | `"client"` | client, subnet-router, or exit-node |
| `hostname` | string? | null | Override Tailscale hostname |
| `advertisedRoutes` | list | `[]` | Subnets to advertise |
| `acceptDns` | bool | false | Accept MagicDNS |
| `authKeyFile` | path? | null | SOPS secret for auth key (NixOS only) |
| `firewall.trustInterface` | bool | true | Trust tailscale0 interface (NixOS only) |
| `ssh.enable` | bool | **true** | Enable Tailscale SSH (`tailscale up --ssh`) — fleet default |

## SSH

Tailscale SSH is the **canonical fleet SSH path**. With `ssh.enable = true`
(default), tailscaled answers `:22` for tailnet-source connections and
applies the tailnet ACL as the authorization source of truth.

```
tailnet ACL  →  authorized identity  →  tailscale SSH on :22
```

The ACL is declared in
[`pleme-io/pangea-architectures/workspaces/pleme-io-tailnet/spec.yaml`](https://github.com/pleme-io/pangea-architectures/tree/main/workspaces/pleme-io-tailnet)
and applied via `nix run .#deploy`. It permits two paths, both
`action: accept`:

- `autogroup:admin → tag:fleet` — operator SSO (any enrolled device
  with admin identity).
- `tag:fleet → tag:fleet` — device-to-device SSH for automation
  (`scp`, `rsync`, `git over ssh`, `nixos-rebuild --target-host`).

Adding/revoking SSH access is a one-line edit to `spec.yaml` plus a
`nix run .#deploy` — no fleet-wide pubkey distribution, no rebuilds.

**Break-glass.** Tailscale SSH only intercepts `:22` for tailnet-source
connections. Hosts that also enable `services.openssh` (NixOS) or
macOS Remote Login continue to answer LAN-side and WireGuard-direct
connections via regular sshd + key auth. rio is the canonical
break-glass node — if Tailscale auth ever wedges, recover via LAN/VPN
into rio with fleet-keys, then unwedge from there.

**Set `ssh.enable = false`** only when a node must NOT participate in
the tailnet-ACL-governed SSH plane (rare; sandbox/throwaway VMs).

## Structure

- `module/nixos/` -- NixOS module (fully declarative)
- `module/darwin/` -- Darwin module (services.tailscale + CLI enforcement)

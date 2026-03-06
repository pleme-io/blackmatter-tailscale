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

## Structure

- `module/nixos/` -- NixOS module (fully declarative)
- `module/darwin/` -- Darwin module (services.tailscale + CLI enforcement)

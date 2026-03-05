# blackmatter-tailscale

Cross-platform Tailscale VPN module for NixOS and nix-darwin. Provides a unified `blackmatter.components.tailscale.*` option interface that configures Tailscale networking, firewall rules, and node roles declaratively. On NixOS the module fully manages the Tailscale service and firewall; on Darwin it configures what it can and documents options that must be applied via the `tailscale up` CLI.

## Architecture

```
blackmatter-tailscale
  module/
    nixos/default.nix     # Full NixOS integration (services.tailscale + networking.firewall)
    darwin/default.nix     # macOS integration (services.tailscale + environment.systemPackages)
```

Both modules expose the same option namespace (`blackmatter.components.tailscale.*`), so the consuming flake can import the appropriate module per platform without changing the configuration.

### NixOS behavior

- Configures `services.tailscale` with `useRoutingFeatures` based on role
- Builds `extraUpFlags` from structured options (hostname, advertised routes, exit node, accept routes, DNS)
- Manages firewall: adds `tailscale0` to trusted interfaces and opens WireGuard UDP port 41641
- Supports headless auth via `authKeyFile` (SOPS secret path)

### Darwin behavior

- Enables `services.tailscale` and `overrideLocalDns` for MagicDNS
- Installs `pkgs.tailscale` CLI into system packages
- Role, advertised routes, and firewall options are accepted for configuration parity but are documentation-only -- Tailscale manages its own firewall on macOS, and advanced features require `sudo tailscale up` post-rebuild

## Features

- **Unified option interface** -- identical `blackmatter.components.tailscale.*` options on NixOS and Darwin
- **Role-based configuration** -- `client`, `subnet-router`, or `exit-node` with automatic flag generation
- **Structured flag building** -- hostname, advertised routes, accept-routes, accept-dns, and extra flags composed into `extraUpFlags` automatically
- **Firewall management** -- trust the `tailscale0` interface and open WireGuard port (NixOS)
- **Headless auth** -- `authKeyFile` option for SOPS-encrypted Tailscale auth keys on NixOS servers
- **MagicDNS** -- `acceptDns` maps to `--accept-dns` on NixOS and `overrideLocalDns` on Darwin

## Installation

Add as a flake input:

```nix
{
  inputs = {
    blackmatter-tailscale = {
      url = "github:pleme-io/blackmatter-tailscale";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### NixOS

```nix
{ inputs, ... }: {
  imports = [ inputs.blackmatter-tailscale.nixosModules.default ];
}
```

### nix-darwin

```nix
{ inputs, ... }: {
  imports = [ inputs.blackmatter-tailscale.darwinModules.default ];
}
```

## Usage

### Simple client

```nix
{
  blackmatter.components.tailscale = {
    enable = true;
    # role defaults to "client"
    # acceptRoutes defaults to true for clients
  };
}
```

### Subnet router

```nix
{
  blackmatter.components.tailscale = {
    enable = true;
    role = "subnet-router";
    hostname = "gateway-01";
    advertisedRoutes = [
      "10.0.0.0/24"
      "192.168.1.0/24"
    ];
    acceptDns = true;
  };
}
```

### Exit node

```nix
{
  blackmatter.components.tailscale = {
    enable = true;
    role = "exit-node";
    hostname = "exit-us-east";
    advertisedRoutes = [ "0.0.0.0/0" "::/0" ];
  };
}
```

### Headless server with SOPS auth key

```nix
{
  blackmatter.components.tailscale = {
    enable = true;
    role = "subnet-router";
    hostname = "k3s-node-01";
    authKeyFile = config.sops.secrets.tailscale-auth-key.path;
    advertisedRoutes = [ "10.43.0.0/16" ];
    firewall = {
      trustInterface = true;
      allowWireguard = true;
    };
  };
}
```

## Configuration Reference

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` | `false` | Enable Tailscale VPN |
| `role` | `enum` | `"client"` | Node role: `client`, `subnet-router`, or `exit-node` |
| `hostname` | `nullOr str` | `null` | Override Tailscale hostname (null = system hostname) |
| `advertisedRoutes` | `listOf str` | `[]` | Subnets to advertise |
| `acceptRoutes` | `bool` | `true` (client) | Accept routes from other nodes |
| `acceptDns` | `bool` | `false` | Accept MagicDNS configuration |
| `authKeyFile` | `nullOr path` | `null` | Path to SOPS secret with auth key (NixOS only) |
| `firewall.trustInterface` | `bool` | `true` | Add tailscale0 to trusted interfaces (NixOS only) |
| `firewall.allowWireguard` | `bool` | `true` | Open UDP 41641 for WireGuard (NixOS only) |
| `extraFlags` | `listOf str` | `[]` | Additional flags for `tailscale up` |

## Platform Differences

| Feature | NixOS | Darwin |
|---------|-------|--------|
| Service management | Full (`services.tailscale`) | Full (`services.tailscale`) |
| Firewall rules | Declarative (networking.firewall) | Managed by Tailscale itself |
| Auth key file | Supported | Not supported (interactive auth) |
| Route advertising | Declarative via `extraUpFlags` | Requires `sudo tailscale up` post-rebuild |
| MagicDNS | `--accept-dns` flag | `overrideLocalDns` setting |

## Development

```bash
# Check the flake
nix flake check

# Evaluate NixOS module
nix eval .#nixosModules.default --apply '(m: builtins.typeOf m)'

# Evaluate Darwin module
nix eval .#darwinModules.default --apply '(m: builtins.typeOf m)'
```

## Project Structure

```
flake.nix                   # Flake: exports nixosModules.default + darwinModules.default
module/
  nixos/default.nix         # NixOS module (services.tailscale + networking.firewall)
  darwin/default.nix        # Darwin module (services.tailscale + environment.systemPackages)
```

## Related Projects

- [blackmatter](https://github.com/pleme-io/blackmatter) -- Home-manager/nix-darwin module aggregator
- [nix](https://github.com/pleme-io/nix) -- Private NixOS/nix-darwin configuration that consumes this module
- [k8s](https://github.com/pleme-io/k8s) -- GitOps manifests for the pleme-io cluster (Tailscale connects nodes)

## License

MIT

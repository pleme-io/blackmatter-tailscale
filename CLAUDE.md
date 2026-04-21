# blackmatter-tailscale — Claude Orientation

One-sentence purpose: cross-platform Tailscale provisioning — NixOS module
wires `services.tailscale`, Darwin module wires the launchd agent + menu-bar
app, both via the single `blackmatter.components.tailscale` option tree.

## Classification

- **Archetype:** `blackmatter-component-nixos-darwin`
- **Flake shape:** `substrate/lib/blackmatter-component-flake.nix`
- **Option namespace:** `blackmatter.components.tailscale`
- **No HM module, no packages, no overlay** — purely system-level config.

## Where to look

| Intent | File |
|--------|------|
| Linux side (services.tailscale) | `module/nixos/default.nix` |
| Darwin side (launchd + GUI) | `module/darwin/default.nix` |
| Flake surface | `flake.nix` |

## What NOT to do

- Don't add node-identifying data (auth keys, tailnet IDs). Those live in
  SOPS in the `nix` repo.
- Don't register at the HM level — the agent is a system service, not
  per-user config.

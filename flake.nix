{
  description = "Blackmatter Tailscale — cross-platform Tailscale VPN provisioning";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    substrate = {
      url = "github:pleme-io/substrate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, substrate, ... }:
    (import "${substrate}/lib/blackmatter-component-flake.nix") {
      inherit self nixpkgs;
      name = "blackmatter-tailscale";
      description = "Cross-platform Tailscale VPN module (NixOS + Darwin)";
      modules.nixos = ./module/nixos;
      modules.darwin = ./module/darwin;
    };
}

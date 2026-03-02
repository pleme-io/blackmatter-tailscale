{
  description = "Blackmatter Tailscale - cross-platform Tailscale VPN module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./module/nixos;
    darwinModules.default = import ./module/darwin;
  };
}

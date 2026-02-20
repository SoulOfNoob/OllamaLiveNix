{
  description = "OllamaLive – bootable NixOS USB appliance for GPU inference";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      nixosConfig = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };
    in
    {
      nixosConfigurations.OllamaLive = nixosConfig;

      packages.${system} = rec {
        iso = nixosConfig.config.system.build.images.iso;
        raw = nixosConfig.config.system.build.images.raw-efi;
        default = raw;
      };
    };
}

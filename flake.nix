{
  description = "OllamaLive – bootable NixOS USB appliance for GPU inference";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.OllamaLive = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };

      packages.${system} = rec {
        iso = nixos-generators.nixosGenerate {
          inherit system;
          modules = [ ./configuration.nix ];
          format = "iso";
        };

        raw = nixos-generators.nixosGenerate {
          inherit system;
          modules = [ ./configuration.nix ];
          format = "raw-efi";
        };

        default = iso;
      };
    };
}

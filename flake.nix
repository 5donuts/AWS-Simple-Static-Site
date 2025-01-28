{
  description = "Flake to provide an OpenTofu development environment";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      # See: https://xeiaso.net/blog/nix-flakes-1-2022-02-21/
      systems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in {
      # TODO: pull this into the same multi-arch setup as everything else
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;

      devShells = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.mkShell { packages = [ pkgs.awscli2 pkgs.opentofu ]; };
        });

      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          tf = pkgs.opentofu;
          aws = pkgs.awscli2;
        });
    };
}

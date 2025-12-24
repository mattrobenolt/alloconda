{
  description = "🐍🦎";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mattware = {
      url = "github:mattrobenolt/nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      mattware,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ mattware.overlays.default ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            just
            zig_0_15
            zls_0_15
            zlint-unstable
            fd
            pkg-config
            python314
            uv
            uvShellHook
            mdbook
            wrangler
            gh
          ];
        };
      }
    );
}

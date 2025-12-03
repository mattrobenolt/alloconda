{
  description = "Zig development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mattrobenolt.url = "github:mattrobenolt/nixpkgs";
  };

  outputs =
    { nixpkgs
    , flake-utils
    , mattrobenolt
    , ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ mattrobenolt.overlays.default ];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          venvDir = ".venv";
          packages = with pkgs; [
            zig_0_15
            zls_0_15
            zlint
            uv
            python313
            python313Packages.venvShellHook
            pkg-config
          ];
        };
      }
    );
}

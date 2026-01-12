{
  description = "🐍🦎";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mattware = {
      url = "github:mattrobenolt/nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      zig,
      mattware,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            zig.overlays.default
            mattware.overlays.default
          ];
        };
        wrangler = pkgs.writeShellScriptBin "wrangler" ''
          exec ${pkgs.bun}/bin/bunx --bun wrangler@4.58.0 "$@"
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc ];
          packages = with pkgs; [
            just
            zigpkgs."0.15.2"
            zls_0_15
            zlint
            fd
            pkg-config
            python314
            uv
            uvShellHook
            mdbook
            gh
            bun
            wrangler
          ];
        };
      }
    );
}

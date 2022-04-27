{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:roarkanize/zig-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system; overlays = [
        (final: prev: {
          zig = zig-overlay.packages.${prev.system}.master.latest;
        })
      ];
      };
    in
    {
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [ zig ];
      };
    });
}

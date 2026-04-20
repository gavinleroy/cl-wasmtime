# cl-wasmtime

A Common Lisp wrapper for Wasmtime.

> :warning: This package is AI slop, like *realllly* sloppy, use at your own risk. Model used: Anthropic, Opus 4.5

## Using with Nix Overlay

```nix 
  inputs = {
    # ...
    cl-wasmtime.url = "github:gavinleroy/cl-wasmtime";
  };

  outputs = { self, cl-wasmtime, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ cl-wasmtime.overlays.${system}.default ];
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            (pkgs.sbcl.withPackages (ps: [
              ps.cl-wasmtime
              # ...
            ]))
          ];
        };
      }
    );
```

## Using with anything else

Godspeed

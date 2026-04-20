{
  description = "cl-wasmtime: Common Lisp wrapper for Wasmtime";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        wasmtimeLib = pkgs.wasmtime.lib;
        wasmtimeDev = pkgs.wasmtime.dev;

        cl-wasmtime-pkg = pkgs.sbcl.buildASDFSystem {
          pname = "cl-wasmtime";
          version = "0.1.0";
          src = pkgs.lib.cleanSource self;
          lispLibs = with pkgs.sbclPackages; [
            cffi
            trivial-garbage
            fiveam
          ];
          buildInputs = [ wasmtimeLib ];
          nativeBuildInputs = [ wasmtimeDev ];
          postPatch = ''
            substituteInPlace src/ffi.lisp \
              --replace-fail 'libwasmtime.so' '${wasmtimeLib}/lib/libwasmtime.so' \
              --replace-fail 'libwasmtime.dylib' '${wasmtimeLib}/lib/libwasmtime.dylib'
          '';
        };

        run-tests = pkgs.writeShellScriptBin "run-tests" ''
          sbcl --non-interactive \
            --eval '(require :asdf)' \
            --eval '(asdf:load-asd (merge-pathnames "cl-wasmtime.asd" (uiop:getcwd)))' \
            --eval '(sb-ext:exit :code (if (asdf:test-system "cl-wasmtime") 0 1))'
        '';

        sbclWithDocs = pkgs.sbcl.withPackages (ps: with ps; cl-wasmtime-pkg.lispLibs ++ [ staple ]);

        documentation = pkgs.stdenv.mkDerivation {
          pname = "cl-wasmtime-documentation";
          version = "0.1.0";
          src = pkgs.lib.cleanSource self;
          buildInputs = [
            sbclWithDocs
            wasmtimeLib
            wasmtimeDev
          ];
          phases = [
            "unpackPhase"
            "buildPhase"
            "installPhase"
          ];
          buildPhase = ''
            export HOME=$(mktemp -d)
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ wasmtimeLib ]}"
            export CPATH="${wasmtimeDev}/include"
            rm -rf docs
            ${sbclWithDocs}/bin/sbcl --non-interactive \
              --eval '(require :asdf)' \
              --eval '(asdf:load-asd (merge-pathnames "cl-wasmtime.asd" (uiop:getcwd)))' \
              --load ${./scripts/gen-docs.lisp}
          '';
          installPhase = ''
            mkdir -p $out
            cp -r docs/* $out/
          '';
        };
      in
      {
        packages = {
          default = cl-wasmtime-pkg;
          documentation = documentation;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ cl-wasmtime-pkg ];
          packages = [
            (pkgs.sbcl.withPackages (ps: with ps; cl-wasmtime-pkg.lispLibs ++ [ staple ]))
            pkgs.pkg-config
            run-tests
          ];
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ wasmtimeLib ];
          CPATH = "${wasmtimeDev}/include";
        };
      }
    );
}

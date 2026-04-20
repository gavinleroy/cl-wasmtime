# CLAUDE.md

This file provides guidance to Claude when working with code in this repository.

## cl-wasmtime

This project provides a Common Lisp wrapper around Wasmtime.

## Key Architecture

- All system setup is done via the `flake.nix` file, NO software is (OR SHOULD BE) installed on the machine outside of Nix.
- `src/package.lisp` exports the pure Common Lisp, high-level objects to users. It SHOULD NOT expose any FFI internals.
- `src/ffi.lisp` is the low-level API built strictly for talking with C. Nothing in this file should be exposed to users.
- `src/core.lisp` is the high-level API that hides raw pointers, and other implementation details from the user. Functions should expose logic the LISP way and users should believe that the entire project is built in LISP, rather than in C.

## Development Guidelines

- No task is complete until the command `nix develop --command run-tests` succeeds
- Don't add excessive comments unless prompted
- Keep lines under 80 characters
- Don't disable warnings or tests unless prompted

## Important Notes

- NEVER change the `flake.nix` file unless explicitly prompted
- NEVER install software or modify the environment via terminal commands
- NEVER proactively create documentation files (*.md,*.txt) or README files
- NEVER stage or commit changes
- NEVER comment out, disable, or remove tests unless explicitly asked

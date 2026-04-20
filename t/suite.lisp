(in-package :cl-wasmtime/tests)

(def-suite cl-wasmtime-tests
  :description "Test suite for cl-wasmtime")

(defun run-tests ()
  "Run all cl-wasmtime tests. Returns T if all pass."
  (run! 'cl-wasmtime-tests))

(defsystem "cl-wasmtime"
  :description "A Common Lisp wrapper for Wasmtime"
  :version "0.1.0"
  :author "Gavin Gray"
  :license "MIT"
  :homepage "https://github.com/gavinleroy/cl-wasmtime"
  :depends-on ("cffi" "trivial-garbage")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "ffi")
                             (:file "core"))))
  :in-order-to ((test-op (test-op "cl-wasmtime/tests"))))


(defsystem "cl-wasmtime/tests"
  :description "Tests for cl-wasmtime"
  :depends-on ("cl-wasmtime" "fiveam")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "suite")
               (:file "core-tests"))
  :perform (test-op (o c) (symbol-call :cl-wasmtime/tests :run-tests)))

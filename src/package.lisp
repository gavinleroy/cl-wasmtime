(defpackage :cl-wasmtime
  (:use :cl :cffi)
  (:export
   ;; Conditions
   #:wasmtime-error
   #:wasmtime-error-message
   #:wasm-trap
   #:wasm-trap-code

   ;; Config
   #:config
   #:make-config

   ;; Engine
   #:engine
   #:make-engine

   ;; Store
   #:store
   #:make-store
   #:store-context
   #:store-gc
   #:store-set-fuel
   #:store-get-fuel

   ;; Module
   #:module
   #:load-module
   #:load-module-from-file
   #:load-module-from-wat
   #:validate-module
   #:module-imports
   #:module-exports
   #:module-serialize
   #:module-deserialize
   #:module-serialize-to-file
   #:module-deserialize-from-file
   #:module-clone

   ;; Linker
   #:linker
   #:make-linker
   #:linker-allow-shadowing
   #:linker-define
   #:linker-define-func
   #:linker-define-wasi
   #:linker-instantiate
   #:linker-get

   ;; Instance
   #:instance
   #:instantiate
   #:instance-export
   #:instance-exports

   ;; Function
   #:wasm-func
   #:call-function
   #:make-host-function

   ;; Memory
   #:wasm-memory
   #:make-memory
   #:memory-data
   #:memory-data-size
   #:memory-size
   #:memory-grow
   #:memory-ref

   ;; Global
   #:wasm-global
   #:make-global
   #:global-value

   ;; Table
   #:wasm-table
   #:make-table
   #:table-size
   #:table-get
   #:table-set
   #:table-grow

   ;; WAT
   #:wat->wasm

   ;; WASI
   #:wasi-config
   #:make-wasi-config
   #:wasi-config-inherit-stdio
   #:wasi-config-inherit-argv
   #:wasi-config-inherit-env
   #:wasi-config-set-argv
   #:wasi-config-set-env
   #:wasi-config-preopen-dir
   #:store-set-wasi

   ;; Component Model
   #:component
   #:load-component
   #:load-component-from-file
   #:component-clone
   #:component-serialize
   #:component-deserialize
   #:component-serialize-to-file
   #:component-deserialize-from-file
   #:component-linker
   #:make-component-linker
   #:component-linker-add-wasi
   #:component-linker-root
   #:component-linker-instance
   #:component-linker-instance-add-instance
   #:component-linker-instance-add-module
   #:component-instance
   #:component-linker-instantiate
   #:component-instance-export))

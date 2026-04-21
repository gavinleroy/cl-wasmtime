(in-package :cl-wasmtime)

(cffi:define-foreign-library libwasmtime
  (:darwin "libwasmtime.dylib")
  (:unix "libwasmtime.so")
  (t (:default "libwasmtime")))

(cffi:use-foreign-library libwasmtime)

;;; ============================================================
;;; Opaque Pointer Types
;;; ============================================================

(defctype wasm-engine-t :pointer)
(defctype wasm-config-t :pointer)
(defctype wasm-store-t :pointer)
(defctype wasmtime-context-t :pointer)
(defctype wasmtime-module-t :pointer)
(defctype wasmtime-linker-t :pointer)
(defctype wasmtime-error-t :pointer)
(defctype wasm-trap-t :pointer)
(defctype wasm-functype-t :pointer)
(defctype wasm-valtype-t :pointer)
(defctype wasm-globaltype-t :pointer)
(defctype wasm-memorytype-t :pointer)
(defctype wasm-tabletype-t :pointer)
(defctype wasm-externtype-t :pointer)
(defctype wasm-importtype-t :pointer)
(defctype wasm-exporttype-t :pointer)
(defctype wasi-config-t :pointer)
(defctype wasmtime-caller-t :pointer)

;;; ============================================================
;;; Value Type Constants
;;; ============================================================

(defconstant +wasm-i32+ 0)
(defconstant +wasm-i64+ 1)
(defconstant +wasm-f32+ 2)
(defconstant +wasm-f64+ 3)
(defconstant +wasm-v128+ 4)
(defconstant +wasm-funcref+ 5)
(defconstant +wasm-externref+ 6)
(defconstant +wasm-anyref+ 7)

;;; ============================================================
;;; Extern Kind Constants
;;; ============================================================

(defconstant +wasmtime-extern-func+ 0)
(defconstant +wasmtime-extern-global+ 1)
(defconstant +wasmtime-extern-table+ 2)
(defconstant +wasmtime-extern-memory+ 3)

;;; ============================================================
;;; Mutability Constants
;;; ============================================================

(defconstant +wasm-const+ 0)
(defconstant +wasm-var+ 1)

;;; ============================================================
;;; Trap Code Constants
;;; ============================================================

(defconstant +wasmtime-trap-code-stack-overflow+ 0)
(defconstant +wasmtime-trap-code-memory-out-of-bounds+ 1)
(defconstant +wasmtime-trap-code-heap-misaligned+ 2)
(defconstant +wasmtime-trap-code-table-out-of-bounds+ 3)
(defconstant +wasmtime-trap-code-indirect-call-to-null+ 4)
(defconstant +wasmtime-trap-code-bad-signature+ 5)
(defconstant +wasmtime-trap-code-integer-overflow+ 6)
(defconstant +wasmtime-trap-code-integer-division-by-zero+ 7)
(defconstant +wasmtime-trap-code-bad-conversion-to-integer+ 8)
(defconstant +wasmtime-trap-code-unreachable+ 9)
(defconstant +wasmtime-trap-code-interrupt+ 10)
(defconstant +wasmtime-trap-code-out-of-fuel+ 11)

;;; ============================================================
;;; Struct Types
;;; ============================================================

(defcstruct wasm-byte-vec-t
  (size :size)
  (data :pointer))

(defcstruct wasm-valtype-vec-t
  (size :size)
  (data :pointer))

(defcstruct wasm-importtype-vec-t
  (size :size)
  (data :pointer))

(defcstruct wasm-exporttype-vec-t
  (size :size)
  (data :pointer))

(defcstruct wasm-limits-t
  (min :uint32)
  (max :uint32))

(defcstruct wasmtime-func-t
  (store-id :uint64)
  (index :size))

(defcstruct wasmtime-memory-t
  (store-id :uint64)
  (index :uint32)
  (padding1 :uint32)
  (index2 :uint32)
  (padding2 :uint32))

(defcstruct wasmtime-global-t
  (store-id :uint64)
  (index :size))

(defcstruct wasmtime-table-t
  (store-id :uint64)
  (index :size))

(defcstruct wasmtime-instance-t
  (store-id :uint64)
  (index :size))

(defcstruct wasmtime-extern-t
  (kind :uint8)
  (padding :uint8 :count 7)
  (of :uint8 :count 24))

(defcstruct wasmtime-val-raw-t
  (bytes :uint8 :count 16))

(defcstruct wasmtime-val-t
  (kind :uint8)
  (padding :uint8 :count 7)
  (of :uint8 :count 24))

;;; ============================================================
;;; Engine Functions
;;; ============================================================

(defcfun ("wasm_engine_new" %wasm-engine-new) wasm-engine-t)

(defcfun ("wasm_engine_delete" %wasm-engine-delete) :void
  (engine wasm-engine-t))

(defcfun ("wasm_engine_new_with_config" %wasm-engine-new-with-config)
    wasm-engine-t
  (config wasm-config-t))

;;; ============================================================
;;; Config Functions
;;; ============================================================

(defcfun ("wasm_config_new" %wasm-config-new) wasm-config-t)

(defcfun ("wasm_config_delete" %wasm-config-delete) :void
  (config wasm-config-t))

(defcfun ("wasmtime_config_debug_info_set" %wasmtime-config-debug-info-set)
    :void
  (config wasm-config-t)
  (enable :bool))

(defcfun ("wasmtime_config_consume_fuel_set" %wasmtime-config-consume-fuel-set)
    :void
  (config wasm-config-t)
  (enable :bool))

(defcfun ("wasmtime_config_wasm_threads_set" %wasmtime-config-wasm-threads-set)
    :void
  (config wasm-config-t)
  (enable :bool))

(defcfun ("wasmtime_config_wasm_simd_set" %wasmtime-config-wasm-simd-set)
    :void
  (config wasm-config-t)
  (enable :bool))

(defcfun ("wasmtime_config_wasm_bulk_memory_set"
          %wasmtime-config-wasm-bulk-memory-set)
    :void
  (config wasm-config-t)
  (enable :bool))

(defcfun ("wasmtime_config_wasm_multi_value_set"
          %wasmtime-config-wasm-multi-value-set)
    :void
  (config wasm-config-t)
  (enable :bool))

(defcfun ("wasmtime_config_wasm_reference_types_set"
          %wasmtime-config-wasm-reference-types-set)
    :void
  (config wasm-config-t)
  (enable :bool))

;;; ============================================================
;;; Store Functions
;;; ============================================================

(defcfun ("wasmtime_store_new" %wasmtime-store-new) wasm-store-t
  (engine wasm-engine-t)
  (data :pointer)
  (finalizer :pointer))

(defcfun ("wasmtime_store_delete" %wasmtime-store-delete) :void
  (store wasm-store-t))

(defcfun ("wasmtime_store_context" %wasmtime-store-context) wasmtime-context-t
  (store wasm-store-t))

(defcfun ("wasmtime_context_gc" %wasmtime-context-gc) :void
  (context wasmtime-context-t))

(defcfun ("wasmtime_context_set_fuel" %wasmtime-context-set-fuel)
    wasmtime-error-t
  (context wasmtime-context-t)
  (fuel :uint64))

(defcfun ("wasmtime_context_get_fuel" %wasmtime-context-get-fuel)
    wasmtime-error-t
  (context wasmtime-context-t)
  (fuel :pointer))

;;; ============================================================
;;; Error Functions
;;; ============================================================

(defcfun ("wasmtime_error_new" %wasmtime-error-new) wasmtime-error-t
  (message :string))

(defcfun ("wasmtime_error_delete" %wasmtime-error-delete) :void
  (error wasmtime-error-t))

(defcfun ("wasmtime_error_message" %wasmtime-error-message) :void
  (error wasmtime-error-t)
  (message :pointer))

;;; ============================================================
;;; Trap Functions
;;; ============================================================

(defcfun ("wasmtime_trap_new" %wasmtime-trap-new) wasm-trap-t
  (message :string)
  (message-len :size))

(defcfun ("wasm_trap_delete" %wasm-trap-delete) :void
  (trap wasm-trap-t))

(defcfun ("wasm_trap_message" %wasm-trap-message) :void
  (trap wasm-trap-t)
  (message :pointer))

(defcfun ("wasmtime_trap_code" %wasmtime-trap-code) :bool
  (trap wasm-trap-t)
  (code :pointer))

;;; ============================================================
;;; Module Functions
;;; ============================================================

(defcfun ("wasmtime_module_new" %wasmtime-module-new) wasmtime-error-t
  (engine wasm-engine-t)
  (wasm :pointer)
  (wasm-len :size)
  (module-out :pointer))

(defcfun ("wasmtime_module_delete" %wasmtime-module-delete) :void
  (module wasmtime-module-t))

(defcfun ("wasmtime_module_clone" %wasmtime-module-clone) wasmtime-module-t
  (module wasmtime-module-t))

(defcfun ("wasmtime_module_validate" %wasmtime-module-validate) wasmtime-error-t
  (engine wasm-engine-t)
  (wasm :pointer)
  (wasm-len :size))

(defcfun ("wasmtime_module_imports" %wasmtime-module-imports) :void
  (module wasmtime-module-t)
  (imports :pointer))

(defcfun ("wasmtime_module_exports" %wasmtime-module-exports) :void
  (module wasmtime-module-t)
  (exports :pointer))

(defcfun ("wasmtime_module_serialize" %wasmtime-module-serialize)
    wasmtime-error-t
  (module wasmtime-module-t)
  (bytes :pointer))

(defcfun ("wasmtime_module_deserialize" %wasmtime-module-deserialize)
    wasmtime-error-t
  (engine wasm-engine-t)
  (bytes :pointer)
  (bytes-len :size)
  (module-out :pointer))

;;; ============================================================
;;; Instance Functions
;;; ============================================================

(defcfun ("wasmtime_instance_new" %wasmtime-instance-new) wasmtime-error-t
  (context wasmtime-context-t)
  (module wasmtime-module-t)
  (imports :pointer)
  (num-imports :size)
  (instance-out :pointer)
  (trap-out :pointer))

(defcfun ("wasmtime_instance_export_get" %wasmtime-instance-export-get) :bool
  (context wasmtime-context-t)
  (instance :pointer)
  (name :string)
  (name-len :size)
  (extern-out :pointer))

(defcfun ("wasmtime_instance_export_nth" %wasmtime-instance-export-nth) :bool
  (context wasmtime-context-t)
  (instance :pointer)
  (index :size)
  (name-out :pointer)
  (name-len-out :pointer)
  (extern-out :pointer))

;;; ============================================================
;;; Linker Functions
;;; ============================================================

(defcfun ("wasmtime_linker_new" %wasmtime-linker-new) wasmtime-linker-t
  (engine wasm-engine-t))

(defcfun ("wasmtime_linker_delete" %wasmtime-linker-delete) :void
  (linker wasmtime-linker-t))

(defcfun ("wasmtime_linker_allow_shadowing" %wasmtime-linker-allow-shadowing)
    :void
  (linker wasmtime-linker-t)
  (allow :bool))

(defcfun ("wasmtime_linker_define" %wasmtime-linker-define) wasmtime-error-t
  (linker wasmtime-linker-t)
  (context wasmtime-context-t)
  (module-name :string)
  (module-name-len :size)
  (field-name :string)
  (field-name-len :size)
  (item :pointer))

(defcfun ("wasmtime_linker_define_func" %wasmtime-linker-define-func)
    wasmtime-error-t
  (linker wasmtime-linker-t)
  (module-name :string)
  (module-name-len :size)
  (field-name :string)
  (field-name-len :size)
  (functype wasm-functype-t)
  (callback :pointer)
  (env :pointer)
  (finalizer :pointer))

(defcfun ("wasmtime_linker_define_wasi" %wasmtime-linker-define-wasi)
    wasmtime-error-t
  (linker wasmtime-linker-t))

(defcfun ("wasmtime_linker_define_instance" %wasmtime-linker-define-instance)
    wasmtime-error-t
  (linker wasmtime-linker-t)
  (context wasmtime-context-t)
  (name :string)
  (name-len :size)
  (instance :pointer))

(defcfun ("wasmtime_linker_instantiate" %wasmtime-linker-instantiate)
    wasmtime-error-t
  (linker wasmtime-linker-t)
  (context wasmtime-context-t)
  (module wasmtime-module-t)
  (instance-out :pointer)
  (trap-out :pointer))

(defcfun ("wasmtime_linker_get" %wasmtime-linker-get) :bool
  (linker wasmtime-linker-t)
  (context wasmtime-context-t)
  (module-name :string)
  (module-name-len :size)
  (field-name :string)
  (field-name-len :size)
  (item-out :pointer))

;;; ============================================================
;;; Function Functions
;;; ============================================================

(defcfun ("wasmtime_func_new" %wasmtime-func-new) :void
  (context wasmtime-context-t)
  (functype wasm-functype-t)
  (callback :pointer)
  (env :pointer)
  (finalizer :pointer)
  (func-out :pointer))

(defcfun ("wasmtime_func_type" %wasmtime-func-type) wasm-functype-t
  (context wasmtime-context-t)
  (func :pointer))

(defcfun ("wasmtime_func_call" %wasmtime-func-call) wasmtime-error-t
  (context wasmtime-context-t)
  (func :pointer)
  (args :pointer)
  (num-args :size)
  (results :pointer)
  (num-results :size)
  (trap-out :pointer))

(defcfun ("wasmtime_caller_export_get" %wasmtime-caller-export-get) :bool
  (caller wasmtime-caller-t)
  (name :string)
  (name-len :size)
  (extern-out :pointer))

(defcfun ("wasmtime_caller_context" %wasmtime-caller-context) wasmtime-context-t
  (caller wasmtime-caller-t))

;;; ============================================================
;;; Memory Functions
;;; ============================================================

(defcfun ("wasmtime_memory_new" %wasmtime-memory-new) wasmtime-error-t
  (context wasmtime-context-t)
  (memtype wasm-memorytype-t)
  (memory-out :pointer))

(defcfun ("wasmtime_memory_type" %wasmtime-memory-type) wasm-memorytype-t
  (context wasmtime-context-t)
  (memory :pointer))

(defcfun ("wasmtime_memory_data" %wasmtime-memory-data) :pointer
  (context wasmtime-context-t)
  (memory :pointer))

(defcfun ("wasmtime_memory_data_size" %wasmtime-memory-data-size) :size
  (context wasmtime-context-t)
  (memory :pointer))

(defcfun ("wasmtime_memory_size" %wasmtime-memory-size) :uint64
  (context wasmtime-context-t)
  (memory :pointer))

(defcfun ("wasmtime_memory_grow" %wasmtime-memory-grow) wasmtime-error-t
  (context wasmtime-context-t)
  (memory :pointer)
  (delta :uint64)
  (prev-size :pointer))

;;; ============================================================
;;; Global Functions
;;; ============================================================

(defcfun ("wasmtime_global_new" %wasmtime-global-new) wasmtime-error-t
  (context wasmtime-context-t)
  (globaltype wasm-globaltype-t)
  (val :pointer)
  (global-out :pointer))

(defcfun ("wasmtime_global_type" %wasmtime-global-type) wasm-globaltype-t
  (context wasmtime-context-t)
  (global :pointer))

(defcfun ("wasmtime_global_get" %wasmtime-global-get) :void
  (context wasmtime-context-t)
  (global :pointer)
  (val-out :pointer))

(defcfun ("wasmtime_global_set" %wasmtime-global-set) wasmtime-error-t
  (context wasmtime-context-t)
  (global :pointer)
  (val :pointer))

;;; ============================================================
;;; Table Functions
;;; ============================================================

(defcfun ("wasmtime_table_new" %wasmtime-table-new) wasmtime-error-t
  (context wasmtime-context-t)
  (tabletype wasm-tabletype-t)
  (init :pointer)
  (table-out :pointer))

(defcfun ("wasmtime_table_type" %wasmtime-table-type) wasm-tabletype-t
  (context wasmtime-context-t)
  (table :pointer))

(defcfun ("wasmtime_table_get" %wasmtime-table-get) :bool
  (context wasmtime-context-t)
  (table :pointer)
  (index :uint32)
  (val-out :pointer))

(defcfun ("wasmtime_table_set" %wasmtime-table-set) wasmtime-error-t
  (context wasmtime-context-t)
  (table :pointer)
  (index :uint32)
  (val :pointer))

(defcfun ("wasmtime_table_size" %wasmtime-table-size) :uint32
  (context wasmtime-context-t)
  (table :pointer))

(defcfun ("wasmtime_table_grow" %wasmtime-table-grow) wasmtime-error-t
  (context wasmtime-context-t)
  (table :pointer)
  (delta :uint32)
  (init :pointer)
  (prev-size :pointer))

;;; ============================================================
;;; Type Functions
;;; ============================================================

(defcfun ("wasm_valtype_new" %wasm-valtype-new) wasm-valtype-t
  (kind :uint8))

(defcfun ("wasm_valtype_delete" %wasm-valtype-delete) :void
  (valtype wasm-valtype-t))

(defcfun ("wasm_valtype_kind" %wasm-valtype-kind) :uint8
  (valtype wasm-valtype-t))

(defcfun ("wasm_functype_new" %wasm-functype-new) wasm-functype-t
  (params :pointer)
  (results :pointer))

(defcfun ("wasm_functype_delete" %wasm-functype-delete) :void
  (functype wasm-functype-t))

(defcfun ("wasm_functype_params" %wasm-functype-params) :pointer
  (functype wasm-functype-t))

(defcfun ("wasm_functype_results" %wasm-functype-results) :pointer
  (functype wasm-functype-t))

(defcfun ("wasm_memorytype_new" %wasm-memorytype-new) wasm-memorytype-t
  (limits :pointer))

(defcfun ("wasm_memorytype_delete" %wasm-memorytype-delete) :void
  (memtype wasm-memorytype-t))

(defcfun ("wasm_memorytype_limits" %wasm-memorytype-limits) :pointer
  (memtype wasm-memorytype-t))

(defcfun ("wasm_globaltype_new" %wasm-globaltype-new) wasm-globaltype-t
  (valtype wasm-valtype-t)
  (mutability :uint8))

(defcfun ("wasm_globaltype_delete" %wasm-globaltype-delete) :void
  (globaltype wasm-globaltype-t))

(defcfun ("wasm_globaltype_content" %wasm-globaltype-content) wasm-valtype-t
  (globaltype wasm-globaltype-t))

(defcfun ("wasm_globaltype_mutability" %wasm-globaltype-mutability) :uint8
  (globaltype wasm-globaltype-t))

(defcfun ("wasm_tabletype_new" %wasm-tabletype-new) wasm-tabletype-t
  (valtype wasm-valtype-t)
  (limits :pointer))

(defcfun ("wasm_tabletype_delete" %wasm-tabletype-delete) :void
  (tabletype wasm-tabletype-t))

(defcfun ("wasm_tabletype_element" %wasm-tabletype-element) wasm-valtype-t
  (tabletype wasm-tabletype-t))

(defcfun ("wasm_tabletype_limits" %wasm-tabletype-limits) :pointer
  (tabletype wasm-tabletype-t))

;;; ============================================================
;;; Vec Functions
;;; ============================================================

(defcfun ("wasm_byte_vec_new" %wasm-byte-vec-new) :void
  (vec :pointer)
  (size :size)
  (data :pointer))

(defcfun ("wasm_byte_vec_new_empty" %wasm-byte-vec-new-empty) :void
  (vec :pointer))

(defcfun ("wasm_byte_vec_new_uninitialized" %wasm-byte-vec-new-uninitialized)
    :void
  (vec :pointer)
  (size :size))

(defcfun ("wasm_byte_vec_copy" %wasm-byte-vec-copy) :void
  (dst :pointer)
  (src :pointer))

(defcfun ("wasm_byte_vec_delete" %wasm-byte-vec-delete) :void
  (vec :pointer))

(defcfun ("wasm_valtype_vec_new" %wasm-valtype-vec-new) :void
  (vec :pointer)
  (size :size)
  (data :pointer))

(defcfun ("wasm_valtype_vec_new_empty" %wasm-valtype-vec-new-empty) :void
  (vec :pointer))

(defcfun ("wasm_valtype_vec_new_uninitialized"
          %wasm-valtype-vec-new-uninitialized) :void
  (vec :pointer)
  (size :size))

(defcfun ("wasm_valtype_vec_copy" %wasm-valtype-vec-copy) :void
  (dst :pointer)
  (src :pointer))

(defcfun ("wasm_valtype_vec_delete" %wasm-valtype-vec-delete) :void
  (vec :pointer))

(defcfun ("wasm_importtype_vec_delete" %wasm-importtype-vec-delete) :void
  (vec :pointer))

(defcfun ("wasm_exporttype_vec_delete" %wasm-exporttype-vec-delete) :void
  (vec :pointer))

;;; ============================================================
;;; Import/Export Type Functions
;;; ============================================================

(defcfun ("wasm_importtype_module" %wasm-importtype-module) :pointer
  (importtype wasm-importtype-t))

(defcfun ("wasm_importtype_name" %wasm-importtype-name) :pointer
  (importtype wasm-importtype-t))

(defcfun ("wasm_importtype_type" %wasm-importtype-type) wasm-externtype-t
  (importtype wasm-importtype-t))

(defcfun ("wasm_exporttype_name" %wasm-exporttype-name) :pointer
  (exporttype wasm-exporttype-t))

(defcfun ("wasm_exporttype_type" %wasm-exporttype-type) wasm-externtype-t
  (exporttype wasm-exporttype-t))

(defcfun ("wasm_externtype_kind" %wasm-externtype-kind) :uint8
  (externtype wasm-externtype-t))

(defcfun ("wasm_externtype_as_functype" %wasm-externtype-as-functype)
    wasm-functype-t
  (externtype wasm-externtype-t))

(defcfun ("wasm_externtype_as_globaltype" %wasm-externtype-as-globaltype)
    wasm-globaltype-t
  (externtype wasm-externtype-t))

(defcfun ("wasm_externtype_as_tabletype" %wasm-externtype-as-tabletype)
    wasm-tabletype-t
  (externtype wasm-externtype-t))

(defcfun ("wasm_externtype_as_memorytype" %wasm-externtype-as-memorytype)
    wasm-memorytype-t
  (externtype wasm-externtype-t))

;;; ============================================================
;;; WAT Functions
;;; ============================================================

(defcfun ("wasmtime_wat2wasm" %wasmtime-wat2wasm) wasmtime-error-t
  (wat :string)
  (wat-len :size)
  (wasm-out :pointer))

;;; ============================================================
;;; WASI Functions
;;; ============================================================

(defcfun ("wasi_config_new" %wasi-config-new) wasi-config-t)

(defcfun ("wasi_config_delete" %wasi-config-delete) :void
  (config wasi-config-t))

(defcfun ("wasi_config_set_argv" %wasi-config-set-argv) :void
  (config wasi-config-t)
  (argc :int)
  (argv :pointer))

(defcfun ("wasi_config_inherit_argv" %wasi-config-inherit-argv) :void
  (config wasi-config-t))

(defcfun ("wasi_config_set_env" %wasi-config-set-env) :void
  (config wasi-config-t)
  (envc :int)
  (names :pointer)
  (values :pointer))

(defcfun ("wasi_config_inherit_env" %wasi-config-inherit-env) :void
  (config wasi-config-t))

(defcfun ("wasi_config_set_stdin_file" %wasi-config-set-stdin-file) :bool
  (config wasi-config-t)
  (path :string))

(defcfun ("wasi_config_inherit_stdin" %wasi-config-inherit-stdin) :void
  (config wasi-config-t))

(defcfun ("wasi_config_set_stdout_file" %wasi-config-set-stdout-file) :bool
  (config wasi-config-t)
  (path :string))

(defcfun ("wasi_config_inherit_stdout" %wasi-config-inherit-stdout) :void
  (config wasi-config-t))

(defcfun ("wasi_config_set_stderr_file" %wasi-config-set-stderr-file) :bool
  (config wasi-config-t)
  (path :string))

(defcfun ("wasi_config_inherit_stderr" %wasi-config-inherit-stderr) :void
  (config wasi-config-t))

(defcfun ("wasi_config_preopen_dir" %wasi-config-preopen-dir) :bool
  (config wasi-config-t)
  (path :string)
  (guest-path :string))

(defcfun ("wasmtime_context_set_wasi" %wasmtime-context-set-wasi)
    wasmtime-error-t
  (context wasmtime-context-t)
  (wasi wasi-config-t))

;;; ============================================================
;;; Component Model Types
;;; ============================================================

(defctype wasmtime-component-t :pointer)
(defctype wasmtime-component-linker-t :pointer)
(defctype wasmtime-component-linker-instance-t :pointer)

(defcstruct wasmtime-component-instance-t
  (store-id :uint64)
  (index :size))

;;; ============================================================
;;; Component Functions
;;; ============================================================

(defcfun ("wasmtime_component_new" %wasmtime-component-new) wasmtime-error-t
  (engine wasm-engine-t)
  (wasm :pointer)
  (wasm-len :size)
  (component-out :pointer))

(defcfun ("wasmtime_component_delete" %wasmtime-component-delete) :void
  (component wasmtime-component-t))

(defcfun ("wasmtime_component_clone" %wasmtime-component-clone)
    wasmtime-component-t
  (component wasmtime-component-t))

(defcfun ("wasmtime_component_serialize" %wasmtime-component-serialize)
    wasmtime-error-t
  (component wasmtime-component-t)
  (bytes :pointer))

(defcfun ("wasmtime_component_deserialize" %wasmtime-component-deserialize)
    wasmtime-error-t
  (engine wasm-engine-t)
  (bytes :pointer)
  (bytes-len :size)
  (component-out :pointer))

;;; ============================================================
;;; Component Linker Functions
;;; ============================================================

(defcfun ("wasmtime_component_linker_new" %wasmtime-component-linker-new)
    wasmtime-component-linker-t
  (engine wasm-engine-t))

(defcfun ("wasmtime_component_linker_delete" %wasmtime-component-linker-delete)
    :void
  (linker wasmtime-component-linker-t))

(defcfun ("wasmtime_component_linker_root" %wasmtime-component-linker-root)
    :void
  (linker wasmtime-component-linker-t)
  (root-out :pointer))

(defcfun ("wasmtime_component_linker_instantiate"
          %wasmtime-component-linker-instantiate) wasmtime-error-t
  (linker wasmtime-component-linker-t)
  (context wasmtime-context-t)
  (component wasmtime-component-t)
  (instance-out :pointer)
  (trap-out :pointer))

(defcfun ("wasmtime_component_linker_add_wasip2"
          %wasmtime-component-linker-add-wasip2) wasmtime-error-t
  (linker wasmtime-component-linker-t))

;;; ============================================================
;;; Component Linker Instance Functions
;;; ============================================================

(defcfun ("wasmtime_component_linker_instance_add_func"
          %wasmtime-component-linker-instance-add-func) wasmtime-error-t
  (instance wasmtime-component-linker-instance-t)
  (name :string)
  (name-len :size)
  (callback :pointer)
  (env :pointer)
  (finalizer :pointer))

(defcfun ("wasmtime_component_linker_instance_add_instance"
          %wasmtime-component-linker-instance-add-instance) wasmtime-error-t
  (instance wasmtime-component-linker-instance-t)
  (name :string)
  (name-len :size)
  (child-out :pointer))

(defcfun ("wasmtime_component_linker_instance_add_module"
          %wasmtime-component-linker-instance-add-module) wasmtime-error-t
  (instance wasmtime-component-linker-instance-t)
  (name :string)
  (name-len :size)
  (module wasmtime-module-t))

;;; ============================================================
;;; Component Instance Functions
;;; ============================================================

(defcfun ("wasmtime_component_instance_export_get"
          %wasmtime-component-instance-export-get) :bool
  (context wasmtime-context-t)
  (instance :pointer)
  (name :string)
  (name-len :size)
  (func-out :pointer))

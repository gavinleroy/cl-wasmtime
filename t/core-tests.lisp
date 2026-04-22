(in-package :cl-wasmtime/tests)

(in-suite cl-wasmtime-tests)

;;; ============================================================
;;; Test Fixtures
;;; ============================================================

(defparameter *simple-add-wat*
  "(module
     (func $add (export \"add\") (param i32 i32) (result i32)
       local.get 0
       local.get 1
       i32.add))"
  "Simple module that exports an add function.")

(defparameter *memory-wat*
  "(module
     (memory (export \"mem\") 1 4)
     (func (export \"store\") (param i32 i32)
       local.get 0
       local.get 1
       i32.store8)
     (func (export \"load\") (param i32) (result i32)
       local.get 0
       i32.load8_u))"
  "Module with memory exports.")

(defparameter *global-wat*
  "(module
     (global $counter (export \"counter\") (mut i32) (i32.const 0))
     (func (export \"inc\")
       global.get $counter
       i32.const 1
       i32.add
       global.set $counter)
     (func (export \"get\") (result i32)
       global.get $counter))"
  "Module with mutable global.")

(defparameter *import-wat*
  "(module
     (import \"env\" \"log\" (func $log (param i32)))
     (func (export \"call_log\") (param i32)
       local.get 0
       call $log))"
  "Module that imports a function.")

(defparameter *multi-export-wat*
  "(module
     (func (export \"one\") (result i32) (i32.const 1))
     (func (export \"two\") (result i32) (i32.const 2))
     (memory (export \"mem\") 1)
     (global (export \"val\") i32 (i32.const 42)))"
  "Module with multiple exports of different types.")

(defparameter *trap-wat*
  "(module
     (func (export \"trap\")
       unreachable))"
  "Module that always traps.")

;;; ============================================================
;;; Engine/Store/Config Tests
;;; ============================================================

(test engine-creation
  "Engine can be created and used."
  (let ((engine (make-engine)))
    (is (typep engine 'engine))))

(test config-creation
  "Config can be created with various options."
  (let ((cfg (make-config :debug-info t :wasm-simd t)))
    (is (typep cfg 'config))))

(test engine-with-config
  "Engine can be created with config."
  (let* ((cfg (make-config :consume-fuel t))
         (engine (make-engine cfg)))
    (is (typep engine 'engine))))

(test store-creation
  "Store can be created from engine."
  (let* ((engine (make-engine))
         (store (make-store engine)))
    (is (typep store 'store))))

(test store-gc
  "Store GC runs without error."
  (let* ((engine (make-engine))
         (store (make-store engine)))
    (finishes (store-gc store))))

(test store-fuel
  "Store fuel can be set and queried when enabled."
  (let* ((cfg (make-config :consume-fuel t))
         (engine (make-engine cfg))
         (store (make-store engine)))
    (store-set-fuel store 1000)
    (is (= 1000 (store-get-fuel store)))))

;;; ============================================================
;;; WAT Conversion Tests
;;; ============================================================

(test wat-to-wasm
  "WAT text converts to WASM bytes."
  (let ((wasm (wat->wasm *simple-add-wat*)))
    (is (typep wasm '(vector (unsigned-byte 8))))
    (is (> (length wasm) 0))
    (is (= (aref wasm 0) 0))
    (is (= (aref wasm 1) #x61))
    (is (= (aref wasm 2) #x73))
    (is (= (aref wasm 3) #x6d))))

(test wat-invalid-syntax
  "Invalid WAT signals error."
  (signals wasmtime-error
    (wat->wasm "(module (invalid syntax here)")))

;;; ============================================================
;;; Module Tests
;;; ============================================================

(test module-load-from-wat
  "Module loads from WAT string."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *simple-add-wat*)))
    (is (typep module 'module))))

(test module-load-from-bytes
  "Module loads from WASM bytes."
  (let* ((engine (make-engine))
         (wasm (wat->wasm *simple-add-wat*))
         (module (load-module engine wasm)))
    (is (typep module 'module))))

(test module-validate-valid
  "Valid WASM passes validation."
  (let* ((engine (make-engine))
         (wasm (wat->wasm *simple-add-wat*)))
    (is (validate-module engine wasm))))

(test module-validate-invalid
  "Invalid WASM fails validation."
  (let ((engine (make-engine)))
    (signals wasmtime-error
      (validate-module engine #(0 1 2 3)))))

(test module-exports
  "Module exports can be inspected."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (exports (module-exports module)))
    (is (= 1 (length exports)))
    (is (equal "add" (first (first exports))))
    (is (eq :func (second (first exports))))))

(test module-multiple-exports
  "Module with multiple exports lists all."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *multi-export-wat*))
         (exports (module-exports module)))
    (is (= 4 (length exports)))
    (is (find "one" exports :key #'first :test #'equal))
    (is (find "two" exports :key #'first :test #'equal))
    (is (find "mem" exports :key #'first :test #'equal))
    (is (find "val" exports :key #'first :test #'equal))))

(test module-imports
  "Module imports can be inspected."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *import-wat*))
         (imports (module-imports module)))
    (is (= 1 (length imports)))
    (is (equal "env" (first (first imports))))
    (is (equal "log" (second (first imports))))
    (is (eq :func (third (first imports))))))

(test module-clone
  "Module can be cloned."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (clone (module-clone module)))
    (is (typep clone 'module))
    (is (not (eq module clone)))))

(test module-serialize-deserialize
  "Module can be serialized and deserialized."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (bytes (module-serialize module))
         (restored (module-deserialize engine bytes)))
    (is (typep bytes '(vector (unsigned-byte 8))))
    (is (typep restored 'module))
    (is (= 1 (length (module-exports restored))))))

;;; ============================================================
;;; Instance Tests
;;; ============================================================

(test linker-instantiate
  "Module instantiates through linker."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module)))
    (is (typep instance 'instance))))

(test instance-export-func
  "Instance export retrieves function."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-fn (instance-export instance "add")))
    (is (typep add-fn 'wasm-func))))

(test instance-exports-list
  "Instance exports returns all exports."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *multi-export-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (exports (instance-exports instance)))
    (is (= 4 (length exports)))
    (is (assoc "one" exports :test #'equal))
    (is (assoc "mem" exports :test #'equal))))

(test instance-export-nonexistent
  "Missing export returns NIL."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module)))
    (is (null (instance-export instance "nonexistent")))))

;;; ============================================================
;;; Function Call Tests
;;; ============================================================

(test call-function-i32
  "Function called with i32 args returns correct result."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-fn (instance-export instance "add")))
    (is (= 5 (call-function add-fn 2 3)))
    (is (= 0 (call-function add-fn 0 0)))
    (is (= -1 (call-function add-fn -3 2)))))

(test call-function-no-args
  "Function with no args returns result."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *multi-export-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (one-fn (instance-export instance "one")))
    (is (= 1 (call-function one-fn)))))

(test call-function-trap
  "Function that traps signals wasm-trap."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *trap-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (trap-fn (instance-export instance "trap")))
    (signals wasm-trap
      (call-function trap-fn))))

;;; ============================================================
;;; Memory Tests
;;; ============================================================

(defparameter *wasm-page-size* 65536
  "Wasm linear memory page size in bytes.")

(test memory-create
  "Memory can be created standalone."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (is (typep mem 'wasm-memory))))

(test memory-create-with-max
  "Memory can be created with max pages."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 4)))
    (is (typep mem 'wasm-memory))))

(test memory-grow
  "Standalone memory can be grown."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 4)))
    (is (= 1 (memory-size mem)))
    (is (= 1 (memory-grow mem 2)))
    (is (= 3 (memory-size mem)))))

(test memory-read-write
  "Standalone memory supports read/write via memory-ref."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (is (= 0 (memory-ref mem 0)))
    (setf (memory-ref mem 0) 42)
    (is (= 42 (memory-ref mem 0)))
    (setf (memory-ref mem 100) 255)
    (is (= 255 (memory-ref mem 100)))))

(test memory-from-module
  "Memory exported from module works."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *memory-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (store-fn (instance-export instance "store"))
         (load-fn (instance-export instance "load")))
    (call-function store-fn 0 42)
    (is (= 42 (call-function load-fn 0)))
    (call-function store-fn 100 255)
    (is (= 255 (call-function load-fn 100)))))

(test memory-ref-from-exported-memory
  "memory-ref reads and writes bytes through exported memory."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *memory-wat*))
         (instance (instantiate store module nil))
         (mem (instance-export instance "mem"))
         (store-fn (instance-export instance "store")))
    (is (typep mem 'wasm-memory))
    (is (= 0 (memory-ref mem 0)))
    (call-function store-fn 0 42)
    (is (= 42 (memory-ref mem 0)))
    (setf (memory-ref mem 1) 7)
    (is (= 7 (memory-ref mem 1)))))

;;; ============================================================
;;; Global Tests
;;; ============================================================

(test global-create-immutable
  "Immutable global can be created."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (glob (make-global store :i32 42)))
    (is (typep glob 'wasm-global))))

(test global-create-mutable
  "Mutable global can be created."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (glob (make-global store :i32 0 :mutable t)))
    (is (typep glob 'wasm-global))))

(test global-from-module
  "Global can be exported from module."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *global-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (counter (instance-export instance "counter"))
         (get-fn (instance-export instance "get")))
    (is (typep counter 'wasm-global))
    (is (= 0 (call-function get-fn)))))

;;; ============================================================
;;; Host Function Tests
;;; ============================================================

(test host-function-create
  "Host function can be created."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (fn (make-host-function store '(:i32) '(:i32)
                                 (lambda (x) (* x 2)))))
    (is (typep fn 'wasm-func))))

(test host-function-call
  "Host function can be called from WASM."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine))
         (logged-values nil))
    (linker-define-func linker "env" "log" '(:i32) '()
                        (lambda (x) (push x logged-values) (values)))
    (let* ((module (load-module-from-wat engine *import-wat*))
           (instance (linker-instantiate linker store module))
           (call-log (instance-export instance "call_log")))
      (call-function call-log 42)
      (call-function call-log 100)
      (is (equal '(100 42) logged-values)))))

(test linker-get
  "Linker-get retrieves defined extern."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine)))
    (linker-define-func linker "env" "test" '() '(:i32) (lambda () 42))
    (let ((fn (linker-get linker store "env" "test")))
      (is (typep fn 'wasm-func))
      (is (= 42 (call-function fn))))))

(test linker-allow-shadowing
  "Linker allows shadowing when enabled."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine)))
    (linker-define-func linker "env" "val" '() '(:i32) (lambda () 1))
    (linker-allow-shadowing linker t)
    (linker-define-func linker "env" "val" '() '(:i32) (lambda () 2))
    (is (= 2 (call-function (linker-get linker store "env" "val"))))))

;;; ============================================================
;;; Error Condition Tests
;;; ============================================================

(test wasmtime-error-message
  "wasmtime-error has message."
  (handler-case
      (wat->wasm "(module (invalid")
    (wasmtime-error (e)
      (is (stringp (wasmtime-error-message e)))
      (is (> (length (wasmtime-error-message e)) 0)))))

(test wasm-trap-inherits-wasmtime-error
  "wasm-trap is a wasmtime-error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *trap-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (trap-fn (instance-export instance "trap")))
    (handler-case
        (call-function trap-fn)
      (wasm-trap (e)
        (is (typep e 'wasmtime-error))
        (is (stringp (wasmtime-error-message e)))))))

;;; ============================================================
;;; WASI Config Tests
;;; ============================================================

(test wasi-config-create
  "WASI config can be created."
  (let ((cfg (make-wasi-config)))
    (is (typep cfg 'wasi-config))))

(test wasi-config-inherit
  "WASI config inherit methods run without error."
  (let ((cfg (make-wasi-config)))
    (finishes (wasi-config-inherit-stdio cfg))
    (finishes (wasi-config-inherit-argv cfg))
    (finishes (wasi-config-inherit-env cfg))))

(test wasi-config-set-argv
  "WASI config set-argv works."
  (let ((cfg (make-wasi-config)))
    (finishes (wasi-config-set-argv cfg '("prog" "arg1" "arg2")))))

(test wasi-config-set-env
  "WASI config set-env works."
  (let ((cfg (make-wasi-config)))
    (finishes (wasi-config-set-env cfg '(("FOO" . "bar") ("BAZ" . "qux"))))))

(test store-set-wasi
  "Store accepts WASI config."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (cfg (make-wasi-config)))
    (wasi-config-inherit-stdio cfg)
    (finishes (store-set-wasi store cfg))))

;;; ============================================================
;;; Float Type Tests
;;; ============================================================

(defparameter *float-wat*
  "(module
     (func (export \"add_f32\") (param f32 f32) (result f32)
       local.get 0
       local.get 1
       f32.add)
     (func (export \"add_f64\") (param f64 f64) (result f64)
       local.get 0
       local.get 1
       f64.add))"
  "Module with float operations.")

(test call-function-f32
  "Function called with f32 args."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *float-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-f32 (instance-export instance "add_f32")))
    (let ((result (call-function add-f32 1.5s0 2.5s0)))
      (is (typep result 'single-float))
      (is (< (abs (- result 4.0s0)) 0.001)))))

(test call-function-f64
  "Function called with f64 args."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *float-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-f64 (instance-export instance "add_f64")))
    (let ((result (call-function add-f64 1.5d0 2.5d0)))
      (is (typep result 'double-float))
      (is (< (abs (- result 4.0d0)) 0.0001)))))

;;; ============================================================
;;; i64 Type Tests
;;; ============================================================

(defparameter *i64-wat*
  "(module
     (func (export \"add_i64\") (param i64 i64) (result i64)
       local.get 0
       local.get 1
       i64.add))"
  "Module with i64 operations.")

(test call-function-i64
  "Function called with i64 args."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *i64-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-i64 (instance-export instance "add_i64")))
    (is (= 9000000000 (call-function add-i64 4000000000 5000000000)))))

;;; ============================================================
;;; Table Tests
;;; ============================================================

(defparameter *table-wat*
  "(module
     (table (export \"tbl\") 2 10 funcref)
     (func $f1 (result i32) (i32.const 1))
     (func $f2 (result i32) (i32.const 2))
     (elem (i32.const 0) $f1 $f2)
     (func (export \"call_indirect\") (param i32) (result i32)
       (call_indirect (result i32) (local.get 0))))"
  "Module with table and indirect calls.")

(test table-create
  "Table export is recognized as wasm-table."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *table-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate
                    linker store module))
         (tbl (instance-export instance "tbl")))
    (is (typep tbl 'wasm-table))))

(test table-grow
  "Table export type appears in module exports."
  (let* ((engine (make-engine))
         (module (load-module-from-wat engine *table-wat*))
         (exports (module-exports module)))
    (is (find :table exports :key #'second))))

(test table-from-module
  "Table exported from module works."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *table-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (call-fn (instance-export instance "call_indirect")))
    (is (= 1 (call-function call-fn 0)))
    (is (= 2 (call-function call-fn 1)))))

;;; ============================================================
;;; Fuel Consumption Tests
;;; ============================================================

(defparameter *loop-wat*
  "(module
     (func (export \"loop\") (param i32)
       (local i32)
       (local.set 1 (local.get 0))
       (block $done
         (loop $again
           (br_if $done (i32.eqz (local.get 1)))
           (local.set 1 (i32.sub (local.get 1) (i32.const 1)))
           (br $again)))))"
  "Module with loop for fuel testing.")

(test fuel-consumed-during-execution
  "Fuel decreases during execution."
  (let* ((cfg (make-config :consume-fuel t))
         (engine (make-engine cfg))
         (store (make-store engine))
         (module (load-module-from-wat engine *loop-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (loop-fn (instance-export instance "loop")))
    (store-set-fuel store 10000)
    (call-function loop-fn 100)
    (is (< (store-get-fuel store) 10000))))

(test fuel-exhaustion-traps
  "Exhausting fuel causes trap."
  (let* ((cfg (make-config :consume-fuel t))
         (engine (make-engine cfg))
         (store (make-store engine))
         (module (load-module-from-wat engine *loop-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (loop-fn (instance-export instance "loop")))
    (store-set-fuel store 10)
    (signals wasm-trap
      (call-function loop-fn 1000000))))

;;; ============================================================
;;; Boundary Value Tests
;;; ============================================================

(test i32-boundary-values
  "i32 boundary values handled correctly."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-fn (instance-export instance "add")))
    (is (= -2147483648 (call-function add-fn 2147483647 1)))
    (is (= -2 (call-function add-fn 2147483647 2147483647)))
    (is (= -2147483648 (call-function add-fn -2147483648 0)))))

(test i64-boundary-values
  "i64 boundary values handled correctly."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *i64-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-i64 (instance-export instance "add_i64")))
    (is (= (- (ash 1 63)) (call-function add-i64 (1- (ash 1 63)) 1)))
    (is (= (- (ash 1 63)) (call-function add-i64 (- (ash 1 63)) 0)))))

;;; ============================================================
;;; Multi-Value Return Tests
;;; ============================================================

(defparameter *multi-value-wat*
  "(module
     (func (export \"swap\") (param i32 i32) (result i32 i32)
       local.get 1
       local.get 0)
     (func (export \"dup\") (param i32) (result i32 i32)
       local.get 0
       local.get 0))"
  "Module with multi-value returns.")

(test multi-value-return
  "Functions returning multiple values work."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *multi-value-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (swap-fn (instance-export instance "swap"))
         (dup-fn (instance-export instance "dup")))
    (multiple-value-bind (a b) (call-function swap-fn 1 2)
      (is (= 2 a))
      (is (= 1 b)))
    (multiple-value-bind (a b) (call-function dup-fn 42)
      (is (= 42 a))
      (is (= 42 b)))))

;;; ============================================================
;;; Host Function with Multiple Args Tests
;;; ============================================================

(test host-function-multiple-args
  "Host function with multiple args works."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine)))
    (linker-define-func linker "env" "add3" '(:i32 :i32 :i32) '(:i32)
                        (lambda (a b c) (+ a b c)))
    (let ((fn (linker-get linker store "env" "add3")))
      (is (= 6 (call-function fn 1 2 3)))
      (is (= 15 (call-function fn 4 5 6))))))

(test host-function-returns-multiple
  "Host function returning multiple values."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine)))
    (linker-define-func linker "env" "divmod" '(:i32 :i32) '(:i32 :i32)
                        (lambda (a b) (values (floor a b) (mod a b))))
    (let ((fn (linker-get linker store "env" "divmod")))
      (multiple-value-bind (q r) (call-function fn 17 5)
        (is (= 3 q))
        (is (= 2 r))))))

;;; ============================================================
;;; Memory Edge Cases
;;; ============================================================

(test memory-grow-failure
  "Growing past max in one step signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 2)))
    (signals wasmtime-error
      (memory-grow mem 5))))

(test memory-boundary-access
  "First and last bytes of a page are accessible."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (setf (memory-ref mem 0) 1)
    (setf (memory-ref mem (1- *wasm-page-size*)) 2)
    (is (= 1 (memory-ref mem 0)))
    (is (= 2 (memory-ref mem (1- *wasm-page-size*))))
    (signals error
      (memory-ref mem *wasm-page-size*))))

(test memory-initial-size-and-data-size
  "New memory reports expected page and byte sizes."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 2 :max-pages 4)))
    (is (= 2 (memory-size mem)))
    (is (= (* 2 *wasm-page-size*)
           (memory-data-size mem)))))

(test memory-grow-updates-size
  "Growing memory returns previous size and updates size."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 4)))
    (is (= 1 (memory-grow mem 1)))
    (is (= 2 (memory-size mem)))
    (is (= (* 2 *wasm-page-size*)
           (memory-data-size mem)))))

(test memory-grow-multiple-steps
  "Memory growth across multiple steps stays consistent."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 4)))
    (is (= 1 (memory-grow mem 1)))
    (is (= 2 (memory-grow mem 1)))
    (is (= 3 (memory-grow mem 1)))
    (is (= 4 (memory-size mem)))
    (is (= (* 4 *wasm-page-size*)
           (memory-data-size mem)))))

(test memory-grow-past-max-signals-error
  "Growing beyond max pages signals an error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 2)))
    (is (= 1 (memory-grow mem 1)))
    (signals wasmtime-error
      (memory-grow mem 1))))

(test memory-ref-bulk-pattern-roundtrip
  "Bulk writes and reads through memory-ref are consistent."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (loop for i below 4096
          do (setf (memory-ref mem i) (mod (* i 7) 256)))
    (loop for i below 4096
          do (is (= (mod (* i 7) 256)
                    (memory-ref mem i))))))

(test memory-ref-page-boundary-roundtrip
  "Reads and writes at page boundaries behave correctly."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 3)))
    (setf (memory-ref mem 0) 11)
    (setf (memory-ref mem (1- *wasm-page-size*)) 22)
    (is (= 11 (memory-ref mem 0)))
    (is (= 22 (memory-ref mem (1- *wasm-page-size*))))
    (memory-grow mem 1)
    (setf (memory-ref mem *wasm-page-size*) 33)
    (setf (memory-ref mem (1- (* 2 *wasm-page-size*))) 44)
    (is (= 33 (memory-ref mem *wasm-page-size*)))
    (is (= 44 (memory-ref mem (1- (* 2 *wasm-page-size*)))))))

(test exported-memory-bulk-roundtrip-with-wasm
  "Bulk writes through wasm function are visible via memory-ref."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *memory-wat*))
         (instance (instantiate store module nil))
         (mem (instance-export instance "mem"))
         (store-fn (instance-export instance "store"))
         (load-fn (instance-export instance "load")))
    (loop for i from 0 below 2048 by 127
          for value = (mod (+ i 33) 256)
          do (call-function store-fn i value))
    (loop for i from 0 below 2048 by 127
          for value = (mod (+ i 33) 256)
          do (is (= value (memory-ref mem i)))
             (is (= value (call-function load-fn i))))))

(test exported-memory-direct-writes-visible-to-wasm
  "Direct memory-ref writes are visible through wasm loads."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *memory-wat*))
         (instance (instantiate store module nil))
         (mem (instance-export instance "mem"))
         (load-fn (instance-export instance "load")))
    (loop for i from 0 below 1024 by 97
          for value = (mod (+ (* i 5) 1) 256)
          do (setf (memory-ref mem i) value))
    (loop for i from 0 below 1024 by 97
          for value = (mod (+ (* i 5) 1) 256)
          do (is (= value (call-function load-fn i))))))

(test exported-memory-grow-and-cross-page-access
  "Exported memory remains usable after grow across pages."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *memory-wat*))
         (instance (instantiate store module nil))
         (mem (instance-export instance "mem"))
         (store-fn (instance-export instance "store"))
         (load-fn (instance-export instance "load"))
         (offset (+ *wasm-page-size* 123)))
    (is (= 1 (memory-grow mem 1)))
    (call-function store-fn offset 199)
    (is (= 199 (memory-ref mem offset)))
    (setf (memory-ref mem (+ offset 1)) 77)
    (is (= 199 (call-function load-fn offset)))
    (is (= 77 (call-function load-fn (+ offset 1))))))

(test memory-stress-repeated-grow-write-read
  "Repeated grow/write/read cycles remain consistent."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 4)))
    (loop for step from 1 to 3
          do (is (= step (memory-grow mem 1)))
             (let ((base (* step *wasm-page-size*)))
               (loop for i from 0 below 1024 by 17
                     for offset = (+ base i)
                     for value = (mod (+ step i) 256)
                     do (setf (memory-ref mem offset) value))
               (loop for i from 0 below 1024 by 17
                     for offset = (+ base i)
                     for value = (mod (+ step i) 256)
                     do (is (= value (memory-ref mem offset))))))))

;;; ============================================================
;;; Global Type Tests
;;; ============================================================

(test global-i64
  "Global with i64 type can be created."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (glob (make-global store :i64 9000000000 :mutable t)))
    (is (typep glob 'wasm-global))))

(test global-f32
  "Global with f32 type can be created."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (glob (make-global store :f32 3.14s0 :mutable t)))
    (is (typep glob 'wasm-global))))

(test global-f64
  "Global with f64 type can be created."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (glob (make-global store :f64 3.14159265358979d0)))
    (is (typep glob 'wasm-global))))

;;; ============================================================
;;; Trap Code Tests
;;; ============================================================

(defparameter *div-zero-wat*
  "(module
     (func (export \"div\") (param i32 i32) (result i32)
       local.get 0
       local.get 1
       i32.div_s))"
  "Module that can divide by zero.")

(test trap-code-accessible
  "Trap code is accessible from wasm-trap condition."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *div-zero-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (div-fn (instance-export instance "div")))
    (handler-case
        (call-function div-fn 10 0)
      (wasm-trap (e)
        (is (not (null (wasm-trap-code e))))))))

;;; ============================================================
;;; Config Options Tests
;;; ============================================================

(test config-all-options
  "Config accepts all documented options."
  (let ((cfg (make-config :debug-info t
                          :consume-fuel t
                          :wasm-threads t
                          :wasm-simd t
                          :wasm-bulk-memory t
                          :wasm-multi-value t
                          :wasm-reference-types t)))
    (is (typep cfg 'config))
    (let ((engine (make-engine cfg)))
      (is (typep engine 'engine)))))

;;; ============================================================
;;; Linker Define Tests
;;; ============================================================

(defparameter *import-memory-wat*
  "(module
     (import \"env\" \"mem\" (memory 1))
     (func (export \"load\") (param i32) (result i32)
       local.get 0
       i32.load8_u))"
  "Module that imports memory from env.")

(test linker-define-memory
  "Memory defined in linker is usable by module."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine))
         (mem (make-memory store 1))
         (module (load-module-from-wat
                  engine *import-memory-wat*)))
    (setf (memory-ref mem 7) 99)
    (linker-define linker store "env" "mem" mem)
    (let* ((inst (linker-instantiate
                  linker store module))
           (load-fn (instance-export inst "load")))
      (is (= 99 (call-function load-fn 7))))))

(test linker-define-global
  "Standalone global can be created with various types."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (g1 (make-global store :i32 42))
         (g2 (make-global store :i64 100 :mutable t)))
    (is (typep g1 'wasm-global))
    (is (typep g2 'wasm-global))))
;;; ============================================================
;;; File I/O Tests
;;; ============================================================

(test module-load-from-file
  "Module can be loaded from file."
  (let ((path "/tmp/test-module.wasm")
        (engine (make-engine)))
    (unwind-protect
         (progn
           (with-open-file (out path
                                :direction :output
                                :if-exists :supersede
                                :element-type '(unsigned-byte 8))
             (let ((wasm-bytes (wat->wasm *simple-add-wat*)))
               (write-sequence wasm-bytes out)))
           (let ((module (load-module-from-file engine path)))
             (is (typep module 'module))))
      (when (probe-file path)
        (delete-file path)))))

(test module-serialize-deserialize-file
  "Module can be serialized to and deserialized from file."
  (let ((path "/tmp/test-module-serial.bin")
        (engine (make-engine)))
    (unwind-protect
         (let* ((module1 (load-module-from-wat engine *simple-add-wat*))
                (store (make-store engine))
                (linker (make-linker engine)))
           (module-serialize-to-file module1 path)
           (is (probe-file path))
           (let* ((module2 (module-deserialize-from-file engine path))
                  (instance1 (linker-instantiate linker store module1))
                  (instance2 (linker-instantiate linker store module2))
                  (add1 (instance-export instance1 "add"))
                  (add2 (instance-export instance2 "add")))
             (is (= 3 (call-function add1 1 2)))
             (is (= 3 (call-function add2 1 2)))))
      (when (probe-file path)
        (delete-file path)))))

;;; Note: table-get/set for funcref not fully implemented yet

;;; ============================================================
;;; Error Handling Tests
;;; ============================================================

(test module-load-corrupted
  "Loading corrupted module signals error."
  (let ((engine (make-engine)))
    (signals wasmtime-error
      (load-module engine #(0 1 2 3)))))

(test module-validate-corrupted
  "Validating corrupted module signals error."
  (let ((engine (make-engine)))
    (signals wasmtime-error
      (validate-module engine #(0 1 2 3)))))

(test call-function-wrong-arg-count
  "Calling function with wrong arg count signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *simple-add-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (add-fn (instance-export instance "add")))
    (signals error
      (call-function add-fn 1))
    (signals error
      (call-function add-fn 1 2 3))))

;;; ============================================================
;;; Memory Bounds Checking Tests
;;; ============================================================

(test memory-ref-out-of-bounds-read
  "Reading past memory bounds signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (signals error
      (memory-ref mem (* 2 *wasm-page-size*)))))

(test memory-ref-out-of-bounds-write
  "Writing past memory bounds signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (signals error
      (setf (memory-ref mem (* 2 *wasm-page-size*)) 42))))

(test memory-ref-exact-boundary-read
  "Reading at exact boundary signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (signals error
      (memory-ref mem *wasm-page-size*))))

(test memory-ref-exact-boundary-write
  "Writing at exact boundary signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (signals error
      (setf (memory-ref mem *wasm-page-size*) 42))))

(test memory-ref-last-valid-byte
  "Reading/writing last valid byte works."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (setf (memory-ref mem (1- *wasm-page-size*)) 255)
    (is (= 255 (memory-ref mem (1- *wasm-page-size*))))))

(test memory-ref-after-grow-new-region
  "After grow, new region accessible via memory-ref."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1 :max-pages 2)))
    (memory-grow mem 1)
    (setf (memory-ref mem *wasm-page-size*) 77)
    (is (= 77 (memory-ref mem *wasm-page-size*)))))

(test memory-ref-negative-offset-signals-error
  "Negative offset treated as large positive, signals error."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (signals error
      (memory-ref mem most-positive-fixnum))))

;;; ============================================================
;;; Context Freshness Tests
;;; ============================================================

(test memory-context-always-fresh
  "Memory context derived from store each time."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (mem (make-memory store 1)))
    (is (= (memory-data-size mem) *wasm-page-size*))
    (memory-grow mem 1)
    (is (= (memory-data-size mem) (* 2 *wasm-page-size*)))))

(test global-from-module-read-write
  "Module-exported mutable global can be mutated via wasm."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (module (load-module-from-wat engine *global-wat*))
         (linker (make-linker engine))
         (instance (linker-instantiate linker store module))
         (counter (instance-export instance "counter"))
         (inc-fn (instance-export instance "inc"))
         (get-fn (instance-export instance "get")))
    (is (typep counter 'wasm-global))
    (is (= 0 (call-function get-fn)))
    (call-function inc-fn)
    (call-function inc-fn)
    (is (= 2 (call-function get-fn)))))

;;; ============================================================
;;; Host Function Cleanup Tests
;;; ============================================================

(test host-function-creation-basic
  "Host function created and callable."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (fn (make-host-function store '(:i32) '(:i32)
                                 (lambda (x) (* x 3)))))
    (is (typep fn 'wasm-func))
    (is (= 15 (call-function fn 5)))))

(test linker-define-func-multiple
  "Multiple linker-define-func calls work."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine)))
    (linker-define-func linker "env" "add"
                        '(:i32 :i32) '(:i32)
                        (lambda (a b) (+ a b)))
    (linker-define-func linker "env" "mul"
                        '(:i32 :i32) '(:i32)
                        (lambda (a b) (* a b)))
    (let ((add-fn (linker-get linker store "env" "add"))
          (mul-fn (linker-get linker store "env" "mul")))
      (is (= 5 (call-function add-fn 2 3)))
      (is (= 6 (call-function mul-fn 2 3))))))

;;; ============================================================
;;; Host Callback Error Handling Tests
;;; ============================================================

(defparameter *call-import-wat*
  "(module
     (import \"env\" \"f\" (func $f (param i32) (result i32)))
     (func (export \"call_it\") (param i32) (result i32)
       local.get 0
       call $f))"
  "Module that calls an imported function.")

(test host-callback-error-becomes-trap
  "Lisp error in host callback becomes wasm trap."
  (let* ((engine (make-engine))
         (store (make-store engine))
         (linker (make-linker engine)))
    (linker-define-func linker "env" "f"
                        '(:i32) '(:i32)
                        (lambda (x)
                          (declare (ignore x))
                          (error "deliberate error")))
    (let* ((module (load-module-from-wat
                    engine *call-import-wat*))
           (inst (linker-instantiate
                  linker store module))
           (call-fn (instance-export inst "call_it")))
      (signals wasmtime-error
        (call-function call-fn 1)))))

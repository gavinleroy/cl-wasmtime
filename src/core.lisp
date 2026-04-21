(in-package :cl-wasmtime)

;;; ============================================================
;;; Error Conditions
;;; ============================================================

(define-condition wasmtime-error (error)
  ((message :initarg :message
            :reader wasmtime-error-message))
  (:report (lambda (c s)
             (format s "Wasmtime error: ~A" (wasmtime-error-message c)))))

(define-condition wasm-trap (wasmtime-error)
  ((code :initarg :code
         :reader wasm-trap-code))
  (:report (lambda (c s)
             (format s "WASM trap (~A): ~A"
                     (wasm-trap-code c) (wasmtime-error-message c)))))

(defun check-wasmtime-error (err-ptr &optional trap-ptr)
  "Signal condition if error or trap occurred."
  (let ((trap-msg nil) (trap-code nil) (err-msg nil))
    (when (and trap-ptr (not (null-pointer-p trap-ptr)))
      (let ((trap (mem-ref trap-ptr :pointer)))
        (unless (null-pointer-p trap)
          (setf trap-msg (extract-trap-message trap)
                trap-code (extract-trap-code trap))
          (%wasm-trap-delete trap))))
    (unless (null-pointer-p err-ptr)
      (setf err-msg (extract-error-message err-ptr))
      (%wasmtime-error-delete err-ptr))
    (when trap-msg
      (error 'wasm-trap :message trap-msg :code trap-code))
    (when err-msg
      (error 'wasmtime-error :message err-msg))))

(defun extract-error-message (err-ptr)
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (%wasmtime-error-message err-ptr vec)
    (let* ((size (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'size))
           (data (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'data))
           (msg (foreign-string-to-lisp data :count size)))
      (%wasm-byte-vec-delete vec)
      msg)))

(defun extract-trap-message (trap-ptr)
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (%wasm-trap-message trap-ptr vec)
    (let* ((size (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'size))
           (data (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'data))
           (msg (foreign-string-to-lisp data :count size)))
      (%wasm-byte-vec-delete vec)
      msg)))

(defun extract-trap-code (trap-ptr)
  (with-foreign-object (code :uint8)
    (if (%wasmtime-trap-code trap-ptr code)
        (mem-ref code :uint8)
        nil)))

;;; ============================================================
;;; CONFIG
;;; ============================================================

(defclass config ()
  ((pointer :initarg :pointer
            :reader config-pointer)))

(defun make-config (&key debug-info consume-fuel wasm-threads wasm-simd
                         wasm-bulk-memory wasm-multi-value
                         wasm-reference-types)
  "Create engine configuration with optional settings."
  (let* ((ptr (%wasm-config-new))
         (cfg (make-instance 'config :pointer ptr)))
    (when debug-info
      (%wasmtime-config-debug-info-set ptr t))
    (when consume-fuel
      (%wasmtime-config-consume-fuel-set ptr t))
    (when wasm-threads
      (%wasmtime-config-wasm-threads-set ptr t))
    (when wasm-simd
      (%wasmtime-config-wasm-simd-set ptr t))
    (when wasm-bulk-memory
      (%wasmtime-config-wasm-bulk-memory-set ptr t))
    (when wasm-multi-value
      (%wasmtime-config-wasm-multi-value-set ptr t))
    (when wasm-reference-types
      (%wasmtime-config-wasm-reference-types-set ptr t))
    (tg:finalize cfg (lambda () (%wasm-config-delete ptr)))
    cfg))

;;; ============================================================
;;; ENGINE
;;; ============================================================

(defclass engine ()
  ((pointer :initarg :pointer
            :reader engine-pointer)))

(defun make-engine (&optional config)
  "Create new Wasmtime engine, optionally with config."
  (let* ((ptr (if config
                  (let* ((cfg-ptr (config-pointer config))
                         (eng-ptr (%wasm-engine-new-with-config cfg-ptr)))
                    (when (null-pointer-p eng-ptr)
                      (error "Failed to create engine"))
                    (tg:cancel-finalization config)
                    eng-ptr)
                  (%wasm-engine-new)))
         (engine (make-instance 'engine :pointer ptr)))
    (tg:finalize engine (lambda () (%wasm-engine-delete ptr)))
    engine))

;;; ============================================================
;;; STORE
;;; ============================================================

(defclass store ()
  ((pointer :initarg :pointer
            :reader store-pointer)
   (engine :initarg :engine
           :reader store-engine)))

(defun make-store (engine)
  "Create new store attached to engine."
  (let* ((ptr (%wasmtime-store-new (engine-pointer engine)
                                   (null-pointer) (null-pointer)))
         (store (make-instance 'store :pointer ptr :engine engine)))
    (tg:finalize store (lambda () (%wasmtime-store-delete ptr)))
    store))

(defun store-context (store)
  "Get context pointer for store."
  (%wasmtime-store-context (store-pointer store)))

(defun store-gc (store)
  "Run garbage collection in store."
  (%wasmtime-context-gc (store-context store)))

(defun store-set-fuel (store amount)
  "Set fuel for store (requires consume-fuel config)."
  (let ((err (%wasmtime-context-set-fuel (store-context store) amount)))
    (check-wasmtime-error err)))

(defun store-get-fuel (store)
  "Get remaining fuel in store."
  (with-foreign-object (fuel :uint64)
    (let ((err (%wasmtime-context-get-fuel (store-context store) fuel)))
      (check-wasmtime-error err)
      (mem-ref fuel :uint64))))

;;; ============================================================
;;; MODULE
;;; ============================================================

(defclass module ()
  ((pointer :initarg :pointer
            :reader module-pointer)
   (engine :initarg :engine
           :reader module-engine)))

(defun load-module (engine bytes)
  "Load module from WASM bytes (vector of (unsigned-byte 8))."
  (let ((len (length bytes)))
    (with-foreign-object (module-out :pointer)
      (with-foreign-object (wasm :uint8 len)
        (loop for i below len
              do (setf (mem-aref wasm :uint8 i) (aref bytes i)))
        (let ((err (%wasmtime-module-new (engine-pointer engine)
                                         wasm len module-out)))
          (check-wasmtime-error err)
          (let* ((ptr (mem-ref module-out :pointer))
                 (mod (make-instance 'module :pointer ptr :engine engine)))
            (tg:finalize mod (lambda () (%wasmtime-module-delete ptr)))
            mod))))))

(defun load-module-from-file (engine path)
  "Load module from .wasm file path."
  (let ((bytes (read-file-into-byte-vector path)))
    (load-module engine bytes)))

(defun read-file-into-byte-vector (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let* ((len (file-length stream))
           (vec (make-array len :element-type '(unsigned-byte 8))))
      (read-sequence vec stream)
      vec)))

(defun load-module-from-wat (engine wat-string)
  "Load module from WAT text format."
  (let ((wasm-bytes (wat->wasm wat-string)))
    (load-module engine wasm-bytes)))

(defun validate-module (engine bytes)
  "Validate WASM bytes. Returns T if valid, signals error otherwise."
  (let ((len (length bytes)))
    (with-foreign-object (wasm :uint8 len)
      (loop for i below len
            do (setf (mem-aref wasm :uint8 i) (aref bytes i)))
      (let ((err (%wasmtime-module-validate (engine-pointer engine) wasm len)))
        (check-wasmtime-error err)
        t))))

(defun module-imports (module)
  "Get list of import specifications: ((module name kind) ...)."
  (with-foreign-object (vec '(:struct wasm-importtype-vec-t))
    (%wasmtime-module-imports (module-pointer module) vec)
    (let* ((size (foreign-slot-value vec '(:struct wasm-importtype-vec-t)
                                      'size))
           (data (foreign-slot-value vec '(:struct wasm-importtype-vec-t)
                                      'data))
           (result (loop for i below size
                         collect (parse-importtype
                                  (mem-aref data :pointer i)))))
      (%wasm-importtype-vec-delete vec)
      result)))

(defun parse-importtype (ptr)
  (let* ((mod-vec (%wasm-importtype-module ptr))
         (name-vec (%wasm-importtype-name ptr))
         (ext-type (%wasm-importtype-type ptr))
         (mod-str (byte-vec-to-string mod-vec))
         (name-str (byte-vec-to-string name-vec))
         (kind (extern-kind-symbol (%wasm-externtype-kind ext-type))))
    (list mod-str name-str kind)))

(defun module-exports (module)
  "Get list of export specifications: ((name kind) ...)."
  (with-foreign-object (vec '(:struct wasm-exporttype-vec-t))
    (%wasmtime-module-exports (module-pointer module) vec)
    (let* ((size (foreign-slot-value vec '(:struct wasm-exporttype-vec-t)
                                      'size))
           (data (foreign-slot-value vec '(:struct wasm-exporttype-vec-t)
                                      'data))
           (result (loop for i below size
                         collect (parse-exporttype
                                  (mem-aref data :pointer i)))))
      (%wasm-exporttype-vec-delete vec)
      result)))

(defun parse-exporttype (ptr)
  (let* ((name-vec (%wasm-exporttype-name ptr))
         (ext-type (%wasm-exporttype-type ptr))
         (name-str (byte-vec-to-string name-vec))
         (kind (extern-kind-symbol (%wasm-externtype-kind ext-type))))
    (list name-str kind)))

(defun byte-vec-to-string (vec-ptr)
  (let ((size (foreign-slot-value vec-ptr '(:struct wasm-byte-vec-t) 'size))
        (data (foreign-slot-value vec-ptr '(:struct wasm-byte-vec-t) 'data)))
    (foreign-string-to-lisp data :count size)))

(defun extern-kind-symbol (kind)
  (case kind
    (#.+wasmtime-extern-func+ :func)
    (#.+wasmtime-extern-global+ :global)
    (#.+wasmtime-extern-table+ :table)
    (#.+wasmtime-extern-memory+ :memory)
    (otherwise :unknown)))

(defun module-serialize (module)
  "Serialize compiled module to byte vector for caching."
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (let ((err (%wasmtime-module-serialize (module-pointer module) vec)))
      (check-wasmtime-error err)
      (let* ((size (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'size))
             (data (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'data))
             (result (make-array size :element-type '(unsigned-byte 8))))
        (loop for i below size
              do (setf (aref result i) (mem-aref data :uint8 i)))
        (%wasm-byte-vec-delete vec)
        result))))

(defun module-deserialize (engine bytes)
  "Deserialize module from previously serialized bytes."
  (let ((len (length bytes)))
    (with-foreign-objects ((module-out :pointer)
                           (data :uint8 len))
      (loop for i below len
            do (setf (mem-aref data :uint8 i) (aref bytes i)))
      (let ((err (%wasmtime-module-deserialize (engine-pointer engine)
                                               data len module-out)))
        (check-wasmtime-error err)
        (let* ((ptr (mem-ref module-out :pointer))
               (mod (make-instance 'module :pointer ptr :engine engine)))
          (tg:finalize mod (lambda () (%wasmtime-module-delete ptr)))
          mod)))))

(defun module-serialize-to-file (module path)
  "Serialize module to file."
  (let ((bytes (module-serialize module)))
    (with-open-file (stream path :direction :output
                                 :element-type '(unsigned-byte 8)
                                 :if-exists :supersede)
      (write-sequence bytes stream))
    path))

(defun module-deserialize-from-file (engine path)
  "Deserialize module from file."
  (let ((bytes (read-file-into-byte-vector path)))
    (module-deserialize engine bytes)))

(defun module-clone (module)
  "Clone a module (for sharing across threads)."
  (let* ((ptr (%wasmtime-module-clone (module-pointer module)))
         (mod (make-instance 'module :pointer ptr
                                     :engine (module-engine module))))
    (tg:finalize mod (lambda () (%wasmtime-module-delete ptr)))
    mod))

;;; ============================================================
;;; LINKER
;;; ============================================================

(defclass linker ()
  ((pointer :initarg :pointer
            :reader linker-pointer)
   (engine :initarg :engine
           :reader linker-engine)
   (callback-ids :initform nil
                 :accessor linker-callback-ids)))

(defun make-linker (engine)
  "Create new linker for engine."
  (let* ((ptr (%wasmtime-linker-new (engine-pointer engine)))
         (linker (make-instance 'linker :pointer ptr :engine engine)))
    (tg:finalize linker
                 (let ((ids (linker-callback-ids linker)))
                   (lambda ()
                     (dolist (id ids)
                       (remhash id *callback-registry*))
                     (%wasmtime-linker-delete ptr))))
    linker))

(defun linker-allow-shadowing (linker allow)
  "Enable/disable shadowing of definitions."
  (%wasmtime-linker-allow-shadowing (linker-pointer linker) allow))

(defun linker-define (linker store module-name field-name extern)
  "Define extern in linker."
  (let ((mod-len (length module-name))
        (field-len (length field-name)))
    (with-foreign-object (ext '(:struct wasmtime-extern-t))
      (extern-to-c extern store ext)
      (let ((err (%wasmtime-linker-define (linker-pointer linker)
                                          (store-context store)
                                          module-name mod-len
                                          field-name field-len
                                          ext)))
        (check-wasmtime-error err)))))

(defun linker-define-wasi (linker)
  "Add WASI to linker."
  (let ((err (%wasmtime-linker-define-wasi (linker-pointer linker))))
    (check-wasmtime-error err)))

(defun linker-instantiate (linker store module)
  "Instantiate module through linker."
  (with-foreign-objects ((instance-out '(:struct wasmtime-instance-t))
                         (trap-out :pointer))
    (setf (mem-ref trap-out :pointer) (null-pointer))
    (let ((err (%wasmtime-linker-instantiate (linker-pointer linker)
                                             (store-context store)
                                             (module-pointer module)
                                             instance-out
                                             trap-out)))
      (check-wasmtime-error err trap-out)
      (let* ((store-id (foreign-slot-value instance-out
                                           '(:struct wasmtime-instance-t)
                                           'store-id))
             (index (foreign-slot-value instance-out
                                        '(:struct wasmtime-instance-t)
                                        'index)))
        (make-instance 'instance :store-id store-id :index index
                                 :store store)))))

(defun linker-get (linker store module-name field-name)
  "Get extern from linker."
  (with-foreign-object (ext '(:struct wasmtime-extern-t))
    (let* ((context (store-context store))
           (found (%wasmtime-linker-get (linker-pointer linker)
                                        context
                                        module-name (length module-name)
                                        field-name (length field-name)
                                        ext)))
      (when found
        (extern-from-c ext store)))))

;;; ============================================================
;;; INSTANCE
;;; ============================================================

(defclass instance ()
  ((store-id :initarg :store-id
             :reader instance-store-id)
   (index :initarg :index
          :reader instance-index)
   (store :initarg :store
          :reader instance-store)))

(defun instantiate (store module imports)
  "Low-level instantiation with explicit imports list."
  (let ((num-imports (length imports)))
    (with-foreign-objects ((instance-out '(:struct wasmtime-instance-t))
                           (trap-out :pointer)
                           (imports-arr '(:struct wasmtime-extern-t)
                                        num-imports))
      (setf (mem-ref trap-out :pointer) (null-pointer))
      (loop for i below num-imports
            for imp in imports
            do (extern-to-c imp store
                            (mem-aptr imports-arr
                                      '(:struct wasmtime-extern-t) i)))
      (let ((err (%wasmtime-instance-new (store-context store)
                                         (module-pointer module)
                                         imports-arr num-imports
                                         instance-out trap-out)))
        (check-wasmtime-error err trap-out)
        (let* ((store-id (foreign-slot-value instance-out
                                             '(:struct wasmtime-instance-t)
                                             'store-id))
               (index (foreign-slot-value instance-out
                                          '(:struct wasmtime-instance-t)
                                          'index)))
          (make-instance 'instance :store-id store-id :index index
                                   :store store))))))

(defun instance-export (instance name)
  "Get export from instance by name."
  (with-foreign-objects ((ext '(:struct wasmtime-extern-t))
                         (inst '(:struct wasmtime-instance-t)))
    (setf (foreign-slot-value inst '(:struct wasmtime-instance-t) 'store-id)
          (instance-store-id instance))
    (setf (foreign-slot-value inst '(:struct wasmtime-instance-t) 'index)
          (instance-index instance))
    (let* ((store (instance-store instance))
           (context (store-context store))
           (found (%wasmtime-instance-export-get context
                                                 inst
                                                 name (length name)
                                                 ext)))
      (when found
        (extern-from-c ext store)))))

(defun instance-exports (instance)
  "Get all exports as alist ((name . extern) ...)."
  (let* ((store (instance-store instance))
         (context (store-context store))
         (result nil))
    (with-foreign-objects ((inst '(:struct wasmtime-instance-t))
                           (ext '(:struct wasmtime-extern-t))
                           (name-out :pointer)
                           (name-len-out :size))
      (setf (foreign-slot-value inst '(:struct wasmtime-instance-t) 'store-id)
            (instance-store-id instance))
      (setf (foreign-slot-value inst '(:struct wasmtime-instance-t) 'index)
            (instance-index instance))
      (loop for i from 0
            while (%wasmtime-instance-export-nth context
                                                 inst i
                                                 name-out name-len-out
                                                 ext)
            do (let ((name (foreign-string-to-lisp
                            (mem-ref name-out :pointer)
                            :count (mem-ref name-len-out :size)))
                     (extern (extern-from-c ext store)))
                 (push (cons name extern) result))))
    (nreverse result)))

;;; ============================================================
;;; EXTERN WRAPPER
;;; ============================================================

(defclass wasm-func ()
  ((store-id :initarg :store-id :reader func-store-id)
   (index :initarg :index :reader func-index)
   (store :initarg :store :reader func-store)
   (functype :initarg :functype :reader func-functype)))

(defclass wasm-memory ()
  ((store-id :initarg :store-id :reader memory-store-id)
   (index :initarg :index :reader memory-index)
   (index2 :initarg :index2 :reader memory-index2)
   (store :initarg :store :reader memory-store)))

(defun memory-context (memory)
  "Get context for memory, always derived fresh from store."
  (store-context (memory-store memory)))

(defclass wasm-global ()
  ((store-id :initarg :store-id :reader global-store-id)
   (index :initarg :index :reader global-index)
   (store :initarg :store :reader global-store)))

(defun global-context (global)
  "Get context for global, always derived fresh from store."
  (store-context (global-store global)))

(defclass wasm-table ()
  ((store-id :initarg :store-id :reader table-store-id)
   (index :initarg :index :reader table-index)
   (store :initarg :store :reader table-store)))

(defun extern-from-c (ext-ptr store)
  "Convert C extern struct to Lisp object."
  (let ((kind (foreign-slot-value ext-ptr '(:struct wasmtime-extern-t) 'kind))
        (context (store-context store)))
    (case kind
      (#.+wasmtime-extern-func+
       (with-foreign-object (func '(:struct wasmtime-func-t))
         (memcpy func (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                            'of)
                 (foreign-type-size '(:struct wasmtime-func-t)))
         (let ((functype (%wasmtime-func-type context func)))
           (make-instance 'wasm-func
                          :store-id (foreign-slot-value
                                     func '(:struct wasmtime-func-t) 'store-id)
                          :index (foreign-slot-value
                                  func '(:struct wasmtime-func-t) 'index)
                          :store store
                          :functype functype))))
      (#.+wasmtime-extern-memory+
       (with-foreign-object (mem '(:struct wasmtime-memory-t))
          (memcpy mem (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                            'of)
                  (foreign-type-size '(:struct wasmtime-memory-t)))
          (make-instance 'wasm-memory
                         :store-id (foreign-slot-value
                                    mem '(:struct wasmtime-memory-t) 'store-id)
                         :index (foreign-slot-value
                                  mem '(:struct wasmtime-memory-t) 'index)
                         :index2 (foreign-slot-value
                                  mem '(:struct wasmtime-memory-t) 'index2)
                         :store store)))
      (#.+wasmtime-extern-global+
       (with-foreign-object (glob '(:struct wasmtime-global-t))
          (memcpy glob (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                             'of)
                  (foreign-type-size '(:struct wasmtime-global-t)))
          (make-instance 'wasm-global
                         :store-id (foreign-slot-value
                                    glob '(:struct wasmtime-global-t) 'store-id)
                         :index (foreign-slot-value
                                 glob '(:struct wasmtime-global-t) 'index)
                         :store store)))
      (#.+wasmtime-extern-table+
       (with-foreign-object (tbl '(:struct wasmtime-table-t))
         (memcpy tbl (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                           'of)
                 (foreign-type-size '(:struct wasmtime-table-t)))
         (make-instance 'wasm-table
                        :store-id (foreign-slot-value
                                   tbl '(:struct wasmtime-table-t) 'store-id)
                        :index (foreign-slot-value
                                tbl '(:struct wasmtime-table-t) 'index)
                        :store store))))))

(defun extern-to-c (extern store ext-ptr)
  "Convert Lisp extern object to C extern struct."
  (declare (ignore store))
  (etypecase extern
    (wasm-func
     (setf (foreign-slot-value ext-ptr '(:struct wasmtime-extern-t) 'kind)
           +wasmtime-extern-func+)
     (let ((of-ptr (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                         'of)))
       (setf (mem-ref of-ptr :uint64) (func-store-id extern))
       (setf (mem-ref (inc-pointer of-ptr 8) :size) (func-index extern))))
    (wasm-memory
     (setf (foreign-slot-value ext-ptr '(:struct wasmtime-extern-t) 'kind)
           +wasmtime-extern-memory+)
     (with-foreign-object (mem '(:struct wasmtime-memory-t))
       (setf (foreign-slot-value mem '(:struct wasmtime-memory-t) 'store-id)
             (memory-store-id extern))
       (setf (foreign-slot-value mem '(:struct wasmtime-memory-t) 'index)
             (memory-index extern))
       (setf (foreign-slot-value mem '(:struct wasmtime-memory-t) 'index2)
             (memory-index2 extern))
       (memcpy (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t) 'of)
               mem
               (foreign-type-size '(:struct wasmtime-memory-t)))))
    (wasm-global
     (setf (foreign-slot-value ext-ptr '(:struct wasmtime-extern-t) 'kind)
           +wasmtime-extern-global+)
     (let ((of-ptr (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                         'of)))
       (setf (mem-ref of-ptr :uint64) (global-store-id extern))
       (setf (mem-ref (inc-pointer of-ptr 8) :size) (global-index extern))))
    (wasm-table
     (setf (foreign-slot-value ext-ptr '(:struct wasmtime-extern-t) 'kind)
           +wasmtime-extern-table+)
     (let ((of-ptr (foreign-slot-pointer ext-ptr '(:struct wasmtime-extern-t)
                                         'of)))
       (setf (mem-ref of-ptr :uint64) (table-store-id extern))
       (setf (mem-ref (inc-pointer of-ptr 8) :size) (table-index extern))))))

(defun memcpy (dst src n)
  (loop for i below n
        do (setf (mem-aref dst :uint8 i) (mem-aref src :uint8 i))))

;;; ============================================================
;;; FUNCTION CALLS
;;; ============================================================

(defun call-function (func &rest args)
  "Call WASM function with args, returns values."
  (let* ((store (func-store func))
         (context (store-context store))
         (num-args (length args))
         (functype (or (func-functype func)
                       (get-func-type context func)))
         (result-count (functype-result-count functype))
         (param-types (functype-param-types functype))
         (expected-args (length param-types)))
    (when (/= num-args expected-args)
      (error "Function expects ~D argument~:P but got ~D."
             expected-args
             num-args))
    (with-foreign-objects ((func-c '(:struct wasmtime-func-t))
                           (args-c '(:struct wasmtime-val-t) (max 1 num-args))
                           (results-c '(:struct wasmtime-val-t)
                                      (max 1 result-count))
                           (trap-out :pointer))
      (setf (mem-ref trap-out :pointer) (null-pointer))
      (setf (foreign-slot-value func-c '(:struct wasmtime-func-t) 'store-id)
            (func-store-id func))
      (setf (foreign-slot-value func-c '(:struct wasmtime-func-t) 'index)
            (func-index func))
      (loop for i below num-args
            for arg in args
            for param-type in param-types
            do (lisp-to-wasm-val arg
                                 (mem-aptr args-c '(:struct wasmtime-val-t) i)
                                 param-type))
      (let ((err (%wasmtime-func-call context func-c
                                      args-c num-args
                                      results-c result-count
                                      trap-out)))
        (check-wasmtime-error err trap-out)
        (if (= result-count 0)
            (values)
            (if (= result-count 1)
                (wasm-val-to-lisp (mem-aptr results-c '(:struct wasmtime-val-t)
                                            0))
                (values-list
                 (loop for i below result-count
                       collect (wasm-val-to-lisp
                                (mem-aptr results-c '(:struct wasmtime-val-t)
                                          i))))))))))

(defun get-func-type (context func)
  (with-foreign-object (func-c '(:struct wasmtime-func-t))
    (setf (foreign-slot-value func-c '(:struct wasmtime-func-t) 'store-id)
          (func-store-id func))
    (setf (foreign-slot-value func-c '(:struct wasmtime-func-t) 'index)
          (func-index func))
    (%wasmtime-func-type context func-c)))

(defun functype-result-count (functype)
  (let ((results-vec (%wasm-functype-results functype)))
    (foreign-slot-value results-vec '(:struct wasm-valtype-vec-t) 'size)))

(defun functype-param-types (functype)
  "Extract parameter types from functype as list of kind constants."
  (let* ((params-vec (%wasm-functype-params functype))
         (size (foreign-slot-value params-vec '(:struct wasm-valtype-vec-t)
                                   'size))
         (data (foreign-slot-value params-vec '(:struct wasm-valtype-vec-t)
                                   'data)))
    (loop for i below size
          collect (%wasm-valtype-kind (mem-aref data :pointer i)))))

;;; ============================================================
;;; VALUE CONVERSION
;;; ============================================================

(defun lisp-to-wasm-val (val val-ptr &optional (type nil))
  "Convert Lisp value to wasmtime_val_t. Type can override auto-detection."
  (etypecase val
    (integer
     (let ((kind (cond
                   ((eql type +wasm-i32+) +wasm-i32+)
                   ((eql type +wasm-i64+) +wasm-i64+)
                   ((typep val '(signed-byte 32)) +wasm-i32+)
                   (t +wasm-i64+))))
       (setf (foreign-slot-value val-ptr '(:struct wasmtime-val-t) 'kind)
             kind)
       (setf (mem-ref (foreign-slot-pointer val-ptr
                                            '(:struct wasmtime-val-t) 'of)
                      (if (= kind +wasm-i32+) :int32 :int64))
             val)))
    (single-float
     (setf (foreign-slot-value val-ptr '(:struct wasmtime-val-t) 'kind)
           +wasm-f32+)
     (setf (mem-ref (foreign-slot-pointer val-ptr
                                          '(:struct wasmtime-val-t) 'of)
                    :float)
           val))
    (double-float
     (setf (foreign-slot-value val-ptr '(:struct wasmtime-val-t) 'kind)
           +wasm-f64+)
     (setf (mem-ref (foreign-slot-pointer val-ptr
                                          '(:struct wasmtime-val-t) 'of)
                    :double)
           val))))

(defun wasm-val-to-lisp (val-ptr)
  "Convert wasmtime_val_t to Lisp value."
  (let ((kind (foreign-slot-value val-ptr '(:struct wasmtime-val-t) 'kind))
        (of-ptr (foreign-slot-pointer val-ptr '(:struct wasmtime-val-t) 'of)))
    (case kind
      (#.+wasm-i32+ (mem-ref of-ptr :int32))
      (#.+wasm-i64+ (mem-ref of-ptr :int64))
      (#.+wasm-f32+ (mem-ref of-ptr :float))
      (#.+wasm-f64+ (mem-ref of-ptr :double))
      (otherwise nil))))

;;; ============================================================
;;; MEMORY
;;; ============================================================

(defun make-memory (store min-pages &key max-pages)
  "Create new WASM memory."
  (with-foreign-objects ((limits '(:struct wasm-limits-t))
                         (mem-out '(:struct wasmtime-memory-t)))
    (setf (foreign-slot-value limits '(:struct wasm-limits-t) 'min) min-pages)
    (setf (foreign-slot-value limits '(:struct wasm-limits-t) 'max)
          (or max-pages #xFFFFFFFF))
    (let* ((ctx (store-context store))
           (memtype (%wasm-memorytype-new limits))
           (err (%wasmtime-memory-new ctx memtype mem-out)))
      (%wasm-memorytype-delete memtype)
      (check-wasmtime-error err)
      (make-instance 'wasm-memory
                     :store-id (foreign-slot-value
                                mem-out '(:struct wasmtime-memory-t) 'store-id)
                     :index (foreign-slot-value
                             mem-out '(:struct wasmtime-memory-t) 'index)
                     :index2 (foreign-slot-value
                              mem-out '(:struct wasmtime-memory-t) 'index2)
                     :store store))))

(defun memory-data (memory)
  "Get raw pointer to memory data.
WARNING: Pointer is invalidated by memory-grow. Do not cache this pointer.
Call memory-data again after any grow operation to get a valid pointer."
  (with-foreign-object (mem-c '(:struct wasmtime-memory-t))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'store-id)
          (memory-store-id memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index)
          (memory-index memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index2)
          (memory-index2 memory))
    (%wasmtime-memory-data (memory-context memory) mem-c)))

(defun memory-data-size (memory)
  "Get size of memory data in bytes."
  (with-foreign-object (mem-c '(:struct wasmtime-memory-t))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'store-id)
          (memory-store-id memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index)
          (memory-index memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index2)
          (memory-index2 memory))
    (%wasmtime-memory-data-size (memory-context memory) mem-c)))

(defun memory-size (memory)
  "Get memory size in pages."
  (with-foreign-object (mem-c '(:struct wasmtime-memory-t))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'store-id)
          (memory-store-id memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index)
          (memory-index memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index2)
          (memory-index2 memory))
    (%wasmtime-memory-size (memory-context memory) mem-c)))

(defun memory-grow (memory delta)
  "Grow memory by delta pages. Returns previous size."
  (with-foreign-objects ((mem-c '(:struct wasmtime-memory-t))
                         (prev-size :uint64))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'store-id)
          (memory-store-id memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index)
          (memory-index memory))
    (setf (foreign-slot-value mem-c '(:struct wasmtime-memory-t) 'index2)
          (memory-index2 memory))
    (let ((err (%wasmtime-memory-grow (memory-context memory)
                                      mem-c delta prev-size)))
      (check-wasmtime-error err)
      (mem-ref prev-size :uint64))))

(defun memory-ref (memory offset)
  "Read byte from memory at offset."
  (let ((size (memory-data-size memory)))
    (when (>= offset size)
      (error "Memory access out of bounds: offset ~D, size ~D" offset size))
    (mem-aref (memory-data memory) :uint8 offset)))

(defun (setf memory-ref) (value memory offset)
  "Write byte to memory at offset."
  (let ((size (memory-data-size memory)))
    (when (>= offset size)
      (error "Memory access out of bounds: offset ~D, size ~D" offset size))
    (setf (mem-aref (memory-data memory) :uint8 offset) value)))

;;; ============================================================
;;; GLOBAL
;;; ============================================================

(defun make-global (store valtype value &key (mutable nil))
  "Create new WASM global."
  (with-foreign-objects ((val '(:struct wasmtime-val-t))
                         (glob-out '(:struct wasmtime-global-t)))
    (lisp-to-wasm-val value val)
    (let* ((ctx (store-context store))
           (vt (%wasm-valtype-new (lisp-type-to-wasm-kind valtype)))
           (mut (if mutable +wasm-var+ +wasm-const+))
           (globaltype (%wasm-globaltype-new vt mut))
           (err (%wasmtime-global-new ctx globaltype val glob-out)))
      (%wasm-globaltype-delete globaltype)
      (check-wasmtime-error err)
      (make-instance 'wasm-global
                     :store-id (foreign-slot-value
                                glob-out '(:struct wasmtime-global-t) 'store-id)
                     :index (foreign-slot-value
                             glob-out '(:struct wasmtime-global-t) 'index)
                     :store store))))

(defun lisp-type-to-wasm-kind (type)
  (case type
    (:i32 +wasm-i32+)
    (:i64 +wasm-i64+)
    (:f32 +wasm-f32+)
    (:f64 +wasm-f64+)
    (:funcref +wasm-funcref+)
    (:externref +wasm-externref+)
    (otherwise (error "Unknown WASM type: ~A" type))))

(defun global-value (global)
  "Get value of WASM global."
  (with-foreign-objects ((glob-c '(:struct wasmtime-global-t))
                         (val '(:struct wasmtime-val-t)))
    (setf (foreign-slot-value glob-c '(:struct wasmtime-global-t) 'store-id)
          (global-store-id global))
    (setf (foreign-slot-value glob-c '(:struct wasmtime-global-t) 'index)
          (global-index global))
    (%wasmtime-global-get (global-context global) glob-c val)
    (wasm-val-to-lisp val)))

(defun (setf global-value) (value global)
  "Set value of mutable WASM global."
  (with-foreign-objects ((glob-c '(:struct wasmtime-global-t))
                         (val '(:struct wasmtime-val-t)))
    (setf (foreign-slot-value glob-c '(:struct wasmtime-global-t) 'store-id)
          (global-store-id global))
    (setf (foreign-slot-value glob-c '(:struct wasmtime-global-t) 'index)
          (global-index global))
    (lisp-to-wasm-val value val)
    (let ((err (%wasmtime-global-set (global-context global)
                                     glob-c val)))
      (check-wasmtime-error err)
      value)))

;;; ============================================================
;;; TABLE
;;; ============================================================

(defun make-table (store element-type min &key max init)
  "Create new WASM table."
  (with-foreign-objects ((limits '(:struct wasm-limits-t))
                         (tbl-out '(:struct wasmtime-table-t))
                         (init-val '(:struct wasmtime-val-t)))
    (setf (foreign-slot-value limits '(:struct wasm-limits-t) 'min) min)
    (setf (foreign-slot-value limits '(:struct wasm-limits-t) 'max)
          (or max #xffffffff))
    (if init
        (lisp-to-wasm-val init init-val)
        (setf (foreign-slot-value init-val '(:struct wasmtime-val-t) 'kind)
              (lisp-type-to-wasm-kind element-type)))
    (let* ((vt (%wasm-valtype-new (lisp-type-to-wasm-kind element-type)))
           (tabletype (%wasm-tabletype-new vt limits))
           (err (%wasmtime-table-new (store-context store) tabletype
                                     init-val tbl-out)))
      (%wasm-tabletype-delete tabletype)
      (check-wasmtime-error err)
      (make-instance 'wasm-table
                     :store-id (foreign-slot-value
                                tbl-out '(:struct wasmtime-table-t) 'store-id)
                     :index (foreign-slot-value
                             tbl-out '(:struct wasmtime-table-t) 'index)
                     :store store))))

(defun table-size (table)
  "Get table size."
  (with-foreign-object (tbl-c '(:struct wasmtime-table-t))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'store-id)
          (table-store-id table))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'index)
          (table-index table))
    (%wasmtime-table-size (store-context (table-store table)) tbl-c)))

(defun table-get (table index)
  "Get value from table at index."
  (with-foreign-objects ((tbl-c '(:struct wasmtime-table-t))
                         (val '(:struct wasmtime-val-t)))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'store-id)
          (table-store-id table))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'index)
          (table-index table))
    (when (%wasmtime-table-get (store-context (table-store table))
                               tbl-c index val)
      (wasm-val-to-lisp val))))

(defun table-set (table index value)
  "Set value in table at index."
  (with-foreign-objects ((tbl-c '(:struct wasmtime-table-t))
                         (val '(:struct wasmtime-val-t)))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'store-id)
          (table-store-id table))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'index)
          (table-index table))
    (lisp-to-wasm-val value val)
    (let ((err (%wasmtime-table-set (store-context (table-store table))
                                    tbl-c index val)))
      (check-wasmtime-error err)
      value)))

(defun table-grow (table delta init)
  "Grow table by delta elements. Returns previous size."
  (with-foreign-objects ((tbl-c '(:struct wasmtime-table-t))
                         (init-val '(:struct wasmtime-val-t))
                         (prev-size :uint32))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'store-id)
          (table-store-id table))
    (setf (foreign-slot-value tbl-c '(:struct wasmtime-table-t) 'index)
          (table-index table))
    (lisp-to-wasm-val init init-val)
    (let ((err (%wasmtime-table-grow (store-context (table-store table))
                                     tbl-c delta init-val prev-size)))
      (check-wasmtime-error err)
      (mem-ref prev-size :uint32))))

;;; ============================================================
;;; WAT
;;; ============================================================

(defun wat->wasm (wat-string)
  "Convert WAT text to WASM bytes."
  (with-foreign-object (wasm-vec '(:struct wasm-byte-vec-t))
    (let ((err (%wasmtime-wat2wasm wat-string (length wat-string) wasm-vec)))
      (check-wasmtime-error err)
      (let* ((size (foreign-slot-value wasm-vec '(:struct wasm-byte-vec-t)
                                       'size))
             (data (foreign-slot-value wasm-vec '(:struct wasm-byte-vec-t)
                                       'data))
             (result (make-array size :element-type '(unsigned-byte 8))))
        (loop for i below size
              do (setf (aref result i) (mem-aref data :uint8 i)))
        (%wasm-byte-vec-delete wasm-vec)
        result))))

;;; ============================================================
;;; WASI
;;; ============================================================

(defclass wasi-config ()
  ((pointer :initarg :pointer
            :reader wasi-config-pointer)))

(defun make-wasi-config ()
  "Create new WASI configuration."
  (let* ((ptr (%wasi-config-new))
         (cfg (make-instance 'wasi-config :pointer ptr)))
    (tg:finalize cfg (lambda () (%wasi-config-delete ptr)))
    cfg))

(defun wasi-config-inherit-stdio (config)
  "Inherit stdin/stdout/stderr from host."
  (%wasi-config-inherit-stdin (wasi-config-pointer config))
  (%wasi-config-inherit-stdout (wasi-config-pointer config))
  (%wasi-config-inherit-stderr (wasi-config-pointer config)))

(defun wasi-config-inherit-argv (config)
  "Inherit command line args from host."
  (%wasi-config-inherit-argv (wasi-config-pointer config)))

(defun wasi-config-inherit-env (config)
  "Inherit environment from host."
  (%wasi-config-inherit-env (wasi-config-pointer config)))

(defun wasi-config-set-argv (config args)
  "Set WASI arguments."
  (let ((argc (length args)))
    (with-foreign-object (argv :pointer argc)
      (loop for i below argc
            for arg in args
            do (setf (mem-aref argv :pointer i)
                     (foreign-string-alloc arg)))
      (%wasi-config-set-argv (wasi-config-pointer config) argc argv)
      (loop for i below argc
            do (foreign-string-free (mem-aref argv :pointer i))))))

(defun wasi-config-set-env (config env)
  "Set WASI environment. ENV is alist ((name . value) ...)."
  (let ((envc (length env)))
    (with-foreign-objects ((names :pointer envc)
                           (values :pointer envc))
      (loop for i below envc
            for (name . value) in env
            do (setf (mem-aref names :pointer i) (foreign-string-alloc name))
               (setf (mem-aref values :pointer i) (foreign-string-alloc value)))
      (%wasi-config-set-env (wasi-config-pointer config) envc names values)
      (loop for i below envc
            do (foreign-string-free (mem-aref names :pointer i))
               (foreign-string-free (mem-aref values :pointer i))))))

(defun wasi-config-preopen-dir (config host-path guest-path)
  "Preopen directory for WASI access."
  (unless (%wasi-config-preopen-dir (wasi-config-pointer config)
                                    host-path guest-path)
    (error 'wasmtime-error :message "Failed to preopen directory")))

(defun store-set-wasi (store wasi-config)
  "Set WASI configuration for store. Consumes wasi-config."
  (tg:cancel-finalization wasi-config)
  (let ((err (%wasmtime-context-set-wasi (store-context store)
                                         (wasi-config-pointer wasi-config))))
    (check-wasmtime-error err)))

;;; ============================================================
;;; HOST CALLBACKS
;;; ============================================================

(defvar *callback-registry* (make-hash-table)
  "Maps callback IDs to Lisp closures.")

(defvar *callback-counter* 0
  "Counter for generating unique callback IDs.")

(defcallback host-func-trampoline :pointer
    ((env :pointer)
     (caller wasmtime-caller-t)
     (args :pointer)
     (nargs :size)
     (results :pointer)
     (nresults :size))
  (declare (ignore caller))
  (let* ((id (pointer-address env))
         (fn (gethash id *callback-registry*)))
    (when fn
      (let* ((lisp-args (loop for i below nargs
                              collect (wasm-val-to-lisp
                                       (mem-aptr args
                                                 '(:struct wasmtime-val-t) i))))
             (lisp-results (multiple-value-list (apply fn lisp-args))))
        (unless (= (length lisp-results) nresults)
          (error "Host function returned ~D values but expected ~D"
                 (length lisp-results) nresults))
        (loop for i below nresults
              for result in lisp-results
              do (lisp-to-wasm-val result
                                   (mem-aptr results
                                             '(:struct wasmtime-val-t) i))))))
  (null-pointer))

(defun make-functype (params results)
  "Create functype from param/result type lists (:i32 :i64 etc)."
  (with-foreign-objects ((params-vec '(:struct wasm-valtype-vec-t))
                         (results-vec '(:struct wasm-valtype-vec-t)))
    (let ((nparams (length params))
          (nresults (length results)))
      (if (zerop nparams)
          (%wasm-valtype-vec-new-empty params-vec)
          (with-foreign-object (param-arr :pointer nparams)
            (loop for i below nparams
                  for p in params
                  do (setf (mem-aref param-arr :pointer i)
                           (%wasm-valtype-new (lisp-type-to-wasm-kind p))))
            (%wasm-valtype-vec-new params-vec nparams param-arr)))
      (if (zerop nresults)
          (%wasm-valtype-vec-new-empty results-vec)
          (with-foreign-object (result-arr :pointer nresults)
            (loop for i below nresults
                  for r in results
                  do (setf (mem-aref result-arr :pointer i)
                           (%wasm-valtype-new (lisp-type-to-wasm-kind r))))
            (%wasm-valtype-vec-new results-vec nresults result-arr)))
      (%wasm-functype-new params-vec results-vec))))

(defun make-host-function (store params results fn)
  "Create WASM function that calls Lisp FN.
PARAMS/RESULTS are lists of types (:i32 :i64 :f32 :f64)."
  (let* ((id (incf *callback-counter*))
         (functype (make-functype params results))
         (func nil))
    (unwind-protect
         (progn
           (setf (gethash id *callback-registry*) fn)
           (with-foreign-object (func-out '(:struct wasmtime-func-t))
             (%wasmtime-func-new (store-context store)
                                 functype
                                 (callback host-func-trampoline)
                                 (make-pointer id)
                                 (null-pointer)
                                 func-out)
             (setf func (make-instance 'wasm-func
                                       :store-id (foreign-slot-value
                                                  func-out
                                                  '(:struct wasmtime-func-t)
                                                  'store-id)
                                       :index (foreign-slot-value
                                               func-out
                                               '(:struct wasmtime-func-t)
                                               'index)
                                       :store store
                                       :functype functype))
             (tg:finalize func (lambda ()
                                 (%wasm-functype-delete functype)
                                 (remhash id *callback-registry*)))
             func))
      (unless func
        (%wasm-functype-delete functype)
        (remhash id *callback-registry*)))))

(defun linker-define-func (linker module-name field-name params results fn)
  "Define host function in linker."
  (let* ((id (incf *callback-counter*))
         (functype (make-functype params results)))
    (setf (gethash id *callback-registry*) fn)
    (push id (linker-callback-ids linker))
    (let ((err (%wasmtime-linker-define-func (linker-pointer linker)
                                             module-name (length module-name)
                                             field-name (length field-name)
                                             functype
                                             (callback host-func-trampoline)
                                             (make-pointer id)
                                             (null-pointer))))
      (%wasm-functype-delete functype)
      (check-wasmtime-error err))))

;;; ============================================================
;;; COMPONENT MODEL
;;; ============================================================

(defclass component ()
  ((pointer :initarg :pointer
            :reader component-pointer)
   (engine :initarg :engine
           :reader component-engine)))

(defun load-component (engine bytes)
  "Load component from WASM bytes."
  (let ((len (length bytes)))
    (with-foreign-object (component-out :pointer)
      (with-foreign-object (wasm :uint8 len)
        (loop for i below len
              do (setf (mem-aref wasm :uint8 i) (aref bytes i)))
        (let ((err (%wasmtime-component-new (engine-pointer engine)
                                            wasm len component-out)))
          (check-wasmtime-error err)
          (let* ((ptr (mem-ref component-out :pointer))
                 (comp (make-instance 'component :pointer ptr :engine engine)))
            (tg:finalize comp (lambda () (%wasmtime-component-delete ptr)))
            comp))))))

(defun load-component-from-file (engine path)
  "Load component from .wasm file."
  (let ((bytes (read-file-into-byte-vector path)))
    (load-component engine bytes)))

(defun component-clone (component)
  "Clone a component."
  (let* ((ptr (%wasmtime-component-clone (component-pointer component)))
         (comp (make-instance 'component :pointer ptr
                                         :engine (component-engine component))))
    (tg:finalize comp (lambda () (%wasmtime-component-delete ptr)))
    comp))

(defun component-serialize (component)
  "Serialize component to byte vector."
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (let ((err (%wasmtime-component-serialize (component-pointer component)
                                              vec)))
      (check-wasmtime-error err)
      (let* ((size (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'size))
             (data (foreign-slot-value vec '(:struct wasm-byte-vec-t) 'data))
             (result (make-array size :element-type '(unsigned-byte 8))))
        (loop for i below size
              do (setf (aref result i) (mem-aref data :uint8 i)))
        (%wasm-byte-vec-delete vec)
        result))))

(defun component-deserialize (engine bytes)
  "Deserialize component from bytes."
  (let ((len (length bytes)))
    (with-foreign-objects ((component-out :pointer)
                           (data :uint8 len))
      (loop for i below len
            do (setf (mem-aref data :uint8 i) (aref bytes i)))
      (let ((err (%wasmtime-component-deserialize (engine-pointer engine)
                                                  data len component-out)))
        (check-wasmtime-error err)
        (let* ((ptr (mem-ref component-out :pointer))
               (comp (make-instance 'component :pointer ptr :engine engine)))
          (tg:finalize comp (lambda () (%wasmtime-component-delete ptr)))
          comp)))))

(defun component-serialize-to-file (component path)
  "Serialize component to file."
  (let ((bytes (component-serialize component)))
    (with-open-file (stream path :direction :output
                                 :element-type '(unsigned-byte 8)
                                 :if-exists :supersede)
      (write-sequence bytes stream))
    path))

(defun component-deserialize-from-file (engine path)
  "Deserialize component from file."
  (let ((bytes (read-file-into-byte-vector path)))
    (component-deserialize engine bytes)))

;;; ============================================================
;;; COMPONENT LINKER
;;; ============================================================

(defclass component-linker ()
  ((pointer :initarg :pointer
            :reader component-linker-pointer)
   (engine :initarg :engine
           :reader component-linker-engine)))

(defun make-component-linker (engine)
  "Create new component linker."
  (let* ((ptr (%wasmtime-component-linker-new (engine-pointer engine)))
         (linker (make-instance 'component-linker :pointer ptr :engine engine)))
    (tg:finalize linker (lambda () (%wasmtime-component-linker-delete ptr)))
    linker))

(defun component-linker-add-wasi (linker)
  "Add WASI P2 to component linker."
  (let ((err (%wasmtime-component-linker-add-wasip2
              (component-linker-pointer linker))))
    (check-wasmtime-error err)))

(defclass component-linker-instance ()
  ((pointer :initarg :pointer
            :reader component-linker-instance-pointer)
   (linker :initarg :linker
           :reader component-linker-instance-linker)))

(defun component-linker-root (linker)
  "Get root instance builder for component linker."
  (with-foreign-object (root-out :pointer)
    (%wasmtime-component-linker-root (component-linker-pointer linker)
                                     root-out)
    (make-instance 'component-linker-instance
                   :pointer (mem-ref root-out :pointer)
                   :linker linker)))

(defun component-linker-instance-add-instance (instance name)
  "Add nested instance to linker instance. Returns child instance builder."
  (with-foreign-object (child-out :pointer)
    (let ((err (%wasmtime-component-linker-instance-add-instance
                (component-linker-instance-pointer instance)
                name (length name)
                child-out)))
      (check-wasmtime-error err)
      (make-instance 'component-linker-instance
                     :pointer (mem-ref child-out :pointer)
                     :linker (component-linker-instance-linker instance)))))

(defun component-linker-instance-add-module (instance name module)
  "Add module to linker instance."
  (let ((err (%wasmtime-component-linker-instance-add-module
              (component-linker-instance-pointer instance)
              name (length name)
              (module-pointer module))))
    (check-wasmtime-error err)))

;;; ============================================================
;;; COMPONENT INSTANCE
;;; ============================================================

(defclass component-instance ()
  ((store-id :initarg :store-id
             :reader component-instance-store-id)
   (index :initarg :index
          :reader component-instance-index)
   (store :initarg :store
          :reader component-instance-store)))

(defun component-linker-instantiate (linker store component)
  "Instantiate component through linker."
  (with-foreign-objects ((instance-out '(:struct wasmtime-component-instance-t))
                         (trap-out :pointer))
    (setf (mem-ref trap-out :pointer) (null-pointer))
    (let ((err (%wasmtime-component-linker-instantiate
                (component-linker-pointer linker)
                (store-context store)
                (component-pointer component)
                instance-out
                trap-out)))
      (check-wasmtime-error err trap-out)
      (let* ((store-id (foreign-slot-value
                        instance-out
                        '(:struct wasmtime-component-instance-t)
                        'store-id))
             (index (foreign-slot-value
                     instance-out
                     '(:struct wasmtime-component-instance-t)
                     'index)))
        (make-instance 'component-instance
                       :store-id store-id
                       :index index
                       :store store)))))

(defun component-instance-export (instance name)
  "Get exported function from component instance."
  (with-foreign-objects ((inst '(:struct wasmtime-component-instance-t))
                         (func-out '(:struct wasmtime-func-t)))
    (setf (foreign-slot-value inst '(:struct wasmtime-component-instance-t)
                              'store-id)
          (component-instance-store-id instance))
    (setf (foreign-slot-value inst '(:struct wasmtime-component-instance-t)
                              'index)
          (component-instance-index instance))
    (let* ((store (component-instance-store instance))
           (context (store-context store))
           (found (%wasmtime-component-instance-export-get
                   context
                   inst
                   name (length name)
                   func-out)))
      (when found
        (let ((functype (%wasmtime-func-type context func-out)))
          (make-instance 'wasm-func
                         :store-id (foreign-slot-value
                                    func-out '(:struct wasmtime-func-t)
                                    'store-id)
                         :index (foreign-slot-value
                                 func-out '(:struct wasmtime-func-t)
                                 'index)
                         :store store
                         :functype functype))))))

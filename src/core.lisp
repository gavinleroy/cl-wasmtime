(in-package :cl-wasmtime)

;;; ============================================================
;;; Error Conditions
;;; ============================================================

(define-condition wasmtime-error (error)
  ((message :initarg :message
            :reader wasmtime-error-message))
  (:report (lambda (c s)
             (format s "Wasmtime error: ~A"
                     (wasmtime-error-message c)))))

(define-condition wasm-trap (wasmtime-error)
  ((code :initarg :code
         :reader wasm-trap-code))
  (:report (lambda (c s)
             (format s "WASM trap (~A): ~A"
                     (wasm-trap-code c)
                     (wasmtime-error-message c)))))

(defun check-wasmtime-error (err-ptr &optional trap-ptr)
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
    (let* ((size (foreign-slot-value
                  vec '(:struct wasm-byte-vec-t) 'size))
           (data (foreign-slot-value
                  vec '(:struct wasm-byte-vec-t) 'data))
           (msg (foreign-string-to-lisp data :count size)))
      (%wasm-byte-vec-delete vec)
      msg)))

(defun extract-trap-message (trap-ptr)
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (%wasm-trap-message trap-ptr vec)
    (let* ((size (foreign-slot-value
                  vec '(:struct wasm-byte-vec-t) 'size))
           (data (foreign-slot-value
                  vec '(:struct wasm-byte-vec-t) 'data))
           (msg (foreign-string-to-lisp data :count size)))
      (%wasm-byte-vec-delete vec)
      msg)))

(defun extract-trap-code (trap-ptr)
  (with-foreign-object (code :uint8)
    (if (%wasmtime-trap-code trap-ptr code)
        (mem-ref code :uint8)
        nil)))

;;; ============================================================
;;; Callback Registry (before first reference in LINKER)
;;; ============================================================

(defvar *callback-registry* (make-hash-table))
(defvar *callback-counter* 0)

;;; ============================================================
;;; CONFIG
;;; ============================================================

(defclass config ()
  ((pointer :initarg :pointer
            :reader config-pointer)))

(defun make-config (&key debug-info consume-fuel wasm-threads
                         wasm-simd wasm-bulk-memory
                         wasm-multi-value wasm-reference-types)
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
  (let* ((ptr (if config
                  (let ((eng (%wasm-engine-new-with-config
                              (config-pointer config))))
                    (when (null-pointer-p eng)
                      (error "Failed to create engine"))
                    (tg:cancel-finalization config)
                    eng)
                  (%wasm-engine-new)))
         (engine (make-instance 'engine :pointer ptr)))
    (tg:finalize engine
                 (lambda () (%wasm-engine-delete ptr)))
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
  (let* ((ptr (%wasmtime-store-new (engine-pointer engine)
                                   (null-pointer)
                                   (null-pointer)))
         (store (make-instance 'store
                               :pointer ptr
                               :engine engine)))
    (tg:finalize store
                 (lambda () (%wasmtime-store-delete ptr)))
    store))

(defun store-context (store)
  (%wasmtime-store-context (store-pointer store)))

(defun store-gc (store)
  (%wasmtime-context-gc (store-context store)))

(defun store-set-fuel (store amount)
  (let ((err (%wasmtime-context-set-fuel
              (store-context store) amount)))
    (check-wasmtime-error err)))

(defun store-get-fuel (store)
  (with-foreign-object (fuel :uint64)
    (let ((err (%wasmtime-context-get-fuel
                (store-context store) fuel)))
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
  (let ((len (length bytes)))
    (with-foreign-object (module-out :pointer)
      (with-foreign-object (wasm :uint8 len)
        (loop for i below len
              do (setf (mem-aref wasm :uint8 i)
                       (aref bytes i)))
        (let ((err (%wasmtime-module-new
                    (engine-pointer engine)
                    wasm len module-out)))
          (check-wasmtime-error err)
          (let* ((ptr (mem-ref module-out :pointer))
                 (mod (make-instance 'module
                                     :pointer ptr
                                     :engine engine)))
            (tg:finalize mod
                         (lambda ()
                           (%wasmtime-module-delete ptr)))
            mod))))))

(defun load-module-from-file (engine path)
  (load-module engine (read-file-into-byte-vector path)))

(defun read-file-into-byte-vector (path)
  (with-open-file (stream path
                          :element-type '(unsigned-byte 8))
    (let* ((len (file-length stream))
           (vec (make-array len
                            :element-type '(unsigned-byte 8))))
      (read-sequence vec stream)
      vec)))

(defun load-module-from-wat (engine wat-string)
  (load-module engine (wat->wasm wat-string)))

(defun validate-module (engine bytes)
  (let ((len (length bytes)))
    (with-foreign-object (wasm :uint8 len)
      (loop for i below len
            do (setf (mem-aref wasm :uint8 i)
                     (aref bytes i)))
      (let ((err (%wasmtime-module-validate
                  (engine-pointer engine) wasm len)))
        (check-wasmtime-error err)
        t))))

(defun module-imports (module)
  (with-foreign-object (vec '(:struct wasm-importtype-vec-t))
    (%wasmtime-module-imports (module-pointer module) vec)
    (let* ((size (foreign-slot-value
                  vec '(:struct wasm-importtype-vec-t) 'size))
           (data (foreign-slot-value
                  vec '(:struct wasm-importtype-vec-t) 'data))
           (result
             (loop for i below size
                   collect (parse-importtype
                            (mem-aref data :pointer i)))))
      (%wasm-importtype-vec-delete vec)
      result)))

(defun parse-importtype (ptr)
  (let* ((mod-vec (%wasm-importtype-module ptr))
         (name-vec (%wasm-importtype-name ptr))
         (ext-type (%wasm-importtype-type ptr)))
    (list (byte-vec-to-string mod-vec)
          (byte-vec-to-string name-vec)
          (extern-kind-symbol
           (%wasm-externtype-kind ext-type)))))

(defun module-exports (module)
  (with-foreign-object (vec '(:struct wasm-exporttype-vec-t))
    (%wasmtime-module-exports (module-pointer module) vec)
    (let* ((size (foreign-slot-value
                  vec '(:struct wasm-exporttype-vec-t) 'size))
           (data (foreign-slot-value
                  vec '(:struct wasm-exporttype-vec-t) 'data))
           (result
             (loop for i below size
                   collect (parse-exporttype
                            (mem-aref data :pointer i)))))
      (%wasm-exporttype-vec-delete vec)
      result)))

(defun parse-exporttype (ptr)
  (let* ((name-vec (%wasm-exporttype-name ptr))
         (ext-type (%wasm-exporttype-type ptr)))
    (list (byte-vec-to-string name-vec)
          (extern-kind-symbol
           (%wasm-externtype-kind ext-type)))))

(defun byte-vec-to-string (vec-ptr)
  (let ((size (foreign-slot-value
               vec-ptr '(:struct wasm-byte-vec-t) 'size))
        (data (foreign-slot-value
               vec-ptr '(:struct wasm-byte-vec-t) 'data)))
    (foreign-string-to-lisp data :count size)))

(defun extern-kind-symbol (kind)
  (case kind
    (#.+wasmtime-extern-func+ :func)
    (#.+wasmtime-extern-global+ :global)
    (#.+wasmtime-extern-table+ :table)
    (#.+wasmtime-extern-memory+ :memory)
    (otherwise :unknown)))

(defun module-serialize (module)
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (let ((err (%wasmtime-module-serialize
                (module-pointer module) vec)))
      (check-wasmtime-error err)
      (let* ((size (foreign-slot-value
                    vec '(:struct wasm-byte-vec-t) 'size))
             (data (foreign-slot-value
                    vec '(:struct wasm-byte-vec-t) 'data))
             (result (make-array
                      size
                      :element-type '(unsigned-byte 8))))
        (loop for i below size
              do (setf (aref result i)
                       (mem-aref data :uint8 i)))
        (%wasm-byte-vec-delete vec)
        result))))

(defun module-deserialize (engine bytes)
  (let ((len (length bytes)))
    (with-foreign-objects ((module-out :pointer)
                           (data :uint8 len))
      (loop for i below len
            do (setf (mem-aref data :uint8 i)
                     (aref bytes i)))
      (let ((err (%wasmtime-module-deserialize
                  (engine-pointer engine)
                  data len module-out)))
        (check-wasmtime-error err)
        (let* ((ptr (mem-ref module-out :pointer))
               (mod (make-instance 'module
                                   :pointer ptr
                                   :engine engine)))
          (tg:finalize mod
                       (lambda ()
                         (%wasmtime-module-delete ptr)))
          mod)))))

(defun module-serialize-to-file (module path)
  (let ((bytes (module-serialize module)))
    (with-open-file (stream path
                            :direction :output
                            :element-type '(unsigned-byte 8)
                            :if-exists :supersede)
      (write-sequence bytes stream))
    path))

(defun module-deserialize-from-file (engine path)
  (module-deserialize engine
                      (read-file-into-byte-vector path)))

(defun module-clone (module)
  (let* ((ptr (%wasmtime-module-clone
               (module-pointer module)))
         (mod (make-instance 'module
                             :pointer ptr
                             :engine (module-engine module))))
    (tg:finalize mod
                 (lambda () (%wasmtime-module-delete ptr)))
    mod))

;;; ============================================================
;;; LINKER
;;; ============================================================

(defclass linker ()
  ((pointer :initarg :pointer
            :reader linker-pointer)
   (engine :initarg :engine
           :reader linker-engine)
   ;; Cons cell (ids . nil) shared with finalizer so
   ;; GC cleanup sees IDs pushed after construction.
   (callback-ids :initform (cons nil nil)
                 :reader linker-callback-ids)))

(defun make-linker (engine)
  (let* ((ptr (%wasmtime-linker-new
               (engine-pointer engine)))
         (linker (make-instance 'linker
                                :pointer ptr
                                :engine engine))
         (ids (linker-callback-ids linker)))
    (tg:finalize linker
                 (lambda ()
                   (dolist (id (car ids))
                     (remhash id *callback-registry*))
                   (%wasmtime-linker-delete ptr)))
    linker))

(defun linker-allow-shadowing (linker allow)
  (%wasmtime-linker-allow-shadowing
   (linker-pointer linker) allow))

(defun linker-define (linker store module-name
                      field-name extern)
  (let ((mod-len (length module-name))
        (field-len (length field-name)))
    (with-foreign-object (ext '(:struct wasmtime-extern-t))
      (extern-to-c extern ext)
      (let ((err (%wasmtime-linker-define
                  (linker-pointer linker)
                  (store-context store)
                  module-name mod-len
                  field-name field-len
                  ext)))
        (check-wasmtime-error err)))))

(defun linker-define-wasi (linker)
  (let ((err (%wasmtime-linker-define-wasi
              (linker-pointer linker))))
    (check-wasmtime-error err)))

(defun linker-instantiate (linker store module)
  (with-foreign-objects
      ((inst-out '(:struct wasmtime-instance-t))
       (trap-out :pointer))
    (setf (mem-ref trap-out :pointer) (null-pointer))
    (let ((err (%wasmtime-linker-instantiate
                (linker-pointer linker)
                (store-context store)
                (module-pointer module)
                inst-out trap-out)))
      (check-wasmtime-error err trap-out)
      (make-instance
       'instance
       :store-id (foreign-slot-value
                  inst-out
                  '(:struct wasmtime-instance-t)
                  'store-id)
       :index (foreign-slot-value
               inst-out
               '(:struct wasmtime-instance-t)
               'index)
       :store store))))

(defun linker-get (linker store module-name field-name)
  (with-foreign-object (ext '(:struct wasmtime-extern-t))
    (let* ((ctx (store-context store))
           (found (%wasmtime-linker-get
                   (linker-pointer linker) ctx
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
  (let ((n (length imports)))
    (with-foreign-objects
        ((inst-out '(:struct wasmtime-instance-t))
         (trap-out :pointer)
         (imports-arr '(:struct wasmtime-extern-t) n))
      (setf (mem-ref trap-out :pointer) (null-pointer))
      (loop for i below n
            for imp in imports
            do (extern-to-c
                imp
                (mem-aptr imports-arr
                          '(:struct wasmtime-extern-t) i)))
      (let ((err (%wasmtime-instance-new
                  (store-context store)
                  (module-pointer module)
                  imports-arr n
                  inst-out trap-out)))
        (check-wasmtime-error err trap-out)
        (make-instance
         'instance
         :store-id (foreign-slot-value
                    inst-out
                    '(:struct wasmtime-instance-t)
                    'store-id)
         :index (foreign-slot-value
                 inst-out
                 '(:struct wasmtime-instance-t)
                 'index)
         :store store)))))

(defun instance-export (instance name)
  (with-foreign-objects
      ((ext '(:struct wasmtime-extern-t))
       (inst '(:struct wasmtime-instance-t)))
    (setf (foreign-slot-value
           inst '(:struct wasmtime-instance-t) 'store-id)
          (instance-store-id instance))
    (setf (foreign-slot-value
           inst '(:struct wasmtime-instance-t) 'index)
          (instance-index instance))
    (let* ((store (instance-store instance))
           (ctx (store-context store))
           (found (%wasmtime-instance-export-get
                   ctx inst name (length name) ext)))
      (when found
        (extern-from-c ext store)))))

(defun instance-exports (instance)
  (let* ((store (instance-store instance))
         (ctx (store-context store))
         (result nil))
    (with-foreign-objects
        ((inst '(:struct wasmtime-instance-t))
         (ext '(:struct wasmtime-extern-t))
         (name-out :pointer)
         (name-len-out :size))
      (setf (foreign-slot-value
             inst '(:struct wasmtime-instance-t) 'store-id)
            (instance-store-id instance))
      (setf (foreign-slot-value
             inst '(:struct wasmtime-instance-t) 'index)
            (instance-index instance))
      (loop for i from 0
            while (%wasmtime-instance-export-nth
                   ctx inst i
                   name-out name-len-out ext)
            do (push (cons (foreign-string-to-lisp
                            (mem-ref name-out :pointer)
                            :count (mem-ref name-len-out
                                            :size))
                           (extern-from-c ext store))
                     result)))
    (nreverse result)))

;;; ============================================================
;;; C STRUCT HELPERS
;;; ============================================================

(defun memcpy (dst src n)
  (loop for i below n
        do (setf (mem-aref dst :uint8 i)
                 (mem-aref src :uint8 i))))

(defmacro with-func-c ((var func) &body body)
  `(with-foreign-object
       (,var '(:struct wasmtime-func-t))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-func-t) 'store-id)
           (func-store-id ,func))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-func-t) 'index)
           (func-index ,func))
     ,@body))

(defmacro with-memory-c ((var memory) &body body)
  `(with-foreign-object
       (,var '(:struct wasmtime-memory-t))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-memory-t) 'store-id)
           (memory-store-id ,memory))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-memory-t) 'index)
           (memory-index ,memory))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-memory-t)
            'index-reserved)
           0)
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-memory-t) 'index2)
           (memory-index2 ,memory))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-memory-t)
            'index2-reserved)
           0)
     ,@body))

(defmacro with-global-c ((var global) &body body)
  `(with-foreign-object
       (,var '(:struct wasmtime-global-t))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-global-t) 'store-id)
           (global-store-id ,global))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-global-t) 'index)
           (global-index ,global))
     ,@body))

(defmacro with-table-c ((var table) &body body)
  `(with-foreign-object
       (,var '(:struct wasmtime-table-t))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-table-t) 'store-id)
           (table-store-id ,table))
     (setf (foreign-slot-value
            ,var '(:struct wasmtime-table-t) 'index)
           (table-index ,table))
     ,@body))

;;; ============================================================
;;; EXTERN WRAPPER
;;; ============================================================

(defclass wasm-func ()
  ((store-id :initarg :store-id :reader func-store-id)
   (index :initarg :index :reader func-index)
   (store :initarg :store :reader func-store)
   (functype :initarg :functype
             :reader func-functype)))

(defclass wasm-memory ()
  ((store-id :initarg :store-id
             :reader memory-store-id)
   (index :initarg :index :reader memory-index)
   (index2 :initarg :index2 :reader memory-index2)
   (store :initarg :store :reader memory-store)))

(defclass wasm-global ()
  ((store-id :initarg :store-id
             :reader global-store-id)
   (index :initarg :index :reader global-index)
   (store :initarg :store :reader global-store)))

(defclass wasm-table ()
  ((store-id :initarg :store-id
             :reader table-store-id)
   (index :initarg :index :reader table-index)
   (store :initarg :store :reader table-store)))

(defun extern-from-c (ext-ptr store)
  (let ((kind (foreign-slot-value
               ext-ptr '(:struct wasmtime-extern-t) 'kind))
        (of (foreign-slot-pointer
             ext-ptr '(:struct wasmtime-extern-t) 'of))
        (ctx (store-context store)))
    (case kind
      (#.+wasmtime-extern-func+
       (with-foreign-object (s '(:struct wasmtime-func-t))
         (memcpy s of (foreign-type-size
                       '(:struct wasmtime-func-t)))
         (make-instance
          'wasm-func
          :store-id (foreign-slot-value
                     s '(:struct wasmtime-func-t)
                     'store-id)
          :index (foreign-slot-value
                  s '(:struct wasmtime-func-t) 'index)
          :store store
          :functype (%wasmtime-func-type ctx s))))
      (#.+wasmtime-extern-memory+
       (with-foreign-object
           (s '(:struct wasmtime-memory-t))
         (memcpy s of (foreign-type-size
                       '(:struct wasmtime-memory-t)))
         (make-instance
          'wasm-memory
          :store-id (foreign-slot-value
                     s '(:struct wasmtime-memory-t)
                     'store-id)
          :index (foreign-slot-value
                  s '(:struct wasmtime-memory-t)
                  'index)
          :index2 (foreign-slot-value
                   s '(:struct wasmtime-memory-t)
                   'index2)
          :store store)))
      (#.+wasmtime-extern-global+
       (with-foreign-object
           (s '(:struct wasmtime-global-t))
         (memcpy s of (foreign-type-size
                       '(:struct wasmtime-global-t)))
         (make-instance
          'wasm-global
          :store-id (foreign-slot-value
                     s '(:struct wasmtime-global-t)
                     'store-id)
          :index (foreign-slot-value
                  s '(:struct wasmtime-global-t)
                  'index)
          :store store)))
      (#.+wasmtime-extern-table+
       (with-foreign-object
           (s '(:struct wasmtime-table-t))
         (memcpy s of (foreign-type-size
                       '(:struct wasmtime-table-t)))
         (make-instance
          'wasm-table
          :store-id (foreign-slot-value
                     s '(:struct wasmtime-table-t)
                     'store-id)
          :index (foreign-slot-value
                  s '(:struct wasmtime-table-t)
                  'index)
          :store store))))))

(defun extern-to-c (extern ext-ptr)
  (let ((of (foreign-slot-pointer
             ext-ptr '(:struct wasmtime-extern-t) 'of)))
    (etypecase extern
      (wasm-func
       (setf (foreign-slot-value
              ext-ptr '(:struct wasmtime-extern-t) 'kind)
             +wasmtime-extern-func+)
       (with-func-c (s extern)
         (memcpy of s (foreign-type-size
                       '(:struct wasmtime-func-t)))))
      (wasm-memory
       (setf (foreign-slot-value
              ext-ptr '(:struct wasmtime-extern-t) 'kind)
             +wasmtime-extern-memory+)
       (with-memory-c (s extern)
         (memcpy of s (foreign-type-size
                       '(:struct wasmtime-memory-t)))))
      (wasm-global
       (setf (foreign-slot-value
              ext-ptr '(:struct wasmtime-extern-t) 'kind)
             +wasmtime-extern-global+)
       (with-global-c (s extern)
         (memcpy of s (foreign-type-size
                       '(:struct wasmtime-global-t)))))
      (wasm-table
       (setf (foreign-slot-value
              ext-ptr '(:struct wasmtime-extern-t) 'kind)
             +wasmtime-extern-table+)
       (with-table-c (s extern)
         (memcpy of s (foreign-type-size
                       '(:struct wasmtime-table-t))))))))

;;; ============================================================
;;; FUNCTION CALLS
;;; ============================================================

(defun call-function (func &rest args)
  (let* ((store (func-store func))
         (ctx (store-context store))
         (num-args (length args))
         (functype (or (func-functype func)
                       (get-func-type ctx func)))
         (result-count (functype-result-count functype))
         (param-types (functype-param-types functype))
         (expected (length param-types)))
    (when (/= num-args expected)
      (error "Function expects ~D argument~:P but got ~D."
             expected num-args))
    (with-func-c (func-c func)
      (with-foreign-objects
          ((args-c '(:struct wasmtime-val-t)
                   (max 1 num-args))
           (res-c '(:struct wasmtime-val-t)
                  (max 1 result-count))
           (trap-out :pointer))
        (setf (mem-ref trap-out :pointer) (null-pointer))
        (loop for i below num-args
              for arg in args
              for ptype in param-types
              do (lisp-to-wasm-val
                  arg
                  (mem-aptr args-c
                            '(:struct wasmtime-val-t) i)
                  ptype))
        (let ((err (%wasmtime-func-call
                    ctx func-c
                    args-c num-args
                    res-c result-count
                    trap-out)))
          (check-wasmtime-error err trap-out)
          (case result-count
            (0 (values))
            (1 (wasm-val-to-lisp
                (mem-aptr res-c
                          '(:struct wasmtime-val-t) 0)))
            (t (values-list
                (loop for i below result-count
                      collect
                      (wasm-val-to-lisp
                       (mem-aptr
                        res-c
                        '(:struct wasmtime-val-t)
                        i)))))))))))

(defun get-func-type (context func)
  (with-func-c (fc func)
    (%wasmtime-func-type context fc)))

(defun functype-result-count (functype)
  (let ((rv (%wasm-functype-results functype)))
    (foreign-slot-value
     rv '(:struct wasm-valtype-vec-t) 'size)))

(defun functype-param-types (functype)
  (let* ((pv (%wasm-functype-params functype))
         (size (foreign-slot-value
                pv '(:struct wasm-valtype-vec-t) 'size))
         (data (foreign-slot-value
                pv '(:struct wasm-valtype-vec-t) 'data)))
    (loop for i below size
          collect (%wasm-valtype-kind
                   (mem-aref data :pointer i)))))

;;; ============================================================
;;; VALUE CONVERSION
;;; ============================================================

(defun lisp-to-wasm-val (val val-ptr &optional type)
  (etypecase val
    (integer
     (let ((kind (cond
                   ((eql type +wasm-i32+) +wasm-i32+)
                   ((eql type +wasm-i64+) +wasm-i64+)
                   ((typep val '(signed-byte 32))
                    +wasm-i32+)
                   (t +wasm-i64+))))
       (setf (foreign-slot-value
              val-ptr '(:struct wasmtime-val-t) 'kind)
             kind)
       (setf (mem-ref
              (foreign-slot-pointer
               val-ptr '(:struct wasmtime-val-t) 'of)
              (if (= kind +wasm-i32+) :int32 :int64))
             val)))
    (single-float
     (setf (foreign-slot-value
            val-ptr '(:struct wasmtime-val-t) 'kind)
           +wasm-f32+)
     (setf (mem-ref
            (foreign-slot-pointer
             val-ptr '(:struct wasmtime-val-t) 'of)
            :float)
           val))
    (double-float
     (setf (foreign-slot-value
            val-ptr '(:struct wasmtime-val-t) 'kind)
           +wasm-f64+)
     (setf (mem-ref
            (foreign-slot-pointer
             val-ptr '(:struct wasmtime-val-t) 'of)
            :double)
           val))))

(defun wasm-val-to-lisp (val-ptr)
  (let ((kind (foreign-slot-value
               val-ptr '(:struct wasmtime-val-t) 'kind))
        (of (foreign-slot-pointer
             val-ptr '(:struct wasmtime-val-t) 'of)))
    (case kind
      (#.+wasm-i32+ (mem-ref of :int32))
      (#.+wasm-i64+ (mem-ref of :int64))
      (#.+wasm-f32+ (mem-ref of :float))
      (#.+wasm-f64+ (mem-ref of :double))
      (otherwise nil))))

(defun lisp-type-to-wasm-kind (type)
  (case type
    (:i32 +wasm-i32+)
    (:i64 +wasm-i64+)
    (:f32 +wasm-f32+)
    (:f64 +wasm-f64+)
    (:funcref +wasm-funcref+)
    (:externref +wasm-externref+)
    (otherwise (error "Unknown WASM type: ~A" type))))

;;; ============================================================
;;; MEMORY
;;; ============================================================

(defun make-memory (store min-pages &key max-pages)
  (with-foreign-objects
      ((limits '(:struct wasm-limits-t))
       (mem-out '(:struct wasmtime-memory-t)))
    (setf (foreign-slot-value
           limits '(:struct wasm-limits-t) 'min)
          min-pages)
    (setf (foreign-slot-value
           limits '(:struct wasm-limits-t) 'max)
          (or max-pages #xFFFFFFFF))
    (let* ((ctx (store-context store))
           (mt (%wasm-memorytype-new limits))
           (err (%wasmtime-memory-new ctx mt mem-out)))
      (%wasm-memorytype-delete mt)
      (check-wasmtime-error err)
      (make-instance
       'wasm-memory
       :store-id (foreign-slot-value
                  mem-out '(:struct wasmtime-memory-t)
                  'store-id)
       :index (foreign-slot-value
               mem-out '(:struct wasmtime-memory-t)
               'index)
       :index2 (foreign-slot-value
                mem-out '(:struct wasmtime-memory-t)
                'index2)
       :store store))))

(defun memory-data (memory)
  (with-memory-c (mc memory)
    (%wasmtime-memory-data
     (store-context (memory-store memory)) mc)))

(defun memory-data-size (memory)
  (with-memory-c (mc memory)
    (%wasmtime-memory-data-size
     (store-context (memory-store memory)) mc)))

(defun memory-size (memory)
  (with-memory-c (mc memory)
    (%wasmtime-memory-size
     (store-context (memory-store memory)) mc)))

(defun memory-grow (memory delta)
  (with-memory-c (mc memory)
    (with-foreign-object (prev :uint64)
      (let ((err (%wasmtime-memory-grow
                  (store-context (memory-store memory))
                  mc delta prev)))
        (check-wasmtime-error err)
        (mem-ref prev :uint64)))))

(defun memory-ref (memory offset)
  (with-memory-c (mc memory)
    (let* ((ctx (store-context (memory-store memory)))
           (size (%wasmtime-memory-data-size ctx mc)))
      (when (>= offset size)
        (error "Memory access out of bounds: ~
                offset ~D, size ~D" offset size))
      (mem-aref (%wasmtime-memory-data ctx mc)
                :uint8 offset))))

(defun (setf memory-ref) (value memory offset)
  (with-memory-c (mc memory)
    (let* ((ctx (store-context (memory-store memory)))
           (size (%wasmtime-memory-data-size ctx mc)))
      (when (>= offset size)
        (error "Memory access out of bounds: ~
                offset ~D, size ~D" offset size))
      (setf (mem-aref (%wasmtime-memory-data ctx mc)
                      :uint8 offset)
            value))))

;;; ============================================================
;;; GLOBAL
;;; ============================================================

(defun make-global (store valtype value &key (mutable nil))
  (with-foreign-objects
      ((val '(:struct wasmtime-val-t))
       (glob-out '(:struct wasmtime-global-t)))
    (lisp-to-wasm-val value val
                      (lisp-type-to-wasm-kind valtype))
    (let* ((ctx (store-context store))
           (vt (%wasm-valtype-new
                (lisp-type-to-wasm-kind valtype)))
           (mut (if mutable +wasm-var+ +wasm-const+))
           (gt (%wasm-globaltype-new vt mut))
           (err (%wasmtime-global-new
                 ctx gt val glob-out)))
      (%wasm-globaltype-delete gt)
      (check-wasmtime-error err)
      (make-instance
       'wasm-global
       :store-id (foreign-slot-value
                  glob-out
                  '(:struct wasmtime-global-t)
                  'store-id)
       :index (foreign-slot-value
               glob-out
               '(:struct wasmtime-global-t) 'index)
       :store store))))

(defun global-value (global)
  (with-global-c (gc global)
    (with-foreign-object (val '(:struct wasmtime-val-t))
      (%wasmtime-global-get
       (store-context (global-store global)) gc val)
      (wasm-val-to-lisp val))))

(defun (setf global-value) (value global)
  (with-global-c (gc global)
    (with-foreign-object (val '(:struct wasmtime-val-t))
      (lisp-to-wasm-val value val)
      (let ((err (%wasmtime-global-set
                  (store-context (global-store global))
                  gc val)))
        (check-wasmtime-error err)
        value))))

;;; ============================================================
;;; TABLE
;;; ============================================================

(defun make-table (store element-type min &key max init)
  (with-foreign-objects
      ((limits '(:struct wasm-limits-t))
       (tbl-out '(:struct wasmtime-table-t))
       (init-val '(:struct wasmtime-val-t)))
    (setf (foreign-slot-value
           limits '(:struct wasm-limits-t) 'min) min)
    (setf (foreign-slot-value
           limits '(:struct wasm-limits-t) 'max)
          (or max #xffffffff))
    (if init
        (lisp-to-wasm-val init init-val)
        (setf (foreign-slot-value
               init-val '(:struct wasmtime-val-t) 'kind)
              (lisp-type-to-wasm-kind element-type)))
    (let* ((vt (%wasm-valtype-new
                (lisp-type-to-wasm-kind element-type)))
           (tt (%wasm-tabletype-new vt limits))
           (err (%wasmtime-table-new
                 (store-context store) tt
                 init-val tbl-out)))
      (%wasm-tabletype-delete tt)
      (check-wasmtime-error err)
      (make-instance
       'wasm-table
       :store-id (foreign-slot-value
                  tbl-out '(:struct wasmtime-table-t)
                  'store-id)
       :index (foreign-slot-value
               tbl-out '(:struct wasmtime-table-t)
               'index)
       :store store))))

(defun table-size (table)
  (with-table-c (tc table)
    (%wasmtime-table-size
     (store-context (table-store table)) tc)))

(defun table-get (table index)
  (with-table-c (tc table)
    (with-foreign-object (val '(:struct wasmtime-val-t))
      (when (%wasmtime-table-get
             (store-context (table-store table))
             tc index val)
        (wasm-val-to-lisp val)))))

(defun table-set (table index value)
  (with-table-c (tc table)
    (with-foreign-object (val '(:struct wasmtime-val-t))
      (lisp-to-wasm-val value val)
      (let ((err (%wasmtime-table-set
                  (store-context (table-store table))
                  tc index val)))
        (check-wasmtime-error err)
        value))))

(defun table-grow (table delta init)
  (with-table-c (tc table)
    (with-foreign-objects
        ((init-val '(:struct wasmtime-val-t))
         (prev :uint32))
      (lisp-to-wasm-val init init-val)
      (let ((err (%wasmtime-table-grow
                  (store-context (table-store table))
                  tc delta init-val prev)))
        (check-wasmtime-error err)
        (mem-ref prev :uint32)))))

;;; ============================================================
;;; WAT
;;; ============================================================

(defun wat->wasm (wat-string)
  (with-foreign-object (wv '(:struct wasm-byte-vec-t))
    (let ((err (%wasmtime-wat2wasm
                wat-string (length wat-string) wv)))
      (check-wasmtime-error err)
      (let* ((size (foreign-slot-value
                    wv '(:struct wasm-byte-vec-t) 'size))
             (data (foreign-slot-value
                    wv '(:struct wasm-byte-vec-t) 'data))
             (result (make-array
                      size
                      :element-type '(unsigned-byte 8))))
        (loop for i below size
              do (setf (aref result i)
                       (mem-aref data :uint8 i)))
        (%wasm-byte-vec-delete wv)
        result))))

;;; ============================================================
;;; WASI
;;; ============================================================

(defclass wasi-config ()
  ((pointer :initarg :pointer
            :reader wasi-config-pointer)))

(defun make-wasi-config ()
  (let* ((ptr (%wasi-config-new))
         (cfg (make-instance 'wasi-config :pointer ptr)))
    (tg:finalize cfg
                 (lambda () (%wasi-config-delete ptr)))
    cfg))

(defun wasi-config-inherit-stdio (config)
  (let ((p (wasi-config-pointer config)))
    (%wasi-config-inherit-stdin p)
    (%wasi-config-inherit-stdout p)
    (%wasi-config-inherit-stderr p)))

(defun wasi-config-inherit-argv (config)
  (%wasi-config-inherit-argv
   (wasi-config-pointer config)))

(defun wasi-config-inherit-env (config)
  (%wasi-config-inherit-env
   (wasi-config-pointer config)))

(defun wasi-config-set-argv (config args)
  (let ((argc (length args)))
    (with-foreign-object (argv :pointer argc)
      (loop for i below argc
            for arg in args
            do (setf (mem-aref argv :pointer i)
                     (foreign-string-alloc arg)))
      (%wasi-config-set-argv
       (wasi-config-pointer config) argc argv)
      (loop for i below argc
            do (foreign-string-free
                (mem-aref argv :pointer i))))))

(defun wasi-config-set-env (config env)
  (let ((envc (length env)))
    (with-foreign-objects ((names :pointer envc)
                           (vals :pointer envc))
      (loop for i below envc
            for (name . value) in env
            do (setf (mem-aref names :pointer i)
                     (foreign-string-alloc name))
               (setf (mem-aref vals :pointer i)
                     (foreign-string-alloc value)))
      (%wasi-config-set-env
       (wasi-config-pointer config) envc names vals)
      (loop for i below envc
            do (foreign-string-free
                (mem-aref names :pointer i))
               (foreign-string-free
                (mem-aref vals :pointer i))))))

(defun wasi-config-preopen-dir (config host-path
                                guest-path)
  (unless (%wasi-config-preopen-dir
           (wasi-config-pointer config)
           host-path guest-path)
    (error 'wasmtime-error
           :message "Failed to preopen directory")))

(defun store-set-wasi (store wasi-config)
  (tg:cancel-finalization wasi-config)
  (let ((err (%wasmtime-context-set-wasi
              (store-context store)
              (wasi-config-pointer wasi-config))))
    (check-wasmtime-error err)))

;;; ============================================================
;;; HOST CALLBACKS
;;; ============================================================

(defcallback host-func-trampoline :pointer
    ((env :pointer)
     (caller wasmtime-caller-t)
     (args :pointer)
     (nargs :size)
     (results :pointer)
     (nresults :size))
  (declare (ignore caller))
  (handler-case
      (let* ((id (pointer-address env))
             (fn (gethash id *callback-registry*)))
        (when fn
          (let* ((lisp-args
                   (loop for i below nargs
                         collect
                         (wasm-val-to-lisp
                          (mem-aptr
                           args
                           '(:struct wasmtime-val-t)
                           i))))
                 (lisp-results
                   (multiple-value-list
                    (apply fn lisp-args))))
            (when (/= (length lisp-results) nresults)
              (error "Host function returned ~D ~
                      values but expected ~D"
                     (length lisp-results) nresults))
            (loop for i below nresults
                  for r in lisp-results
                  do (lisp-to-wasm-val
                      r
                      (mem-aptr
                       results
                       '(:struct wasmtime-val-t)
                       i)))))
        (null-pointer))
    (error (e)
      (let ((msg (format nil "~A" e)))
        (%wasmtime-trap-new msg (length msg))))))

(defun make-functype (params results)
  (with-foreign-objects
      ((pvec '(:struct wasm-valtype-vec-t))
       (rvec '(:struct wasm-valtype-vec-t)))
    (let ((np (length params))
          (nr (length results)))
      (if (zerop np)
          (%wasm-valtype-vec-new-empty pvec)
          (with-foreign-object (pa :pointer np)
            (loop for i below np
                  for p in params
                  do (setf (mem-aref pa :pointer i)
                           (%wasm-valtype-new
                            (lisp-type-to-wasm-kind p))))
            (%wasm-valtype-vec-new pvec np pa)))
      (if (zerop nr)
          (%wasm-valtype-vec-new-empty rvec)
          (with-foreign-object (ra :pointer nr)
            (loop for i below nr
                  for r in results
                  do (setf (mem-aref ra :pointer i)
                           (%wasm-valtype-new
                            (lisp-type-to-wasm-kind r))))
            (%wasm-valtype-vec-new rvec nr ra)))
      (%wasm-functype-new pvec rvec))))

(defun make-host-function (store params results fn)
  (let* ((id (incf *callback-counter*))
         (functype (make-functype params results))
         (func nil))
    (unwind-protect
         (progn
           (setf (gethash id *callback-registry*) fn)
           (with-foreign-object
               (fout '(:struct wasmtime-func-t))
             (%wasmtime-func-new
              (store-context store)
              functype
              (callback host-func-trampoline)
              (make-pointer id)
              (null-pointer)
              fout)
             (setf func
                   (make-instance
                    'wasm-func
                    :store-id
                    (foreign-slot-value
                     fout '(:struct wasmtime-func-t)
                     'store-id)
                    :index
                    (foreign-slot-value
                     fout '(:struct wasmtime-func-t)
                     'index)
                    :store store
                    :functype functype))
             (tg:finalize
              func
              (lambda ()
                (%wasm-functype-delete functype)
                (remhash id *callback-registry*)))
             func))
      (unless func
        (%wasm-functype-delete functype)
        (remhash id *callback-registry*)))))

(defun linker-define-func (linker module-name field-name
                           params results fn)
  (let* ((id (incf *callback-counter*))
         (functype (make-functype params results)))
    (setf (gethash id *callback-registry*) fn)
    (push id (car (linker-callback-ids linker)))
    (let ((err (%wasmtime-linker-define-func
                (linker-pointer linker)
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
  (let ((len (length bytes)))
    (with-foreign-object (out :pointer)
      (with-foreign-object (wasm :uint8 len)
        (loop for i below len
              do (setf (mem-aref wasm :uint8 i)
                       (aref bytes i)))
        (let ((err (%wasmtime-component-new
                    (engine-pointer engine)
                    wasm len out)))
          (check-wasmtime-error err)
          (let* ((ptr (mem-ref out :pointer))
                 (comp (make-instance 'component
                                      :pointer ptr
                                      :engine engine)))
            (tg:finalize
             comp
             (lambda ()
               (%wasmtime-component-delete ptr)))
            comp))))))

(defun load-component-from-file (engine path)
  (load-component engine
                  (read-file-into-byte-vector path)))

(defun component-clone (component)
  (let* ((ptr (%wasmtime-component-clone
               (component-pointer component)))
         (comp (make-instance
                'component
                :pointer ptr
                :engine (component-engine component))))
    (tg:finalize
     comp (lambda ()
            (%wasmtime-component-delete ptr)))
    comp))

(defun component-serialize (component)
  (with-foreign-object (vec '(:struct wasm-byte-vec-t))
    (let ((err (%wasmtime-component-serialize
                (component-pointer component) vec)))
      (check-wasmtime-error err)
      (let* ((size (foreign-slot-value
                    vec '(:struct wasm-byte-vec-t)
                    'size))
             (data (foreign-slot-value
                    vec '(:struct wasm-byte-vec-t)
                    'data))
             (result (make-array
                      size
                      :element-type '(unsigned-byte 8))))
        (loop for i below size
              do (setf (aref result i)
                       (mem-aref data :uint8 i)))
        (%wasm-byte-vec-delete vec)
        result))))

(defun component-deserialize (engine bytes)
  (let ((len (length bytes)))
    (with-foreign-objects ((out :pointer)
                           (data :uint8 len))
      (loop for i below len
            do (setf (mem-aref data :uint8 i)
                     (aref bytes i)))
      (let ((err (%wasmtime-component-deserialize
                  (engine-pointer engine)
                  data len out)))
        (check-wasmtime-error err)
        (let* ((ptr (mem-ref out :pointer))
               (comp (make-instance 'component
                                    :pointer ptr
                                    :engine engine)))
          (tg:finalize
           comp
           (lambda ()
             (%wasmtime-component-delete ptr)))
          comp)))))

(defun component-serialize-to-file (component path)
  (let ((bytes (component-serialize component)))
    (with-open-file (stream path
                            :direction :output
                            :element-type '(unsigned-byte 8)
                            :if-exists :supersede)
      (write-sequence bytes stream))
    path))

(defun component-deserialize-from-file (engine path)
  (component-deserialize
   engine (read-file-into-byte-vector path)))

;;; ============================================================
;;; COMPONENT LINKER
;;; ============================================================

(defclass component-linker ()
  ((pointer :initarg :pointer
            :reader component-linker-pointer)
   (engine :initarg :engine
           :reader component-linker-engine)))

(defun make-component-linker (engine)
  (let* ((ptr (%wasmtime-component-linker-new
               (engine-pointer engine)))
         (linker (make-instance 'component-linker
                                :pointer ptr
                                :engine engine)))
    (tg:finalize
     linker
     (lambda ()
       (%wasmtime-component-linker-delete ptr)))
    linker))

(defun component-linker-add-wasi (linker)
  (let ((err (%wasmtime-component-linker-add-wasip2
              (component-linker-pointer linker))))
    (check-wasmtime-error err)))

(defclass component-linker-instance ()
  ((pointer :initarg :pointer
            :reader component-linker-instance-pointer)
   (linker :initarg :linker
           :reader component-linker-instance-linker)))

(defun component-linker-root (linker)
  (with-foreign-object (out :pointer)
    (%wasmtime-component-linker-root
     (component-linker-pointer linker) out)
    (make-instance
     'component-linker-instance
     :pointer (mem-ref out :pointer)
     :linker linker)))

(defun component-linker-instance-add-instance
    (instance name)
  (with-foreign-object (child-out :pointer)
    (let ((err
            (%wasmtime-component-linker-instance-add-instance
             (component-linker-instance-pointer instance)
             name (length name)
             child-out)))
      (check-wasmtime-error err)
      (make-instance
       'component-linker-instance
       :pointer (mem-ref child-out :pointer)
       :linker (component-linker-instance-linker
                instance)))))

(defun component-linker-instance-add-module
    (instance name module)
  (let ((err
          (%wasmtime-component-linker-instance-add-module
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

(defun component-linker-instantiate (linker store
                                     component)
  (with-foreign-objects
      ((inst-out
        '(:struct wasmtime-component-instance-t))
       (trap-out :pointer))
    (setf (mem-ref trap-out :pointer) (null-pointer))
    (let ((err (%wasmtime-component-linker-instantiate
                (component-linker-pointer linker)
                (store-context store)
                (component-pointer component)
                inst-out trap-out)))
      (check-wasmtime-error err trap-out)
      (make-instance
       'component-instance
       :store-id
       (foreign-slot-value
        inst-out
        '(:struct wasmtime-component-instance-t)
        'store-id)
       :index
       (foreign-slot-value
        inst-out
        '(:struct wasmtime-component-instance-t)
        'index)
       :store store))))

(defun component-instance-export (instance name)
  (with-foreign-objects
      ((inst '(:struct wasmtime-component-instance-t))
       (fout '(:struct wasmtime-func-t)))
    (setf (foreign-slot-value
           inst
           '(:struct wasmtime-component-instance-t)
           'store-id)
          (component-instance-store-id instance))
    (setf (foreign-slot-value
           inst
           '(:struct wasmtime-component-instance-t)
           'index)
          (component-instance-index instance))
    (let* ((store (component-instance-store instance))
           (ctx (store-context store))
           (found
             (%wasmtime-component-instance-export-get
              ctx inst name (length name) fout)))
      (when found
        (make-instance
         'wasm-func
         :store-id (foreign-slot-value
                    fout '(:struct wasmtime-func-t)
                    'store-id)
         :index (foreign-slot-value
                 fout '(:struct wasmtime-func-t)
                 'index)
         :store store
         :functype (%wasmtime-func-type
                    ctx fout))))))

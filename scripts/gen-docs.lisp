(require :asdf)
(require :staple)

(asdf:load-system "cl-wasmtime")

(let* ((project (asdf:find-system "cl-wasmtime"))
       (base-path (asdf:system-source-directory project))
       (output-path (merge-pathnames #p"docs/" base-path)))
  (ensure-directories-exist output-path)
  (staple:generate project :output-directory output-path))

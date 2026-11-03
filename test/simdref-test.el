;;; simdref-test.el --- ERT tests for simdref.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marco Barbone

;; Author: Marco Barbone <mbarbone@flatironinstitute.org>

;;; Commentary:

;; Each test drives `simdref-maintain', the real entry point, with fake
;; uv, isa, rass and clangd scripts that log their argv.  Run with:
;;   emacs -Q --batch -L . -l test/simdref-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defconst simdref-test--root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "Root of the emacs-simdref checkout.")

(defconst simdref-test--fakes
  (expand-file-name "test/fakes" simdref-test--root)
  "Directory that holds the fake executables.")

(defun simdref-test--fake (name)
  "Return the path of the fake script NAME."
  (expand-file-name name simdref-test--fakes))

;; Loading simdref.el runs one maintenance pass.  Give it a complete
;; managed install and today's marker in the default install dir, so
;; that pass spawns nothing and every test stays offline.
(setq user-emacs-directory
      (file-name-as-directory (make-temp-file "simdref-test-home" t)))
(let* ((dir (locate-user-emacs-file "simdref/"))
       (server (expand-file-name "bin/simdref-lsp" dir)))
  (make-directory (file-name-directory server) t)
  (copy-file (simdref-test--fake "server.sh") server t)
  (set-file-modes server #o755)
  (write-region "" nil (expand-file-name "installed" dir))
  (write-region "" nil
                (expand-file-name (format "update-%d" (floor (float-time) 86400)) dir)))

(require 'simdref)

(defvar simdref-test--log nil
  "Path of the argv log that the fakes append to.")

(defun simdref-test--log-contents ()
  "Return the current argv log contents."
  (if (file-exists-p simdref-test--log)
      (with-temp-buffer
        (insert-file-contents simdref-test--log)
        (buffer-string))
    ""))

(defun simdref-test--reflog ()
  "Return the contents of the `*simdref-log*' buffer."
  (if (get-buffer "*simdref-log*")
      (with-current-buffer "*simdref-log*" (buffer-string))
    ""))

(defun simdref-test--messages ()
  "Return the contents of the `*Messages*' buffer."
  (if (get-buffer "*Messages*")
      (with-current-buffer "*Messages*" (buffer-string))
    ""))

(defun simdref-test--clear-messages ()
  "Erase the `*Messages*' buffer."
  (with-current-buffer (get-buffer-create "*Messages*")
    (let ((inhibit-read-only t))
      (erase-buffer))))

(defun simdref-test--count (regexp string)
  "Count the matches of REGEXP in STRING."
  (let ((n 0) (start 0))
    (while (string-match regexp string start)
      (setq n (1+ n)
            start (match-end 0)))
    n))

(defun simdref-test--wait (pred &optional seconds)
  "Run the event loop until PRED returns non-nil.  Wait at most SECONDS."
  (let ((deadline (+ (float-time) (or seconds 60))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall pred)))

(defvar simdref-test--lines nil
  "Recorded `message' lines of the current capture.")

(defun simdref-test--capture (fn)
  "Run FN with `message' recording onto `simdref-test--lines'.
Return the recorded lines.  The real `message' still runs, so
`*Messages*' stays accurate.  The tests check `*Warnings*' against
the real `display-warning'."
  (let ((simdref-test--lines nil)
        (real (symbol-function 'message)))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (let ((line (apply #'format fmt args)))
                   (push line simdref-test--lines)
                   (apply real fmt args)))))
      (funcall fn))
    (nreverse simdref-test--lines)))

(defun simdref-test--simdref-messages (lines)
  "Return the lines in LINES that the package echoed."
  (cl-remove-if-not (lambda (l) (string-prefix-p "simdref: " l)) lines))

(defvar simdref-test--tmp-root nil
  "Install dir of the current sandbox.")

(defmacro simdref-test--with-sandbox (&rest body)
  "Run BODY with a fresh install dir, a fresh argv log and a fresh session.
The install dir starts out missing: the package must create it."
  (declare (indent 0) (debug t))
  `(let* ((tmp (make-temp-file "simdref-test" t))
          (simdref-test--tmp-root
           (directory-file-name (expand-file-name "install" tmp)))
          (simdref-install-dir (file-name-as-directory simdref-test--tmp-root))
          (simdref-test--log (expand-file-name "argv.log" tmp))
          (process-environment
           (append (list (format "SIMDREF_TEST_LOG=%s" simdref-test--log)
                         (format "SIMDREF_TEST_FAKE_ISA=%s" (simdref-test--fake "isa.sh"))
                         (format "SIMDREF_TEST_FAKE_RASS=%s" (simdref-test--fake "rass.sh"))
                         (format "SIMDREF_TEST_FAKE_LSP=%s" (simdref-test--fake "server.sh")))
                   process-environment))
          (simdref--installing nil)
          (simdref--notice-shown nil))
     (when (get-buffer "*simdref-log*")
       (kill-buffer "*simdref-log*"))
     ,@body))

(defun simdref-test--put (src dst)
  "Copy the executable SRC to DST."
  (make-directory (file-name-directory dst) t)
  (copy-file src dst t)
  (set-file-modes dst #o755))

(defun simdref-test--setup-daily ()
  "Place the fake uv, isa, rass and server where the daily check finds them.
This is a complete install: the server, the tools and the stamp."
  (simdref-test--put (simdref-test--fake "uv.sh")
                     (expand-file-name "uv/uv" simdref-test--tmp-root))
  (simdref-test--put (simdref-test--fake "isa.sh")
                     (expand-file-name "bin/isa" simdref-test--tmp-root))
  (simdref-test--put (simdref-test--fake "rass.sh")
                     (expand-file-name "bin/rass" simdref-test--tmp-root))
  (simdref-test--put (simdref-test--fake "server.sh")
                     (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root))
  (write-region "" nil (expand-file-name "installed" simdref-test--tmp-root)))

(defun simdref-test--claim-today ()
  "Write today's marker, so `simdref-maintain' spawns nothing."
  (write-region "" nil
                (expand-file-name (format "update-%d" (floor (float-time) 86400))
                                  simdref-test--tmp-root)))

(defun simdref-test--stage-uv (tmp corrupt)
  "Stage a uv archive and sidecar under TMP.  Return the base file URL.
When CORRUPT is non-nil the sidecar holds a wrong hash."
  (let* ((target (or (simdref--uv-target) (error "no uv target for this machine")))
         (work (expand-file-name "work" tmp))
         (stage (expand-file-name "stage" tmp))
         (top (format "uv-%s" target))
         (inner (expand-file-name top work)))
    (make-directory inner t)
    (make-directory stage t)
    (simdref-test--put (simdref-test--fake "uv.sh") (expand-file-name "uv" inner))
    (should (zerop (call-process "tar" nil nil nil
                                 "-czf" (expand-file-name (format "%s.tar.gz" top) stage)
                                 "-C" work top)))
    (let ((archive (expand-file-name (format "%s.tar.gz" top) stage)))
      (with-temp-file (concat archive ".sha256")
        (insert (if corrupt
                    (make-string 64 ?0)
                  (with-temp-buffer
                    (insert-file-contents-literally archive)
                    (secure-hash 'sha256 (current-buffer))))
                "  " (format "%s.tar.gz" top) "\n"))
      (concat "file://" stage "/"))))

(ert-deftest simdref-test-fakes-parse-and-run ()
  "The fakes are valid shell scripts and they log their argv."
  (dolist (name '("uv.sh" "isa.sh" "rass.sh" "clangd.sh" "server.sh"))
    (should (zerop (call-process "sh" nil nil nil "-n" (simdref-test--fake name)))))
  (simdref-test--with-sandbox
    (let ((process-environment process-environment))
      (setenv "SIMDREF_TEST_UV_EXIT" "0")
      (setenv "UV_TOOL_BIN_DIR" (expand-file-name "bin" simdref-test--tmp-root))
      (call-process (simdref-test--fake "uv.sh") nil nil nil "tool" "install" "--force" "simdref")
      (call-process (simdref-test--fake "uv.sh") nil nil nil "tool" "install" "--force" "rassumfrassum")
      (call-process (simdref-test--fake "isa.sh") nil nil nil "update")
      (call-process (simdref-test--fake "server.sh") nil nil nil))
    ;; Positive control: the fakes above really ran and logged argv.
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p "uv tool install --force simdref" log))
      (should (string-match-p "uv tool install --force rassumfrassum" log))
      (should (string-match-p "isa update" log))
      (should (string-match-p "lsp" log)))))

(ert-deftest simdref-test-first-install ()
  "No server: install downloads pinned uv, installs simdref, runs isa update."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil))
          (stamp (expand-file-name "installed" simdref-test--tmp-root)))
      (simdref-maintain)
      ;; The stamp lands only when the whole chain exited 0.
      (should (simdref-test--wait (lambda () (file-exists-p stamp)) 120)))
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p "uv tool install --force simdref" log))
      (should (string-match-p "isa update" log))
      (should (< (string-match "uv tool install --force simdref" log)
                 (string-match "isa update" log))))
    (should (file-executable-p (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root)))))

(ert-deftest simdref-test-install-rejects-bad-sha ()
  "A wrong sha256 sidecar must stop the install before any uv run."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root t))
          (lines nil))
      (setq lines
            (simdref-test--capture
             (lambda ()
               (simdref-maintain)
               (should (simdref-test--wait
                        (lambda ()
                          (cl-find-if
                           (lambda (l) (string-match-p "checksum mismatch" l))
                           (simdref-test--simdref-messages simdref-test--lines)))
                        120)))))
      ;; The download ran for real; the sha check rejected it.
      (should (file-exists-p (expand-file-name "uv.tar.gz" simdref-test--tmp-root)))
      (should (not (string-match-p "tool install" (simdref-test--log-contents))))
      ;; The failure is one echo-area line, and it names the step.
      (let ((notice (cl-find-if
                     (lambda (l) (string-match-p "simdref-lsp not found" l))
                     (simdref-test--simdref-messages lines))))
        (should notice)
        (should (string-match-p "checksum mismatch" notice)))
      (should (not (get-buffer "*Warnings*"))))))

(ert-deftest simdref-test-daily-check ()
  "The daily check runs uv tool upgrade, then isa vaddps --short."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-maintain)
    (should (simdref-test--wait
             (lambda () (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p "uv tool upgrade simdref" log))
      (should (< (string-match "uv tool upgrade simdref" log)
                 (string-match "isa vaddps --short" log))))))

(ert-deftest simdref-test-throttle-skips-same-day ()
  "A same-day restart must not run the network step again."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-maintain)
    (should (simdref-test--wait
             (lambda () (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))
    (let ((before (simdref-test--log-contents)))
      (setq simdref--installing nil)  ; the marker throttle must cover a restart
      (simdref-maintain)
      (simdref-test--wait (lambda () nil) 1)
      (should (equal before (simdref-test--log-contents))))))

(ert-deftest simdref-test-todays-marker-kept ()
  "Cleanup deletes old markers but never today's marker."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (let* ((day (floor (float-time) 86400))
           (today (expand-file-name (format "update-%d" day) simdref-test--tmp-root))
           (old (expand-file-name (format "update-%d" (1- day)) simdref-test--tmp-root)))
      (write-region "" nil old)
      (simdref-maintain)
      (should (simdref-test--wait
               (lambda () (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))
      (should (file-exists-p today))
      (should (not (file-exists-p old))))))

(ert-deftest simdref-test-path-install-untouched ()
  "A simdref-lsp on PATH gets no upgrade and no isa call."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (let ((pdir (expand-file-name "pathbin" simdref-test--tmp-root)))
      (simdref-test--put (simdref-test--fake "server.sh")
                         (expand-file-name "simdref-lsp" pdir))
      (let ((exec-path (cons pdir exec-path)))
        (simdref-maintain)))
    (should (string-empty-p (simdref-test--log-contents)))
    (should (null (directory-files simdref-test--tmp-root nil "\\`update-")))))

(ert-deftest simdref-test-missing-executable-quiet ()
  "A missing executable pops no window and echoes one line naming the step."
  (simdref-test--with-sandbox
    (simdref-test--put (simdref-test--fake "server.sh")
                       (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root))
    (write-region "" nil (expand-file-name "installed" simdref-test--tmp-root))
    (let ((lines (simdref-test--capture #'simdref-maintain)))
      (should (string-match-p "spawn skipped" (simdref-test--reflog)))
      (let ((echo (cl-find-if
                   (lambda (l) (string-match-p "spawn skipped" l))
                   (simdref-test--simdref-messages lines))))
        (should echo)
        (should (string-match-p "uv tool upgrade simdref" echo)))
      (should (not (get-buffer "*Warnings*"))))))

(ert-deftest simdref-test-refresh-after-failed-upgrade ()
  "The catalog refresh runs even when the upgrade exits nonzero."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (setenv "SIMDREF_TEST_UV_EXIT" "1")
    (simdref-maintain)
    (should (simdref-test--wait
             (lambda () (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))
    (should (string-match-p "uv tool upgrade simdref" (simdref-test--log-contents)))))

(ert-deftest simdref-test-nonzero-louder-than-success ()
  "A nonzero exit reaches the echo area.  Success stays in the log buffer."
  ;; Success: the line lands in `*simdref-log*', never in `*Messages*'.
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-test--clear-messages)
    (simdref-maintain)
    (should (simdref-test--wait
             (lambda ()
               (string-match-p "isa vaddps --short: ok" (simdref-test--reflog)))))
    (should (string-match-p "isa vaddps --short: ok" (simdref-test--reflog)))
    (should (not (string-match-p "simdref:" (simdref-test--messages))))
    (should (not (get-buffer "*Warnings*"))))
  ;; Nonzero: the failure reaches `*Messages*', still with no popup.
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (setenv "SIMDREF_TEST_UV_EXIT" "1")
    (simdref-test--clear-messages)
    (simdref-maintain)
    (should (simdref-test--wait
             (lambda ()
               (string-match-p "isa vaddps --short: ok" (simdref-test--reflog)))))
    (should (string-match-p "simdref: uv tool upgrade simdref: exit 1"
                            (simdref-test--messages)))
    (should (not (get-buffer "*Warnings*")))))

(ert-deftest simdref-test-failed-install-quiet ()
  "A failed first install pops no window and echoes one line, only once."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url "file:///nonexistent-simdref/")
          (lines nil))
      (setq lines
            (simdref-test--capture
             (lambda ()
               (simdref-maintain)
               (should (simdref-test--wait (lambda () (null simdref--installing)) 60))
               ;; A retry must not repeat the notice.
               (simdref-maintain)
               (should (simdref-test--wait (lambda () (null simdref--installing)) 60)))))
      (should (not (get-buffer "*Warnings*")))
      (let ((echo (simdref-test--simdref-messages lines)))
        (should (= 1 (length echo)))
        (should (string-prefix-p "simdref: " (car echo)))
        (should (string-match-p "simdref-lsp not found" (car echo)))
        (should (string-match-p "curl" (car echo)))))))

(ert-deftest simdref-test-eglot-contact-never-waits ()
  "With no server the contact signals `user-error' and returns within 1 s."
  (simdref-test--with-sandbox
    (let* ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil))
           (start (float-time))
           (err (should-error (simdref--eglot-contact) :type 'user-error)))
      (should (< (- (float-time) start) 1.0))
      (should (string-match-p "M-x eglot" (cadr err)))
      ;; The contact started the asynchronous install.
      (should simdref--installing)
      (should (not (get-buffer "*Warnings*")))
      ;; Drain the background install so no later test sees its messages.
      (should (simdref-test--wait (lambda () (null simdref--installing)) 60)))))

(ert-deftest simdref-test-failed-isa-update-no-stamp ()
  "A failed isa update leaves no stamp.  The next call reruns both steps."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil))
          (stamp (expand-file-name "installed" simdref-test--tmp-root)))
      (setenv "SIMDREF_TEST_ISA_EXIT" "1")
      (simdref-maintain)
      (should (simdref-test--wait (lambda () (null simdref--installing)) 60))
      (should (file-executable-p (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root)))
      (should (not (file-exists-p stamp)))
      (setenv "SIMDREF_TEST_ISA_EXIT" "0")
      (simdref-maintain)
      (should (simdref-test--wait (lambda () (file-exists-p stamp)) 60))
      (let ((log (simdref-test--log-contents)))
        (should (= 2 (simdref-test--count "uv tool install --force simdref" log)))
        (should (= 2 (simdref-test--count "isa update" log)))))))

(ert-deftest simdref-test-killed-uv-install-not-installed ()
  "A killed uv tool install is not installed, even with the lsp shim in place."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil))
          (simdref--timeout 2)
          (stamp (expand-file-name "installed" simdref-test--tmp-root)))
      (setenv "SIMDREF_TEST_UV_SLEEP" "60")
      (simdref-maintain)
      (should (simdref-test--wait (lambda () (null simdref--installing)) 60))
      ;; The shim exists, but the install never completed.
      (should (file-executable-p (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root)))
      (should (not (file-exists-p stamp)))
      (should (not (simdref--installed-p simdref-test--tmp-root)))
      ;; The next call reruns install and this time reaches isa update.
      (setenv "SIMDREF_TEST_UV_SLEEP" "0")
      (let ((before (simdref-test--log-contents)))
        (simdref-maintain)
        (should (simdref-test--wait (lambda () (file-exists-p stamp)) 60))
        (let ((new (substring (simdref-test--log-contents) (length before))))
          (should (string-match-p "uv tool install --force simdref" new))
          (should (string-match-p "isa update" new)))))))

(ert-deftest simdref-test-eglot-registration ()
  "eglot-server-programs maps every listed mode to the simdref contact."
  (require 'eglot)
  (dolist (mode simdref--modes)
    (should (memq mode '(asm-mode nasm-mode cuda-mode
                                  c-mode c++-mode c-ts-mode c++-ts-mode)))
    (should (cl-find-if
             (lambda (entry)
               (let ((modes (car entry)))
                 (and (memq mode (if (listp modes) modes (list modes)))
                      (eq (cdr entry) #'simdref--eglot-contact))))
             eglot-server-programs))))

(ert-deftest simdref-test-contact-cxx-rass-with-clangd ()
  "A C++ buffer with clangd runs rass with the simdref-rass.py preset.
The contact is rass PRESET -- simdref-lsp -- clangd: rass takes the
preset path as its first positional argument, and the preset makes
hover reach both servers.  The preset path is the file that ships
beside simdref.el, and it exists."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-test--claim-today)
    (let ((pdir (expand-file-name "pathbin" simdref-test--tmp-root)))
      (simdref-test--put (simdref-test--fake "clangd.sh")
                         (expand-file-name "clangd" pdir))
      (let* ((exec-path (list pdir))
             (contact (with-temp-buffer
                        (c++-mode)
                        (simdref--eglot-contact))))
        (should (equal contact
                       (list (expand-file-name "bin/rass" simdref-test--tmp-root)
                             (expand-file-name "simdref-rass.py"
                                               simdref-test--root)
                             "--"
                             (expand-file-name "bin/simdref-lsp"
                                               simdref-test--tmp-root)
                             "--" "clangd")))
        (should (file-exists-p (nth 1 contact)))))))

(ert-deftest simdref-test-contact-preset-missing-fallback ()
  "A missing preset file keeps the contact without the preset argument."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-test--claim-today)
    (let ((pdir (expand-file-name "pathbin" simdref-test--tmp-root))
          (simdref--preset-file (expand-file-name "no-such-preset.py"
                                                  simdref-test--tmp-root)))
      (simdref-test--put (simdref-test--fake "clangd.sh")
                         (expand-file-name "clangd" pdir))
      (let ((exec-path (list pdir)))
        (should (equal (with-temp-buffer
                         (c++-mode)
                         (simdref--eglot-contact))
                       (list (expand-file-name "bin/rass" simdref-test--tmp-root)
                             "--"
                             (expand-file-name "bin/simdref-lsp"
                                               simdref-test--tmp-root)
                             "--" "clangd")))))))

(ert-deftest simdref-test-contact-cxx-no-clangd ()
  "A C++ buffer with no clangd on exec-path runs simdref alone."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-test--claim-today)
    (let ((exec-path (list (expand-file-name "pathbin" simdref-test--tmp-root))))
      (should (equal (with-temp-buffer
                       (c++-mode)
                       (simdref--eglot-contact))
                     (list (expand-file-name "bin/simdref-lsp"
                                             simdref-test--tmp-root)))))))

(ert-deftest simdref-test-contact-companion-nil ()
  "A nil `simdref-companion-server' runs simdref alone."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-test--claim-today)
    (let ((pdir (expand-file-name "pathbin" simdref-test--tmp-root))
          (simdref-companion-server nil))
      (simdref-test--put (simdref-test--fake "clangd.sh")
                         (expand-file-name "clangd" pdir))
      (let ((exec-path (list pdir)))
        (should (equal (with-temp-buffer
                         (c++-mode)
                         (simdref--eglot-contact))
                       (list (expand-file-name "bin/simdref-lsp"
                                               simdref-test--tmp-root))))))))

(ert-deftest simdref-test-contact-asm-no-rass ()
  "An asm buffer runs simdref alone, even with clangd and rass present."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-test--claim-today)
    (let ((pdir (expand-file-name "pathbin" simdref-test--tmp-root)))
      (simdref-test--put (simdref-test--fake "clangd.sh")
                         (expand-file-name "clangd" pdir))
      (let ((exec-path (list pdir)))
        (should (equal (with-temp-buffer
                         (asm-mode)
                         (simdref--eglot-contact))
                       (list (expand-file-name "bin/simdref-lsp"
                                               simdref-test--tmp-root))))))))

(ert-deftest simdref-test-install-rass-step-stamp-last ()
  "The install runs the rass step, and the stamp lands only after it."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil))
          (stamp (expand-file-name "installed" simdref-test--tmp-root)))
      (setenv "SIMDREF_TEST_UV_RASS_SLEEP" "2")
      (simdref-maintain)
      ;; The rass step runs, and the stamp is not there while it runs.
      (should (simdref-test--wait
               (lambda ()
                 (string-match-p "tool install --force rassumfrassum"
                                 (simdref-test--log-contents)))
               60))
      (should (not (file-exists-p stamp)))
      (should (simdref-test--wait (lambda () (file-exists-p stamp)) 120))
      (setenv "SIMDREF_TEST_UV_RASS_SLEEP" "0"))
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p (regexp-quote
                               "uv tool install --force rassumfrassum>=0.3.5,<0.4")
                              log))
      (should (< (string-match "uv tool install --force rassumfrassum" log)
                 (string-match "isa update" log))))
    (should (file-executable-p (expand-file-name "bin/rass"
                                                 simdref-test--tmp-root)))))

(ert-deftest simdref-test-failed-rass-install-no-stamp ()
  "A failed rass install leaves no stamp.  The next call reruns the steps."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil))
          (stamp (expand-file-name "installed" simdref-test--tmp-root)))
      (setenv "SIMDREF_TEST_UV_RASS_EXIT" "1")
      (simdref-maintain)
      (should (simdref-test--wait (lambda () (null simdref--installing)) 60))
      (should (file-executable-p (expand-file-name "bin/simdref-lsp"
                                                   simdref-test--tmp-root)))
      (should (not (file-exists-p stamp)))
      (setenv "SIMDREF_TEST_UV_RASS_EXIT" "0")
      (simdref-maintain)
      (should (simdref-test--wait (lambda () (file-exists-p stamp)) 60))
      (should (= 2 (simdref-test--count "uv tool install --force rassumfrassum"
                                        (simdref-test--log-contents)))))))

(ert-deftest simdref-test-daily-upgrade-rass ()
  "The daily check runs uv tool upgrade rassumfrassum after simdref."
  (simdref-test--with-sandbox
    (simdref-test--setup-daily)
    (simdref-maintain)
    (should (simdref-test--wait
             (lambda ()
               (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p (regexp-quote
                               "uv tool upgrade rassumfrassum>=0.3.5,<0.4")
                              log))
      (should (< (string-match "uv tool upgrade simdref" log)
                 (string-match "uv tool upgrade rassumfrassum" log)))
      (should (< (string-match "uv tool upgrade rassumfrassum" log)
                 (string-match "isa vaddps --short" log))))))

(provide 'simdref-test)
;;; simdref-test.el ends here

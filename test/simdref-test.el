;;; simdref-test.el --- ERT tests for simdref.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marco Barbone

;; Author: Marco Barbone <mbarbone@flatironinstitute.org>

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Each test drives `simdref-maintain', the real entry point, with fake
;; uv and isa scripts that log their argv.  Run with:
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

;; Loading simdref.el runs one maintenance pass.  Give it a managed
;; server and today's marker in the default install dir, so that pass
;; spawns nothing and every test stays offline.
(setq user-emacs-directory
      (file-name-as-directory (make-temp-file "simdref-test-home" t)))
(let* ((dir (locate-user-emacs-file "simdref/"))
       (server (expand-file-name "bin/simdref-lsp" dir)))
  (make-directory (file-name-directory server) t)
  (copy-file (simdref-test--fake "server.sh") server t)
  (set-file-modes server #o755)
  (write-region "" nil
                (expand-file-name (format "update-%d" (floor (float-time) 86400)) dir)))

(require 'simdref)

(defvar simdref-test--log nil
  "Path of the argv log that the fakes append to.")

(defvar simdref-test--events nil
  "Captured `message' and `display-warning' calls.")

(defun simdref-test--log-contents ()
  "Return the current argv log contents."
  (if (file-exists-p simdref-test--log)
      (with-temp-buffer
        (insert-file-contents simdref-test--log)
        (buffer-string))
    ""))

(defun simdref-test--wait (pred &optional seconds)
  "Run the event loop until PRED returns non-nil.  Wait at most SECONDS."
  (let ((deadline (+ (float-time) (or seconds 60))))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (funcall pred)))

(defun simdref-test--capture (fn)
  "Run FN with `message' and `display-warning' captured.  Return the events."
  (let ((simdref-test--events nil))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (_type msg &optional level &rest _)
                 (push (list :warn level msg) simdref-test--events)))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (list :message (apply #'format fmt args)) simdref-test--events))))
      (funcall fn))
    (nreverse simdref-test--events)))

(defun simdref-test--events-matching (events regexp)
  "Return the first of EVENTS whose text matches REGEXP."
  (cl-find-if (lambda (e) (string-match-p regexp (car (last e)))) events))

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
                         (format "SIMDREF_TEST_FAKE_LSP=%s" (simdref-test--fake "server.sh")))
                   process-environment))
          (simdref--installing nil))
     ,@body))

(defun simdref-test--put (src dst)
  "Copy the executable SRC to DST."
  (make-directory (file-name-directory dst) t)
  (copy-file src dst t)
  (set-file-modes dst #o755))

(defun simdref-test--setup-daily ()
  "Place the fake uv, isa and server where the daily check finds them."
  (simdref-test--put (simdref-test--fake "uv.sh")
                     (expand-file-name "uv/uv" simdref-test--tmp-root))
  (simdref-test--put (simdref-test--fake "isa.sh")
                     (expand-file-name "bin/isa" simdref-test--tmp-root))
  (simdref-test--put (simdref-test--fake "server.sh")
                     (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root)))

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
  (dolist (name '("uv.sh" "isa.sh" "server.sh"))
    (should (zerop (call-process "sh" nil nil nil "-n" (simdref-test--fake name)))))
  (simdref-test--with-sandbox
    (let ((process-environment process-environment))
      (setenv "SIMDREF_TEST_UV_EXIT" "0")
      (setenv "UV_TOOL_BIN_DIR" (expand-file-name "bin" simdref-test--tmp-root))
      (call-process (simdref-test--fake "uv.sh") nil nil nil "tool" "install" "simdref")
      (call-process (simdref-test--fake "isa.sh") nil nil nil "update")
      (call-process (simdref-test--fake "server.sh") nil nil nil))
    ;; Positive control: the fakes above really ran and logged argv.
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p "uv tool install simdref" log))
      (should (string-match-p "isa update" log))
      (should (string-match-p "lsp" log)))))

(ert-deftest simdref-test-first-install ()
  "No server: install downloads pinned uv, installs simdref, runs isa update."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root nil)))
      (simdref-maintain)
      (should (simdref-test--wait
               (lambda () (string-match-p "isa update" (simdref-test--log-contents))) 120)))
    (let ((log (simdref-test--log-contents)))
      (should (string-match-p "uv tool install simdref" log))
      (should (string-match-p "isa update" log))
      (should (< (string-match "uv tool install simdref" log)
                 (string-match "isa update" log))))
    (should (file-executable-p (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root)))))

(ert-deftest simdref-test-install-rejects-bad-sha ()
  "A wrong sha256 sidecar must stop the install before any uv run."
  (simdref-test--with-sandbox
    (let ((simdref-uv-base-url (simdref-test--stage-uv simdref-test--tmp-root t))
          (events nil))
      (setq events
            (simdref-test--capture
             (lambda ()
               (simdref-maintain)
               (should (simdref-test--wait
                        (lambda ()
                          (simdref-test--events-matching
                           simdref-test--events "checksum mismatch"))
                        120)))))
      ;; The download ran for real; the sha check rejected it.
      (should (file-exists-p (expand-file-name "uv.tar.gz" simdref-test--tmp-root)))
      (should (not (string-match-p "tool install" (simdref-test--log-contents))))
      (let ((notice (simdref-test--events-matching events "simdref-lsp not found")))
        (should notice)
        (should (eq (nth 1 notice) :warning))))))

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
  "A missing executable logs quietly: no spawn error and no popup."
  (simdref-test--with-sandbox
    (simdref-test--put (simdref-test--fake "server.sh")
                       (expand-file-name "bin/simdref-lsp" simdref-test--tmp-root))
    (let ((events (simdref-test--capture #'simdref-maintain)))
      (should (cl-find-if (lambda (e) (string-match-p "spawn skipped" (car (last e)))) events))
      ;; No popup: nothing at :warning or above.
      (should (cl-every (lambda (e)
                          (or (eq (car e) :message)
                              (not (memq (nth 1 e) '(:warning :error :emergency)))))
                        events)))))

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
  "A nonzero exit is logged at the warning channel; success is a plain line."
  (let (ok-events bad-events)
    (simdref-test--with-sandbox
      (simdref-test--setup-daily)
      (setq ok-events
            (simdref-test--capture
             (lambda ()
               (simdref-maintain)
               (should (simdref-test--wait
                        (lambda ()
                          (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))))))
    (simdref-test--with-sandbox
      (simdref-test--setup-daily)
      (setenv "SIMDREF_TEST_UV_EXIT" "1")
      (setq bad-events
            (simdref-test--capture
             (lambda ()
               (simdref-maintain)
               (should (simdref-test--wait
                        (lambda ()
                          (string-match-p "isa vaddps --short" (simdref-test--log-contents)))))))))
    ;; Success is a plain message line only.
    (should (cl-every (lambda (e) (eq (car e) :message)) ok-events))
    ;; The nonzero exit is louder: it goes to `display-warning'.
    (let ((warn (cl-find-if (lambda (e) (eq (car e) :warn)) bad-events)))
      (should warn)
      ;; Maintenance failures stay at :debug and never pop up a window.
      (should (eq (nth 1 warn) :debug)))))

(ert-deftest simdref-test-eglot-registration ()
  "eglot-server-programs maps every listed mode to the simdref contact."
  (require 'eglot)
  (dolist (mode simdref--modes)
    (should (memq mode '(asm-mode c-mode c++-mode c-ts-mode c++-ts-mode)))
    (should (cl-find-if
             (lambda (entry)
               (let ((modes (car entry)))
                 (and (memq mode (if (listp modes) modes (list modes)))
                      (eq (cdr entry) #'simdref--eglot-contact))))
             eglot-server-programs))))

(provide 'simdref-test)
;;; simdref-test.el ends here

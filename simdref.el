;;; simdref.el --- simdref LSP setup and self-install  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Marco Barbone

;; Author: Marco Barbone <mbarbone@flatironinstitute.org>
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages, tools, hardware
;; URL: https://github.com/simd-labs/emacs-simdref

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package registers `simdref-lsp' with eglot, and with lsp-mode when
;; lsp-mode is loaded.  With no server on `PATH', it installs one private
;; copy under `simdref-install-dir' in the background.  Once a day the
;; package upgrades that copy and refreshes the catalog.  A server on
;; `PATH' belongs to the user; the package never touches it.  A new
;; simdref version takes effect at the next server start.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defvar eglot-server-programs)
(defvar lsp-language-id-configuration)
(declare-function lsp-register-client "lsp-mode" (client))
(declare-function make-lsp-client "lsp-mode" (&rest args))
(declare-function lsp-stdio-connection "lsp-mode" (command &optional test-command))

(defgroup simdref nil
  "LSP support for simdref."
  :group 'tools
  :prefix "simdref-")

(defcustom simdref-install-dir (locate-user-emacs-file "simdref/")
  "Directory that holds the private simdref install."
  :type 'directory
  :group 'simdref)

(defconst simdref--uv-version "0.12.23"
  "Pinned uv release.  Same pin as the other simdref extensions.")

(defconst simdref--uv-targets
  '(("gnu/linux" . (("x86_64" . "x86_64-unknown-linux-gnu")
                    ("aarch64" . "aarch64-unknown-linux-gnu")))
    ("darwin" . (("x86_64" . "x86_64-apple-darwin")
                 ("aarch64" . "aarch64-apple-darwin")))
    ("windows-nt" . (("x86_64" . "x86_64-pc-windows-msvc")
                     ("aarch64" . "aarch64-pc-windows-msvc"))))
  "Release triples keyed by OS and CPU.  Same map as the vscode extension.")

(defconst simdref--timeout 600
  "Timeout in seconds for each subprocess.
A stuck step must not hang forever.")

(defcustom simdref-uv-base-url
  (concat "https://github.com/astral-sh/uv/releases/download/" simdref--uv-version "/")
  "Base URL of the pinned uv release.  Tests point this at a file URL."
  :type 'string
  :group 'simdref)

(defconst simdref--modes '(asm-mode c-mode c++-mode c-ts-mode c++-ts-mode)
  "Major modes that get the simdref server.")

(defvar simdref--installing nil
  "Non-nil while a private install runs.  Stops a second install.")

(defun simdref--log (fmt &rest args)
  "Log a plain success line with a `simdref' prefix.
FMT and ARGS follow `message'."
  (message "simdref: %s" (apply #'format fmt args)))

(defun simdref--warn (level fmt &rest args)
  "Show a `simdref' warning at LEVEL.  FMT and ARGS follow `format'.
LEVEL :debug never pops up a window.  See `display-warning'."
  (display-warning 'simdref (apply #'format fmt args) level))

(defun simdref--exe (name)
  "Return NAME with an exe suffix on Windows."
  (if (eq system-type 'windows-nt) (concat name ".exe") name))

(defun simdref--uv-target ()
  "Return the uv release triple for this machine, or nil."
  (let* ((arch (car (split-string system-configuration "-")))
         (os (pcase system-type
               ((or 'gnu 'gnu/linux 'gnu/kfreebsd) "gnu/linux")
               ('darwin "darwin")
               ('windows-nt "windows-nt"))))
    (cdr (assoc arch (cdr (assoc os simdref--uv-targets))))))

(defun simdref--uv-env (dir)
  "Return the environment DIR needs.  Keep every uv write inside DIR."
  (list (format "UV_TOOL_DIR=%s" (expand-file-name "tools" dir))
        (format "UV_TOOL_BIN_DIR=%s" (expand-file-name "bin" dir))
        (format "UV_PYTHON_INSTALL_DIR=%s" (expand-file-name "python" dir))
        (format "UV_CACHE_DIR=%s" (expand-file-name "cache" dir))))

(defun simdref--server-cmd (&optional dir)
  "Return the absolute path of the simdref server, or nil.
A server on `PATH' wins over the private copy in DIR."
  (or (executable-find "simdref-lsp")
      (let ((bin (expand-file-name (simdref--exe "simdref-lsp")
                                   (expand-file-name "bin" (or dir simdref-install-dir)))))
        (and (file-executable-p bin) bin))))

(defun simdref--managed-p (server dir)
  "Return non-nil when SERVER is the private copy inside DIR."
  (equal (file-name-directory server)
         (file-name-as-directory (expand-file-name "bin" dir))))

(defun simdref--exit-log (level program args code out)
  "Log the exit of PROGRAM with ARGS at LEVEL.
CODE is nonzero on failure.  OUT holds the program output."
  (if (zerop code)
      (simdref--log "%s %s: ok" (file-name-nondirectory program) (string-join args " "))
    (simdref--warn level "%s %s: exit %d: %s" (file-name-nondirectory program)
                   (string-join args " ") code (string-trim out))))

(defun simdref--run (program args env level on-exit)
  "Run PROGRAM with ARGS in the background.
ENV is a list of NAME=VALUE strings.  Log the exit at LEVEL.  Call
ON-EXIT with the exit code and the output.  Return the process, or
nil when PROGRAM is missing."
  ;; Look up a bare name on PATH.  Use an absolute path as is.
  (setq program (if (file-name-absolute-p program)
                    program
                  (or (executable-find program) program)))
  (if (not (file-executable-p program))
      (progn (simdref--warn :debug "spawn skipped, %s is missing" program) nil)
    (let ((buf (generate-new-buffer " *simdref*"))
          proc timer)
      (setq proc
            (condition-case err
                (let ((process-environment (append env process-environment)))
                  (make-process
                   :name "simdref" :buffer buf :noquery t
                   :command (cons program args)
                   :sentinel
                   (lambda (p _ev)
                     (when (memq (process-status p) '(exit signal))
                       (when (timerp timer) (cancel-timer timer))
                       (let ((code (process-exit-status p))
                             (out (with-current-buffer buf (buffer-string))))
                         (kill-buffer buf)
                         (simdref--exit-log level program args code out)
                         (when on-exit (funcall on-exit code out)))))))
              (error (simdref--warn :debug "spawn failed: %s" (error-message-string err))
                     nil)))
      (when proc
        (setq timer
              (run-at-time simdref--timeout nil
                           (lambda ()
                             (simdref--warn level "timeout, killing %s" program)
                             (ignore-errors (delete-process proc))))))
      proc)))

(defun simdref--sha256-match-p (file checksum-file)
  "Return non-nil when the sha256 of FILE matches CHECKSUM-FILE.
The checksum is the first token in CHECKSUM-FILE."
  (when (and (file-readable-p file) (file-readable-p checksum-file))
    (let ((want (with-temp-buffer
                  (insert-file-contents checksum-file)
                  (car (split-string (buffer-string)))))
          (got (with-temp-buffer
                 (insert-file-contents-literally file)
                 (secure-hash 'sha256 (current-buffer)))))
      (and want (string-equal (downcase want) got)))))

(defun simdref--claim-marker (marker)
  "Create MARKER with an exclusive create.  Return non-nil on success.
An existing marker means another process did today's check already."
  (condition-case nil
      (progn (write-region "" nil marker nil 'silent nil 'excl) t)
    (file-already-exists nil)
    (error (simdref--warn :debug "marker %s failed" marker) nil)))

(defun simdref--missing-notice (cause)
  "Warn that the server is missing.  CAUSE names the failed step."
  (simdref--warn :warning
                 "simdref-lsp not found. Run: uv tool install simdref && isa update\n%s\n%s"
                 "https://github.com/simd-labs/simdref" cause))

(defun simdref--maybe-upgrade (dir)
  "Upgrade the private simdref copy in DIR once a day.
Then refresh the catalog."
  (let* ((day (floor (float-time) 86400))
         (marker (expand-file-name (format "update-%d" day) dir)))
    ;; Known race: a check that runs at midnight UTC can overlap the next
    ;; day's check, and cleanup can delete the new marker of another
    ;; process.  The overlap is accepted.  A lock was tried and it
    ;; reintroduced the race.
    (when (simdref--claim-marker marker)
      (dolist (f (directory-files dir t "\\`update-"))
        (unless (equal f marker)
          (ignore-errors (delete-file f))))
      (let ((env (simdref--uv-env dir)))
        ;; The refresh runs also when the upgrade failed: an offline
        ;; upgrade must not block a catalog repair.
        (simdref--run (expand-file-name (simdref--exe "uv") (expand-file-name "uv" dir))
                      '("tool" "upgrade" "simdref") env :debug
                      (lambda (_code _out)
                        (simdref--run (expand-file-name (simdref--exe "isa")
                                                       (expand-file-name "bin" dir))
                                      '("vaddps" "--short") env :debug nil)))))))

(defun simdref--install (dir)
  "Install a private simdref under DIR: pinned uv, simdref, then the catalog."
  (unless simdref--installing
    (setq simdref--installing t)
    (make-directory dir t)
    (let* ((target (simdref--uv-target))
           (zip (eq system-type 'windows-nt))
           (base (and target
                      (concat simdref-uv-base-url
                              (format "uv-%s.%s" target (if zip "zip" "tar.gz")))))
           (uvdir (expand-file-name "uv" dir))
           (uv (expand-file-name (simdref--exe "uv") uvdir))
           (bin (expand-file-name "bin" dir))
           (isa (expand-file-name (simdref--exe "isa") bin))
           (env (simdref--uv-env dir))
           (archive (expand-file-name (if zip "uv.zip" "uv.tar.gz") dir))
           (checksum (concat archive ".sha256")))
      (cl-labels
          ((fail (cause)
             (setq simdref--installing nil)
             (simdref--missing-notice cause))
           (step (program args on-done)
             (unless (simdref--run program args env :debug
                                   (lambda (code out)
                                     (if (zerop code)
                                         (funcall on-done)
                                       (fail (format "%s %s failed: %s" program
                                                     (string-join args " ")
                                                     (string-trim out))))))
               (fail (format "%s is missing" program))))
           (download (url dest on-done)
             (step "curl" (list "-fsSL" "-o" dest url) on-done))
           (check-sha ()
             (if (simdref--sha256-match-p archive checksum)
                 (extract)
               (fail "uv checksum mismatch")))
           (extract ()
             (make-directory uvdir t)
             (step "tar" (append (list "-xf" archive "-C" uvdir)
                                 (unless zip '("--strip-components=1")))
                   #'install-tool))
           (install-tool ()
             (step uv '("tool" "install" "simdref") #'refresh))
           (refresh ()
             (step isa '("update") #'done))
           (done ()
             (setq simdref--installing nil)
             (simdref--log "installed %s" (expand-file-name (simdref--exe "simdref-lsp") bin))))
        (if (not base)
            (fail (format "no uv build for %s" system-configuration))
          (download base archive
                    (lambda ()
                      (download (concat base ".sha256") checksum #'check-sha))))))))

(defun simdref-maintain ()
  "Install simdref when it is missing, else run the daily upgrade check."
  (interactive)
  (let* ((dir (directory-file-name (expand-file-name simdref-install-dir)))
         (server (simdref--server-cmd dir)))
    (if server
        (when (simdref--managed-p server dir)
          (simdref--maybe-upgrade dir))
      (simdref--install dir))))

(defun simdref--eglot-contact (&rest _args)
  "Return the eglot contact for simdref, or nil when the server is missing.
A first install finishes before this returns, so eglot can start."
  (simdref-maintain)
  (let ((deadline (+ (float-time) 7200)))
    (while (and simdref--installing (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (let ((cmd (simdref--server-cmd)))
    (and cmd (list cmd))))

;;;###autoload
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               (cons simdref--modes #'simdref--eglot-contact)))

;;;###autoload
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(asm-mode . "asm"))
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection
                                     (lambda ()
                                       (let ((cmd (simdref--server-cmd)))
                                         (and cmd (list cmd)))))
                    :major-modes simdref--modes
                    :server-id 'simdref)))

;; Install now when the server is missing, like the other extensions.
(simdref-maintain)

(provide 'simdref)
;;; simdref.el ends here

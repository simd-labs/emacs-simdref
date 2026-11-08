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
;; lsp-mode is loaded.  In C, C++ and CUDA buffers it runs the companion
;; server of `simdref-companion-server' (clangd by default) together with
;; simdref through the rassumfrassum multiplexer, so both answer in one
;; buffer.  With no server on `PATH', it installs one private
;; copy under `simdref-install-dir' in the background.  Once a day the
;; package upgrades that copy and refreshes the catalog.  A server on
;; `PATH' belongs to the user; the package never touches it.  A new
;; simdref version takes effect at the next server start.
;;
;; Maintenance never opens a window and never blocks.  Success lines go
;; to the `*simdref-log*' buffer only.  A failure logs there and shows
;; one echo-area line that starts with "simdref:" and names the step.

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

(defconst simdref--uv-sha256
  '(("x86_64-unknown-linux-gnu" . "9167d72b3319674b6303c4cbe071854bba13ebdf3d76b1a7cbdc175471fb66d6")
    ("aarch64-unknown-linux-gnu" . "6524bd338177ed50d035d39354e12545e993bbeba2ecbddf0480c5b3a81d313f")
    ("x86_64-apple-darwin" . "960da44cb4b73685206ddd250b19e0a117fa41095710c1038f081f5cb613efb4")
    ("aarch64-apple-darwin" . "50487ae565ccd96e499056b4674d438f4c53170202617b4c759defe0c6a1b544")
    ("x86_64-pc-windows-msvc" . "75d05de6762778c31ee183398de7dd15093fad0ed90b1f236d8205ea5ec00c90")
    ("aarch64-pc-windows-msvc" . "13294e232ececbe709c06b74e6ced06f2a225ea5591476685362f22be56a50d5"))
  "Pinned sha256 of the uv 0.12.23 archive of each release triple.
The install checks the downloaded archive against this value.  Bump
the version and these values together in one edit.")

(defconst simdref--timeout 600
  "Timeout in seconds for each subprocess.
A stuck step must not hang forever.")

(defcustom simdref-uv-base-url
  (concat "https://github.com/astral-sh/uv/releases/download/" simdref--uv-version "/")
  "Base URL of the pinned uv release.  Tests point this at a file URL."
  :type 'string
  :group 'simdref)

(defconst simdref--modes
  '(asm-mode nasm-mode cuda-mode c-mode c++-mode c-ts-mode c++-ts-mode)
  "Major modes that get the simdref server.")

(defconst simdref--c-modes
  '(cuda-mode c-mode c++-mode c-ts-mode c++-ts-mode)
  "Major modes that share the buffer with `simdref-companion-server'.")

(defconst simdref--asm-modes
  '(asm-mode nasm-mode)
  "Major modes that run the simdref server alone.")

(defcustom simdref-companion-server '("clangd")
  "Command list of the companion LSP server for C, C++ and CUDA buffers.
The package multiplexes this server with simdref through
rassumfrassum, so both answer in one buffer.  The first element must
be on the variable `exec-path'.  Nil runs simdref alone."
  :type '(repeat string)
  :group 'simdref)

(defvar simdref--installing nil
  "Non-nil while a private install runs.  Stops a second install.")

(defvar simdref--notice-shown nil
  "Non-nil once this session echoed the missing-server notice.
The notice prints at most once per Emacs session.")

(defun simdref--log (fmt &rest args)
  "Append one line to the `*simdref-log*' buffer.
FMT and ARGS follow `format'.  Success lines log here only."
  (with-current-buffer (get-buffer-create "*simdref-log*")
    (goto-char (point-max))
    (insert (format "simdref: %s\n" (apply #'format fmt args)))))

(defun simdref--echo (fmt &rest args)
  "Log like `simdref--log' and show one \"simdref:\" echo-area line.
FMT and ARGS follow `format'.  Failure lines use this.  It is louder
than success and it opens no window."
  (let ((line (apply #'format fmt args)))
    (simdref--log "%s" line)
    (message "simdref: %s" line)))

(defun simdref--report (loud fmt &rest args)
  "Log the line from FMT and ARGS, and echo it when LOUD is non-nil."
  (if loud
      (apply #'simdref--echo fmt args)
    (apply #'simdref--log fmt args)))

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

(defun simdref--rass-cmd (&optional dir)
  "Return the absolute path of the rassumfrassum multiplexer, or nil.
The private copy in DIR wins over a rass on `PATH'.  A rass on `PATH'
is never upgraded."
  (or (let ((bin (expand-file-name (simdref--exe "rass")
                                   (expand-file-name "bin"
                                                     (or dir simdref-install-dir)))))
        (and (file-executable-p bin) bin))
      (executable-find "rass")))

(defun simdref--stamp (dir)
  "Write the install stamp in DIR.
Call this only after every install step exits 0."
  (write-region "" nil (expand-file-name "installed" dir) nil 'silent))

(defun simdref--installed-p (dir)
  "Return non-nil when the install in DIR is complete.
A complete install is the server executable and the stamp file.  The
package writes the stamp only after every install step exits 0, so a
half install never counts as installed."
  (and (file-executable-p (expand-file-name (simdref--exe "simdref-lsp")
                                            (expand-file-name "bin" dir)))
       (file-exists-p (expand-file-name "installed" dir))))

(defun simdref--exit-log (loud program args code out)
  "Log the exit of PROGRAM with ARGS to the log buffer.
CODE is nonzero on failure.  OUT holds the program output.  Echo the
failure when LOUD is non-nil."
  (let* ((step (format "%s %s" (file-name-nondirectory program)
                       (string-join args " ")))
         (detail (string-trim out)))
    (if (zerop code)
        (simdref--log "%s: ok" step)
      (let ((line (if (string-empty-p detail)
                      (format "%s: exit %d" step code)
                    (format "%s: exit %d: %s" step code detail))))
        (if loud (simdref--echo "%s" line) (simdref--log "%s" line))))))

(defun simdref--run (program args env loud on-exit)
  "Run PROGRAM with ARGS in the background.
ENV is a list of NAME=VALUE strings.  Log every exit to the log
buffer, and echo failures when LOUD is non-nil.  Call ON-EXIT with
the exit code and the output.  Return the process, or nil when
PROGRAM is missing."
  ;; Look up a bare name on PATH.  Use an absolute path as is.
  (setq program (if (file-name-absolute-p program)
                    program
                  (or (executable-find program) program)))
  (if (not (file-executable-p program))
      (progn (simdref--report loud "%s %s: spawn skipped, %s is missing"
                              (file-name-nondirectory program)
                              (string-join args " ") program)
             nil)
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
                         (simdref--exit-log loud program args code out)
                         (when on-exit (funcall on-exit code out)))))))
              (error (simdref--report loud "%s %s: spawn failed: %s"
                                      (file-name-nondirectory program)
                                      (string-join args " ")
                                      (error-message-string err))
                     nil)))
      (when proc
        (setq timer
              (run-at-time simdref--timeout nil
                           (lambda ()
                             (simdref--log "timeout, killing %s" program)
                             (ignore-errors (delete-process proc))))))
      proc)))

(defun simdref--sha256-match-p (file expected)
  "Return non-nil when the sha256 of FILE is the hex digest EXPECTED.
EXPECTED is the pinned value in `simdref--uv-sha256'.  A nil EXPECTED
never matches."
  (when (and expected (file-readable-p file))
    (let ((got (with-temp-buffer
                 (insert-file-contents-literally file)
                 (secure-hash 'sha256 (current-buffer)))))
      (string-equal (downcase expected) got))))

(defun simdref--claim-marker (marker)
  "Create MARKER with an exclusive create.  Return non-nil on success.
An existing marker means another process did today's check already."
  (condition-case nil
      (progn (write-region "" nil marker nil 'silent nil 'excl) t)
    (file-already-exists nil)
    (error (simdref--log "marker %s failed" marker) nil)))

(defconst simdref--not-found-text
  "simdref not found. Install it: uv tool install simdref (or pip install simdref), then run isa update. Instructions: https://github.com/simd-labs/simdref"
  "Missing-server text.  Same string as the other simdref extensions.")

(defun simdref--missing-notice (cause)
  "Report the missing server and name CAUSE as the failed step.
The text is the shared not-found sentence.  The echo-area notice
prints once per Emacs session."
  (simdref--log "%s Failed step: %s" simdref--not-found-text cause)
  (unless simdref--notice-shown
    (setq simdref--notice-shown t)
    (message "simdref: %s Failed step: %s" simdref--not-found-text cause)))

(defun simdref--maybe-upgrade (dir)
  "Upgrade the private simdref copy in DIR once a day.
Then upgrade the private rass copy, or install it when it is missing,
and refresh the catalog."
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
      (let* ((env (simdref--uv-env dir))
             (uv (expand-file-name (simdref--exe "uv")
                                   (expand-file-name "uv" dir)))
             (isa (expand-file-name (simdref--exe "isa")
                                    (expand-file-name "bin" dir)))
             (rass (expand-file-name (simdref--exe "rass")
                                     (expand-file-name "bin" dir)))
             (refresh (lambda (_code _out)
                        (simdref--run isa '("vaddps" "--short") env t nil))))
        ;; The refresh runs also when an upgrade failed: an offline
        ;; upgrade must not block a catalog repair.
        (simdref--run uv '("tool" "upgrade" "simdref") env t
                      (lambda (_code _out)
                        ;; The check reads the private copy only; a rass on
                        ;; `PATH' belongs to the user and never changes here.
                        ;; The spec keeps the upgrade inside the pinned range.
                        (if (file-executable-p rass)
                            (simdref--run uv '("tool" "upgrade" "rassumfrassum>=0.3.5,<0.4")
                                          env t refresh)
                          ;; An install from before rass support holds no
                          ;; private copy.  The install step adds it, with
                          ;; the same pin the fresh install uses.
                          (simdref--run uv '("tool" "install" "--force" "rassumfrassum>=0.3.5,<0.4")
                                        env t refresh))))))))

(defun simdref--install (dir)
  "Install a private simdref under DIR.
The steps are pinned uv, simdref, rass and the catalog."
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
           (archive (expand-file-name (if zip "uv.zip" "uv.tar.gz") dir)))
      (cl-labels
          ((fail (cause)
             (setq simdref--installing nil)
             (simdref--missing-notice cause))
           (step (program args on-done)
             (unless (simdref--run program args env nil
                                   (lambda (code out)
                                     (if (zerop code)
                                         (funcall on-done)
                                       (fail (format "%s %s failed%s" program
                                                     (string-join args " ")
                                                     (let ((detail (string-trim out)))
                                                       (if (string-empty-p detail)
                                                           ""
                                                         (format ": %s" detail))))))))
               (fail (format "%s is missing" program))))
           (download (url dest on-done)
             (step "curl" (list "-fsSL" "-o" dest url) on-done))
           (check-sha ()
             ;; The check reads the pinned digest, never a fetched sidecar.
             (if (simdref--sha256-match-p
                  archive (cdr (assoc target simdref--uv-sha256)))
                 (extract)
               (fail "uv checksum mismatch")))
           (extract ()
             (make-directory uvdir t)
             (step "tar" (append (list "-xf" archive "-C" uvdir)
                                 (unless zip '("--strip-components=1")))
                   #'install-tool))
           (install-tool ()
             (step uv '("tool" "install" "--force" "simdref") #'install-rass))
           (install-rass ()
             ;; The pin keeps rass on the class API the preset uses.
             (step uv '("tool" "install" "--force" "rassumfrassum>=0.3.5,<0.4")
                   #'refresh))
           (refresh ()
             (step isa '("update") #'done))
           (done ()
             (setq simdref--installing nil)
             (simdref--stamp dir)
             (simdref--echo "install done, run M-x eglot")))
        (if (not base)
            (fail (format "no uv build for %s" system-configuration))
          (download base archive #'check-sha))))))

(defun simdref-maintain ()
  "Install simdref when it is missing, else run the daily upgrade check."
  (interactive)
  (let* ((dir (directory-file-name (expand-file-name simdref-install-dir)))
         (server (simdref--server-cmd dir)))
    (if server
        (when (simdref--managed-p server dir)
          (if (simdref--installed-p dir)
              (simdref--maybe-upgrade dir)
            (simdref--install dir)))
      (simdref--install dir))))

(defvar simdref--rass-log-shown nil
  "Non-nil once this session logged the missing-multiplexer fallback.")

(defvar simdref--preset-log-shown nil
  "Non-nil once this session logged the missing-preset fallback.")

(defconst simdref--preset-file
  (expand-file-name "simdref-rass.py"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Absolute path of the rass preset that ships beside simdref.el.
The contact passes it to rass, so hover reaches simdref and the
companion.  Captured at load time.")

(defun simdref--eglot-contact (&rest _args)
  "Return the eglot contact for simdref, or signal `user-error'.
A C, C++ or CUDA buffer with `simdref-companion-server' runs both
servers through the rassumfrassum multiplexer, when the companion and
rass are present.  The preset makes hover reach both servers.  With no
preset file the companion runs first, so every clangd feature works
and simdref hover is lost.  Else the contact is the simdref command
alone.  A server on `PATH' or in `simdref-install-dir' returns its
command.  With no server, start the asynchronous install and signal
`user-error'.  This function never waits for the install."
  (simdref-maintain)
  (let* ((cmd (simdref--server-cmd))
         (want (and cmd simdref-companion-server
                    (memq major-mode simdref--c-modes)))
         (rass (and want (simdref--rass-cmd))))
    (when (and want (not rass) (not simdref--rass-log-shown))
      (setq simdref--rass-log-shown t)
      (simdref--log "rass not found, running simdref alone"))
    (or (and cmd
             (if (and rass (executable-find (car simdref-companion-server)))
                 (if (file-readable-p simdref--preset-file)
                     ;; The preset sends hover to both servers, simdref and
                     ;; the companion.  rass takes the preset path as its
                     ;; first positional argument.
                     (append (list rass simdref--preset-file)
                             (list "--" cmd "--")
                             simdref-companion-server)
                   ;; rass with no preset routes hover to its first server.
                   ;; The companion runs first: every clangd feature keeps
                   ;; working and simdref hover is lost.
                   (unless simdref--preset-log-shown
                     (setq simdref--preset-log-shown t)
                     (simdref--log "preset %s missing, companion first, simdref hover off"
                                   simdref--preset-file))
                   (append (list rass "--")
                           simdref-companion-server
                           (list "--" cmd)))
               (list cmd)))
        (user-error "%s Installing simdref in the background.  Run M-x eglot again when the log says the install is done"
                    simdref--not-found-text))))

;;;###autoload
(with-eval-after-load 'eglot
  ;; Two keys, not one shared key: eglot lets a running server manage
  ;; every mode its starting key lists (eglot--languageId), so one key
  ;; let an asm-started bare simdref server claim later C buffers and
  ;; skip the rass plus clangd contact.
  (add-to-list 'eglot-server-programs
               (cons simdref--c-modes #'simdref--eglot-contact))
  (add-to-list 'eglot-server-programs
               (cons simdref--asm-modes #'simdref--eglot-contact)))

;;;###autoload
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(asm-mode . "asm"))
  (add-to-list 'lsp-language-id-configuration '(nasm-mode . "nasm"))
  (add-to-list 'lsp-language-id-configuration '(cuda-mode . "cuda"))
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection
                                     (lambda ()
                                       (let ((cmd (simdref--server-cmd)))
                                         (and cmd (list cmd)))))
                    :add-on? t
                    :major-modes simdref--modes
                    :server-id 'simdref)))

;; Install now when the server is missing, like the other extensions.
(simdref-maintain)

(provide 'simdref)
;;; simdref.el ends here

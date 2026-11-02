#!/usr/bin/env bash
# Runs the emacs-simdref checks inside the container.  Mounted at /src.
set -u
cd "$(dirname "$0")/../.." || exit 1

echo "emacs: $(emacs --version | head -1)"
echo "curl: $(curl --version | head -1)"
echo "tar: $(tar --version | head -1)"

fail=0

echo "--- ERT suite ---"
emacs -Q --batch -L . -l test/simdref-test.el -f ert-run-tests-batch-and-exit
rc=$?; echo "exit=$rc"; [ $rc -ne 0 ] && fail=1

echo "--- byte-compile (no warnings allowed) ---"
cp simdref.el /tmp/simdref.el
emacs -Q --batch --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile /tmp/simdref.el
rc=$?; echo "exit=$rc"; [ $rc -ne 0 ] && fail=1

echo "--- checkdoc ---"
emacs -Q --batch --eval '(progn (require (quote checkdoc))
  (let ((checkdoc-autofix-flag (quote never)))
    (checkdoc-file "simdref.el")))' > /tmp/checkdoc.log 2>&1
rc=$?
echo "checkdoc output lines: $(grep -c . /tmp/checkdoc.log)"
cat /tmp/checkdoc.log
echo "exit=$rc"

echo "=== container tests done, fail=$fail ==="
exit $fail

#!/bin/sh
# Fake simdref-lsp for the tests: log that it exists, then exit.
set -u
printf 'lsp %s\n' "$*" >> "$SIMDREF_TEST_LOG"
exit 0

#!/bin/sh
# Fake clangd for the tests: log that it exists, then exit.
set -u
printf 'clangd %s\n' "$*" >> "$SIMDREF_TEST_LOG"
exit 0

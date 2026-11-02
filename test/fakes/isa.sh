#!/bin/sh
# Fake isa for the tests: log argv, then exit with the test's code.
set -u
printf 'isa %s\n' "$*" >> "$SIMDREF_TEST_LOG"
exit "${SIMDREF_TEST_ISA_EXIT:-0}"

#!/bin/sh
# Fake rass for the tests: log that it exists, then exit.
set -u
printf 'rass %s\n' "$*" >> "$SIMDREF_TEST_LOG"
exit 0

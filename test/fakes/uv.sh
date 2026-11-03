#!/bin/sh
# Fake uv for the tests: log argv, then place the fake tools into
# $UV_TOOL_BIN_DIR on `tool install [--force] PACKAGE'.  The simdref
# step places isa and simdref-lsp, the rassumfrassum step places rass.
# SIMDREF_TEST_UV_SLEEP delays the exit, so a test can kill the run.
# SIMDREF_TEST_UV_RASS_* apply to the rassumfrassum step only.
set -u
printf 'uv %s\n' "$*" >> "$SIMDREF_TEST_LOG"
case "$*" in
  "tool install simdref"|"tool install --force simdref")
    mkdir -p "$UV_TOOL_BIN_DIR"
    cp "$SIMDREF_TEST_FAKE_ISA" "$UV_TOOL_BIN_DIR/isa"
    cp "$SIMDREF_TEST_FAKE_LSP" "$UV_TOOL_BIN_DIR/simdref-lsp"
    chmod +x "$UV_TOOL_BIN_DIR/isa" "$UV_TOOL_BIN_DIR/simdref-lsp"
    ;;
  "tool install rassumfrassum"*|"tool install --force rassumfrassum"*)
    mkdir -p "$UV_TOOL_BIN_DIR"
    cp "$SIMDREF_TEST_FAKE_RASS" "$UV_TOOL_BIN_DIR/rass"
    chmod +x "$UV_TOOL_BIN_DIR/rass"
    sleep "${SIMDREF_TEST_UV_RASS_SLEEP:-0}"
    sleep "${SIMDREF_TEST_UV_SLEEP:-0}"
    exit "${SIMDREF_TEST_UV_RASS_EXIT:-0}"
    ;;
esac
sleep "${SIMDREF_TEST_UV_SLEEP:-0}"
exit "${SIMDREF_TEST_UV_EXIT:-0}"

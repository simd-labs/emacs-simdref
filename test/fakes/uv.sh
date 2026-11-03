#!/bin/sh
# Fake uv for the tests: log argv, then place the fake isa and
# simdref-lsp into $UV_TOOL_BIN_DIR on `tool install [--force] simdref`.
# SIMDREF_TEST_UV_SLEEP delays the exit, so a test can kill the run.
set -u
printf 'uv %s\n' "$*" >> "$SIMDREF_TEST_LOG"
if [ "$*" = "tool install simdref" ] || [ "$*" = "tool install --force simdref" ]; then
  mkdir -p "$UV_TOOL_BIN_DIR"
  cp "$SIMDREF_TEST_FAKE_ISA" "$UV_TOOL_BIN_DIR/isa"
  cp "$SIMDREF_TEST_FAKE_LSP" "$UV_TOOL_BIN_DIR/simdref-lsp"
  chmod +x "$UV_TOOL_BIN_DIR/isa" "$UV_TOOL_BIN_DIR/simdref-lsp"
fi
sleep "${SIMDREF_TEST_UV_SLEEP:-0}"
exit "${SIMDREF_TEST_UV_EXIT:-0}"

#!/bin/sh
# Fake uv for the tests: log argv, then place the fake isa and
# simdref-lsp into $UV_TOOL_BIN_DIR on `tool install simdref`.
set -u
printf 'uv %s\n' "$*" >> "$SIMDREF_TEST_LOG"
if [ "$*" = "tool install simdref" ]; then
  mkdir -p "$UV_TOOL_BIN_DIR"
  cp "$SIMDREF_TEST_FAKE_ISA" "$UV_TOOL_BIN_DIR/isa"
  cp "$SIMDREF_TEST_FAKE_LSP" "$UV_TOOL_BIN_DIR/simdref-lsp"
  chmod +x "$UV_TOOL_BIN_DIR/isa" "$UV_TOOL_BIN_DIR/simdref-lsp"
fi
exit "${SIMDREF_TEST_UV_EXIT:-0}"

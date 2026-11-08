# emacs-simdref

Show the brief of an assembly instruction from the local simdref catalog.

`M-x eglot` on a buffer shows hover docs and inlay hints for instructions.
The catalog is local, so the server answers without network. An inlay
hint label is at most 60 characters: the server cuts a longer brief and
ends it with `...`.

![Emacs showing simdref inlay hints in an asm buffer](https://raw.githubusercontent.com/simd-labs/emacs-simdref/81f8e260e2c98b509a5be81653f872049129d0b6/emacs-asm.png)
![Emacs showing a simdref inlay hint in a C++ buffer](https://raw.githubusercontent.com/simd-labs/emacs-simdref/81f8e260e2c98b509a5be81653f872049129d0b6/emacs-cpp.png)

## Requirements

- Emacs 29.1 or newer
- `curl` and `tar` for the first install
- Install the `markdown-mode` package so eglot shows the hover text as formatted markdown. Without the package the hover shows raw markdown.

## Setup

```elisp
(add-to-list 'load-path "/path/to/emacs-simdref")
(require 'simdref)
```

The package registers `simdref-lsp` with eglot for `asm-mode`, `nasm-mode`,
`cuda-mode`, `c-mode`, `c++-mode`, `c-ts-mode` and `c++-ts-mode`. When
lsp-mode is loaded, it registers the server there too.

## Settings

- `simdref-install-dir`: directory of the private install. Default `(locate-user-emacs-file "simdref/")`.
- `simdref-uv-base-url`: base URL of the pinned `uv` release. Default the GitHub release of `uv` 0.12.23.
- `simdref-companion-server`: command list of the companion LSP server for C, C++ and CUDA buffers. Default `("clangd")`. Nil runs simdref alone. The first element must be on `exec-path`.

## First start

Without a server on `PATH`, the package installs one in the background to
`(locate-user-emacs-file "simdref/")`. It downloads a pinned `uv`, installs
`simdref`, `rass` and the catalog. This takes minutes and never blocks Emacs.
`M-x eglot` during the install starts nothing and shows this error:

```
simdref not found. Install it: uv tool install simdref (or pip install simdref), then run isa update. Instructions: https://github.com/simd-labs/simdref Installing simdref in the background.  Run M-x eglot again when the log says the install is done
```

When the echo area shows `simdref: install done, run M-x eglot`, run
`M-x eglot` again.

Once a day the package upgrades that copy, `rass` and the catalog.
A new simdref version takes effect at the next server start.
Restart the server with `M-x eglot-shutdown` and `M-x eglot`. A server
on `PATH` is never upgraded.

## C, C++ and CUDA buffers

In a C, C++ or CUDA buffer with clangd on `exec-path`, simdref and
clangd run together. The rassumfrassum multiplexer (`rass`) runs the
two servers for one eglot connection. `rass` comes with the extension's
install. An install from before rass support gets `rass` at the next
daily check. lsp-mode runs simdref as an add-on client with clangd and
no multiplexer.

The companion server is the `simdref-companion-server` command list
(see Settings). Assembly buffers run simdref alone.

Hover on an asm string shows the simdref instruction text. Hover on a
C++ name shows the clangd declaration: both servers answer hover.

## Logging

Maintenance never opens a window. Success lines go to the `*simdref-log*`
buffer only. A failure (nonzero exit, timeout kill, missing executable,
sha mismatch) logs to that buffer and shows one echo-area line that
starts with `simdref:` and names the step that failed. The missing-server
notice prints once per Emacs session. A failed install shows for example:

```
simdref: simdref not found. Install it: uv tool install simdref (or pip install simdref), then run isa update. Instructions: https://github.com/simd-labs/simdref Failed step: curl -fsSL ... failed: exit 6
```

## Test

```sh
podman build -t emacs-simdref-test -f test/podman/Containerfile .
podman run --rm --network none -v "$PWD:/src:ro,Z" emacs-simdref-test
```

The suite drives `simdref-maintain` with fake `uv`, `isa`, `rass` and
`simdref-lsp` scripts. It needs no network: the install test fetches a
staged uv release from a `file://` URL. Mutation results live in
`test/MUTATIONS.md`.

## License

GPL-3.0-or-later. See LICENSE.

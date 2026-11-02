# emacs-simdref

Show the brief of an assembly instruction from the local simdref catalog.

`M-x eglot` on a buffer shows hover docs and inlay hints for instructions.
The catalog is local, so the server answers without network.

## Requirements

- Emacs 29.1 or newer
- `curl` and `tar` for the first install

## Setup

```elisp
(add-to-list 'load-path "/path/to/emacs-simdref")
(require 'simdref)
```

The package registers `simdref-lsp` with eglot for `asm-mode`, `c-mode`,
`c++-mode`, `c-ts-mode` and `c++-ts-mode`. When lsp-mode is loaded, it
registers the server there too.

Without a server on `PATH`, the package installs it in the background to
`(locate-user-emacs-file "simdref/")`, then starts it. The first
`M-x eglot` waits for that install. It downloads a pinned `uv`, installs
`simdref` and the catalog. This takes minutes.

Once a day the package upgrades that copy and refreshes the catalog. A
new simdref version takes effect at the next server start. A server on
`PATH` is never upgraded.

Set `simdref-install-dir` to move the private install.

If the install fails, the package shows:

```
simdref-lsp not found. Run: uv tool install simdref && isa update
https://github.com/simd-labs/simdref
```

## Test

```sh
podman build -t emacs-simdref-test -f test/podman/Containerfile .
podman run --rm --network none -v "$PWD:/src:ro,Z" emacs-simdref-test
```

The suite drives `simdref-maintain` with fake `uv` and `isa` scripts.
It needs no network: the install test fetches a staged uv release from
a `file://` URL. Mutation results live in `test/MUTATIONS.md`.

## License

GPL-3.0-or-later. See LICENSE.

# Mutation list for simdref.el and simdref-rass.py

Each mutation is one edit to `simdref.el` or `simdref-rass.py`. A
mutation counts as caught only when its named test fails. The runner
copies the edited file aside, applies the edit, runs the suite in the
container, restores the file and proves the restore with `cmp`.

| id | mutation | edit | named test |
|----|----------|------|------------|
| M1 | remove time gate | `(when (simdref--claim-marker marker)` becomes `(when t` | `simdref-test-throttle-skips-same-day` |
| M2 | remove sha check | `(if (simdref--sha256-match-p archive checksum)` becomes `(if t` | `simdref-test-install-rejects-bad-sha` |
| M3 | drop PATH-install guard | `(when (simdref--managed-p server dir)` becomes `(when t` | `simdref-test-path-install-untouched` |
| M4 | delete today's marker in cleanup | `(unless (equal f marker)` becomes `(unless nil` | `simdref-test-todays-marker-kept` |
| M5 | drop executable-exists check | `(if (not (file-executable-p program))` becomes `(if nil` | `simdref-test-missing-executable-quiet` |
| M6 | drop catalog refresh after failed upgrade | the `isa vaddps --short` run form in `simdref--maybe-upgrade` becomes `nil` | `simdref-test-refresh-after-failed-upgrade` |
| M7 | log nonzero exit at the success level | `(simdref--echo "%s" line)` becomes `(simdref--log "%s" line)` in `simdref--exit-log` | `simdref-test-nonzero-louder-than-success` |
| M8 | stamp written before isa update | `(refresh ()` becomes `(refresh () (simdref--stamp dir)` | `simdref-test-failed-isa-update-no-stamp` |
| M9 | predicate ignoring the stamp | `(file-exists-p (expand-file-name "installed" dir))` becomes `t` | `simdref-test-killed-uv-install-not-installed` |
| M10 | display-warning reintroduced | `(message "simdref: simdref-lsp not found; %s" cause)` becomes the same call behind `(progn (display-warning 'simdref cause :warning) ...)` | `simdref-test-failed-install-quiet` |
| M11 | contact waiting loop reintroduced | the `user-error` in `simdref--eglot-contact` becomes a `while simdref--installing` wait loop that returns the contact | `simdref-test-eglot-contact-never-waits` |
| M12 | stamp before rass install | `(install-rass ()` becomes `(install-rass () (simdref--stamp dir)` | `simdref-test-install-rass-step-stamp-last` |
| M13 | contact ignoring the companion check | `(if (and rass (executable-find (car simdref-companion-server)))` becomes `(if rass` | `simdref-test-contact-cxx-no-clangd` |
| M14 | asm-mode routed through rass | `(memq major-mode simdref--c-modes)` becomes `t` | `simdref-test-contact-asm-no-rass` |
| M15 | simdref no longer first in the rass command | the tail of the preset append in `simdref--eglot-contact` becomes `(list "--") simdref-companion-server (list "--" cmd)` | `simdref-test-contact-cxx-rass-with-clangd` |
| M16 | hover routing back to primary only | the hover fan-out in `simdref-rass.py` becomes `s for s in servers[:1]` | `test_hover_routes_to_all_hover_servers` |
| M17 | maintenance skips the missing-rass install | the rass install run form in `simdref--maybe-upgrade` becomes `(funcall refresh nil nil)` | `simdref-test-daily-install-rass-missing` |

The throttle mutation target is the time gate (M1). The named test
fails when a same-day restart re-runs the network step.

## Results

Each run: full suite in the container, named test must fail. The
restore copies `simdref.el` back from the pristine copy and `cmp`
proves it byte-identical (`cmp exit=0`).

| id | named test result | verdict |
|----|-------------------|---------|
| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |

Verdict `failed-loud` means a contract test caught the mutation.
Verdict `silent-pass` means no test caught the mutation.
All eleven mutations are caught. Every restore is clean.

M6 note: the first run of M6 replaced the whole run form with `nil`
and left one unbalanced paren. The load then aborted before any test
ran, which is no result. The table holds the corrected edit that keeps
the parens balanced. With the corrected edit the named test fails.

## Results at the rassumfrassum commit

Each run: full suite in the container, named test must fail. The
restore copies `simdref.el` back from the pristine copy and `cmp`
proves it byte-identical (`cmp exit=0`). All fourteen mutations run
again at this commit, old ones included.

| id | named test result | verdict |
|----|-------------------|---------|
| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
| M12 | `simdref-test-install-rass-step-stamp-last` FAILED | failed-loud |
| M13 | `simdref-test-contact-cxx-no-clangd` FAILED | failed-loud |
| M14 | `simdref-test-contact-asm-no-rass` FAILED | failed-loud |

All fourteen mutations are caught. Every restore is clean.

## Results at the rass order commit

Each run: full suite in the container, named test must fail. The
restore copies `simdref.el` back from the pristine copy and `cmp`
proves it byte-identical (`cmp exit=0`). All fifteen mutations run
again at this commit, old ones included. M15 is new: it reverts the
rass command order, and the contact test catches it.

| id | named test result | verdict |
|----|-------------------|---------|
| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
| M12 | `simdref-test-install-rass-step-stamp-last` FAILED | failed-loud |
| M13 | `simdref-test-contact-cxx-no-clangd` FAILED | failed-loud |
| M14 | `simdref-test-contact-asm-no-rass` FAILED | failed-loud |
| M15 | `simdref-test-contact-cxx-rass-with-clangd` FAILED | failed-loud |

All fifteen mutations are caught. Every restore is clean.

## Results at the rass preset commit

Each run: full suite in the container, named test must fail. The
restore copies the edited file back from the pristine copy and `cmp`
proves it byte-identical (`cmp exit=0`). All sixteen mutations run
again at this commit, old ones included. M16 is new: it reverts the
hover fan-out in `simdref-rass.py` to primary-only routing, and the
Python preset test catches it.

| id | named test result | verdict |
|----|-------------------|---------|
| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
| M12 | `simdref-test-install-rass-step-stamp-last` FAILED | failed-loud |
| M13 | `simdref-test-contact-cxx-no-clangd` FAILED | failed-loud |
| M14 | `simdref-test-contact-asm-no-rass` FAILED | failed-loud |
| M15 | `simdref-test-contact-cxx-rass-with-clangd` FAILED | failed-loud |
| M16 | `test_hover_routes_to_all_hover_servers` FAILED | failed-loud |

All sixteen mutations are caught. Every restore is clean.

## Results at the fallback fix commit

Each run: full suite in the container, named test must fail. The
restore copies the edited file back from the pristine copy and `cmp`
proves it byte-identical (`cmp exit=0`). All seventeen mutations run
again at this commit, old ones included. M17 is new: it skips the
missing-rass install in the daily check, and the new daily test
catches it.

| id | named test result | verdict |
|----|-------------------|---------|
| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
| M12 | `simdref-test-install-rass-step-stamp-last` FAILED | failed-loud |
| M13 | `simdref-test-contact-cxx-no-clangd` FAILED | failed-loud |
| M14 | `simdref-test-contact-asm-no-rass` FAILED | failed-loud |
| M15 | `simdref-test-contact-cxx-rass-with-clangd` FAILED | failed-loud |
| M16 | `test_hover_routes_to_all_hover_servers` FAILED | failed-loud |
| M17 | `simdref-test-daily-install-rass-missing` FAILED | failed-loud |

All seventeen mutations are caught. Every restore is clean.

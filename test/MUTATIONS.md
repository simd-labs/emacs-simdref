# Mutation list for simdref.el

Each mutation is one edit to `simdref.el`. A mutation counts as caught
only when its named test fails. The runner copies `simdref.el` aside,
applies the edit, runs the suite in the container, restores the file and
proves the restore with `cmp`.

| id | mutation | edit | named test |
|----|----------|------|------------|
| M1 | remove time gate | `(when (simdref--claim-marker marker)` becomes `(when t` | `simdref-test-throttle-skips-same-day` |
| M2 | remove sha check | `(if (simdref--sha256-match-p archive checksum)` becomes `(if t` | `simdref-test-install-rejects-bad-sha` |
| M3 | drop PATH-install guard | `(when (simdref--managed-p server dir)` becomes `(when t` | `simdref-test-path-install-untouched` |
| M4 | delete today's marker in cleanup | `(unless (equal f marker)` becomes `(unless nil` | `simdref-test-todays-marker-kept` |
| M5 | drop executable-exists check | `(if (not (file-executable-p program))` becomes `(if nil` | `simdref-test-missing-executable-quiet` |
| M6 | drop catalog refresh after failed upgrade | the `isa vaddps --short` run form becomes `nil` | `simdref-test-refresh-after-failed-upgrade` |
| M7 | log nonzero exit at the success level | `simdref--warn` becomes `simdref--log` in `simdref--exit-log` | `simdref-test-nonzero-louder-than-success` |

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

Verdict `failed-loud` means a contract test caught the mutation.
Verdict `silent-pass` means no test caught the mutation.
All seven mutations are caught. Every restore is clean.

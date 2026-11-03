1|# Mutation list for simdref.el
2|
3|Each mutation is one edit to `simdref.el`. A mutation counts as caught
4|only when its named test fails. The runner copies `simdref.el` aside,
5|applies the edit, runs the suite in the container, restores the file and
6|proves the restore with `cmp`.
7|
8|| id | mutation | edit | named test |
9||----|----------|------|------------|
10|| M1 | remove time gate | `(when (simdref--claim-marker marker)` becomes `(when t` | `simdref-test-throttle-skips-same-day` |
11|| M2 | remove sha check | `(if (simdref--sha256-match-p archive checksum)` becomes `(if t` | `simdref-test-install-rejects-bad-sha` |
12|| M3 | drop PATH-install guard | `(when (simdref--managed-p server dir)` becomes `(when t` | `simdref-test-path-install-untouched` |
13|| M4 | delete today's marker in cleanup | `(unless (equal f marker)` becomes `(unless nil` | `simdref-test-todays-marker-kept` |
14|| M5 | drop executable-exists check | `(if (not (file-executable-p program))` becomes `(if nil` | `simdref-test-missing-executable-quiet` |
15|| M6 | drop catalog refresh after failed upgrade | the `isa vaddps --short` run head `(simdref--run (expand-file-name (simdref--exe "isa")` becomes `(ignore (expand-file-name (simdref--exe "isa")` | `simdref-test-refresh-after-failed-upgrade` |
16|| M7 | log nonzero exit at the success level | `(simdref--echo "%s" line)` becomes `(simdref--log "%s" line)` in `simdref--exit-log` | `simdref-test-nonzero-louder-than-success` |
17|| M8 | stamp written before isa update | `(refresh ()` becomes `(refresh () (simdref--stamp dir)` | `simdref-test-failed-isa-update-no-stamp` |
18|| M9 | predicate ignoring the stamp | `(file-exists-p (expand-file-name "installed" dir))` becomes `t` | `simdref-test-killed-uv-install-not-installed` |
19|| M10 | display-warning reintroduced | `(message "simdref: simdref-lsp not found; %s" cause)` becomes the same call behind `(progn (display-warning 'simdref cause :warning) ...)` | `simdref-test-failed-install-quiet` |
20|| M11 | contact waiting loop reintroduced | the `user-error` in `simdref--eglot-contact` becomes a `while simdref--installing` wait loop that returns the contact | `simdref-test-eglot-contact-never-waits` |
21|| M12 | stamp before rass install | `(install-rass ()` becomes `(install-rass () (simdref--stamp dir)` | `simdref-test-install-rass-step-stamp-last` |
22|| M13 | contact ignoring the companion check | `(if (and rass (executable-find (car simdref-companion-server)))` becomes `(if rass` | `simdref-test-contact-cxx-no-clangd` |
23|| M14 | asm-mode routed through rass | `(memq major-mode simdref--c-modes)` becomes `t` | `simdref-test-contact-asm-no-rass` |
24|| M15 | simdref no longer first in the rass command | the append form `(append (list rass "--") (list cmd "--") simdref-companion-server)` becomes `(append (list rass "--") simdref-companion-server (list "--" cmd))` | `simdref-test-contact-cxx-rass-with-clangd` |
25|
26|The throttle mutation target is the time gate (M1). The named test
27|fails when a same-day restart re-runs the network step.
28|
29|## Results
30|
31|Each run: full suite in the container, named test must fail. The
32|restore copies `simdref.el` back from the pristine copy and `cmp`
33|proves it byte-identical (`cmp exit=0`).
34|
35|| id | named test result | verdict |
36||----|-------------------|---------|
37|| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
38|| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
39|| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
40|| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
41|| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
42|| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
43|| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
44|| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
45|| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
46|| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
47|| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
48|
49|Verdict `failed-loud` means a contract test caught the mutation.
50|Verdict `silent-pass` means no test caught the mutation.
51|All eleven mutations are caught. Every restore is clean.
52|
53|M6 note: the first run of M6 replaced the whole run form with `nil`
54|and left one unbalanced paren. The load then aborted before any test
55|ran, which is no result. The table holds the corrected edit that keeps
56|the parens balanced. With the corrected edit the named test fails.
57|
58|## Results at the rassumfrassum commit
87|
88|Each run: full suite in the container, named test must fail. The
89|restore copies `simdref.el` back from the pristine copy and `cmp`
90|proves it byte-identical (`cmp exit=0`). All fourteen mutations run
91|again at this commit, old ones included.
92|
93|| id | named test result | verdict |
94||----|-------------------|---------|
95|| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
96|| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
97|| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
98|| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
99|| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
100|| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
101|| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
102|| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
103|| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
104|| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
105|| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
106|| M12 | `simdref-test-install-rass-step-stamp-last` FAILED | failed-loud |
107|| M13 | `simdref-test-contact-cxx-no-clangd` FAILED | failed-loud |
108|| M14 | `simdref-test-contact-asm-no-rass` FAILED | failed-loud |
109|
110|All fourteen mutations are caught. Every restore is clean.

## Results at the rass order commit
59|
60|Each run: full suite in the container, named test must fail. The
61|restore copies `simdref.el` back from the pristine copy and `cmp`
62|proves it byte-identical (`cmp exit=0`). All fifteen mutations run
63|again at this commit, old ones included. M15 is new: it reverts the
64|rass command order, and the contact test catches it.
65|
66|| id | named test result | verdict |
67||----|-------------------|---------|
68|| M1 | `simdref-test-throttle-skips-same-day` FAILED | failed-loud |
69|| M2 | `simdref-test-install-rejects-bad-sha` FAILED | failed-loud |
70|| M3 | `simdref-test-path-install-untouched` FAILED | failed-loud |
71|| M4 | `simdref-test-todays-marker-kept` FAILED | failed-loud |
72|| M5 | `simdref-test-missing-executable-quiet` FAILED | failed-loud |
73|| M6 | `simdref-test-refresh-after-failed-upgrade` FAILED | failed-loud |
74|| M7 | `simdref-test-nonzero-louder-than-success` FAILED | failed-loud |
75|| M8 | `simdref-test-failed-isa-update-no-stamp` FAILED | failed-loud |
76|| M9 | `simdref-test-killed-uv-install-not-installed` FAILED | failed-loud |
77|| M10 | `simdref-test-failed-install-quiet` FAILED | failed-loud |
78|| M11 | `simdref-test-eglot-contact-never-waits` FAILED | failed-loud |
79|| M12 | `simdref-test-install-rass-step-stamp-last` FAILED | failed-loud |
80|| M13 | `simdref-test-contact-cxx-no-clangd` FAILED | failed-loud |
81|| M14 | `simdref-test-contact-asm-no-rass` FAILED | failed-loud |
82|| M15 | `simdref-test-contact-cxx-rass-with-clangd` FAILED | failed-loud |
83|
84|All fifteen mutations are caught. Every restore is clean.
85|
86|

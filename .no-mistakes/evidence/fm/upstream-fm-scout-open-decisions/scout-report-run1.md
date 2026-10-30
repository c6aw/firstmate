# Scout report: should fm-lab-home.sh gain a `list` subcommand?

## What the script does today (bin/fm-lab-home.sh, 107 lines)
- `create <dir>` (l.40-54): mkdir, stamp marker via `fm_gate_lab_mark` (refuses non-empty dir), make state/data/config/projects, print dir.
- `tmux-dir <dir>` (l.55-77): create or print a private `/tmp/fml.XXXXXX` socket dir; path recorded in `<dir>/state/.fm-lab-tmux-dir`.
- `teardown <dir>` (l.78-102): kill-check tmux sockets, remove the socket dir. It does NOT delete the home; callers use `rm -rf`.
- Anything else: usage error, exit 2 (l.103-106).
- Every subcommand takes a caller-chosen path. Callers: bin/fm-live-lab.sh:29, tests/fm-live-lab.test.sh:58,735, tests/fm-gate-refuse.test.sh:162, tests/fm-watch-wedge-cap-live.test.sh:133. Test labs live under per-test temp dirs.

## Key finding
There is no registry and no fixed location. Lab homes are scattered, caller-chosen directories; the only identity is the `.fm-lab-home` marker file (written at l.48 via bin/fm-gate-refuse-lib.sh:96-102; content is a token, no timestamp). A `list` has nothing to enumerate today.

## What adding `list` would involve
1. Choose a discovery source. Options:
   a. Scan a root (`list [root]`, e.g. `${TMPDIR:-/tmp}`) with `find -maxdepth 3 -name .fm-lab-home`. About 5 lines, no new state, but it only finds labs under that root.
   b. Append each `create` to a registry file. This adds state that goes stale when callers `rm -rf` (the script never learns of it), so it needs pruning. Not recommended.
2. Print each hit's path (one per line), validating with the same `-f marker && -d state` test used at l.58, l.81.
3. Add a usage-line entry (l.104), header usage (l.10-13), and a docs/scripts.md row (l.41). Add a test case in tests/fm-gate-refuse.test.sh next to the create tests (~l.284).
4. Size: roughly 10-15 lines plus a test. Read-only, so it adds no new authorization risk; it must not follow symlinks.

## Age
Age is derivable without changing the marker: `stat` mtime of `.fm-lab-home` (the script already has a Darwin/Linux `stat` split at l.32-37, so a third helper would match it). Cost: about 5 more lines, one more portable-stat helper, and a format choice (seconds vs. human). Caveat: mtime is creation time only until something rewrites the marker; nothing does today.

## Evidence
Commands: read bin/fm-lab-home.sh; `grep -rn fm-lab-home` over the repo; read fm_gate_lab_mark in bin/fm-gate-refuse-lib.sh. Nothing was run or edited. Not checked: whether any external tool relies on the exact usage text.

## Recommendation
Low value today: no caller needs enumeration, since each creator already knows its dir and cleans up. If wanted, add scan-only `list [root]` (option 1a), and add age only if a stale-lab cleanup use is real. Do not build a registry. Ponytail view: skip both until a concrete caller exists.

## Open decisions: options and my pick
1. Add `list` at all? Options: (a) no, (b) scan-only `list [root]`. Pick (a): no caller needs it. Captain's call (product choice).
2. If added, print age? Options: (a) path only, (b) path + age from marker mtime. Pick (a) unless stale-lab cleanup is the goal. Captain's call.

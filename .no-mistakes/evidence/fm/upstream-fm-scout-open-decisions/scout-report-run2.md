# Scout: a `list` subcommand for bin/fm-lab-home.sh

## What the script does today (read at HEAD 47ab4f93)
- Three subcommands, each taking a caller-chosen path (`bin/fm-lab-home.sh:10-13`, usage at :104):
  `create <dir>` stamps the marker and makes state/ data/ config/ projects/ (:40-54);
  `tmux-dir <dir>` creates or re-validates a private `/tmp/fml.XXXXXX` socket dir recorded in `state/.fm-lab-tmux-dir` (:55-77);
  `teardown <dir>` removes that socket dir after confirming no tmux server lives there (:78-102).
- No registry. A lab home is known only by `<dir>/.fm-lab-home` holding `fm-lab-home v1`
  (`bin/fm-gate-refuse-lib.sh:83-92`). Homes are removed by plain `rm -rf` (`fm-lab-home.sh:15-16`).
- Callers pick unrelated roots: tests use their own temp dirs (`tests/fm-gate-refuse.test.sh:162`,
  `tests/fm-approval-failover.test.sh:72`); `bin/fm-live-lab.sh` defaults to `/tmp/fmlab.XXXXXX/home` (:18-19, :29).
- `find /tmp -maxdepth 3 -name .fm-lab-home` today finds one: `/tmp/fm-lab.gDDMRw` (this lab).

## What adding `list` would involve
- `list [<root>]`: `find <root> -maxdepth N -name .fm-lab-home`, keep dirs where `fm_gate_lab_home` passes,
  print one path per line. Default root would be `/tmp`, since no other place is known; depth must reach
  `/tmp/fmlab.X/home` (3). Homes under other roots (a test's `$TMP`, `$TMPDIR` on macOS) are missed unless passed.
- About 10-15 lines, plus the header usage, the usage error line, the `docs/scripts.md:41` row, and one test
  in `tests/fm-gate-refuse.test.sh` (create two homes plus one bad-token dir, assert only the two print).
- No new state; read-only, so no safety risk. The "lab marker only on an empty dir" rule is untouched.
- Age option: marker mtime via the same Linux/Darwin `stat` split the script already uses (:32-37);
  about 3 more lines and one more test assertion. Output becomes `<age-seconds or date> <path>`,
  which changes the line format any caller would parse - decide it before first release, not after.

## Assessment
- No caller or test needs a list today; nothing in bin/ or tests/ enumerates lab homes. The only use I see is
  finding homes leaked by crashed runs, and the one-line `find` above already does that.
- Ponytail view: do not add it until a leak is actually seen or a cleanup job needs it. If added, keep it
  path-only first; age is the cheap follow-up.

## Open decisions: options and my pick
One captain call (product choice, captain only), one gate with two questions:
1. Add `list`? Options: (a) no, document the `find` line; (b) yes, `list [<root>]`, default `/tmp`.
   My pick: (a) - no measured need, and a default root silently misses homes elsewhere.
2. If yes, print age too? Options: (a) path only; (b) age plus path.
   My pick: (a) path only - stable output; add age when someone needs it for cleanup.

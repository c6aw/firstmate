# fm-lab-home.sh subcommands

Finding: `bin/fm-lab-home.sh` accepts exactly 3 subcommands, each taking one `<dir>` argument:
1. `create <dir>` - makes a marked lab home (state/, data/, config/, projects/) and prints it (bin/fm-lab-home.sh:40).
2. `tmux-dir <dir>` - creates or prints the home's private tmux socket directory (bin/fm-lab-home.sh:55).
3. `teardown <dir>` - removes that socket directory (bin/fm-lab-home.sh:78).
Anything else hits the `*)` arm, prints the usage line and exits 2 (bin/fm-lab-home.sh:103-105).

Evidence: read the `case "${1:-}"` dispatch at bin/fm-lab-home.sh:39 and the header usage at :10-13, at HEAD 47ab4f93 (worktree /tmp/fm-lab.gDDMRw/scratch). Nothing was edited or run.

Recommendation: none; no work to ship.

## Open decisions: options and my pick
None.

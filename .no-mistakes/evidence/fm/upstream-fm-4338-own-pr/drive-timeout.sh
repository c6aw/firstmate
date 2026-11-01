#!/usr/bin/env bash
# drive-timeout.sh <repo-root> <label> <mode: timeout|force-fallback|no-timeout-path> <check-body-file>
# Mints a disposable lab home, registers a custom check, runs the real watcher once, prints its wake.
set -u
ROOT=$1 LABEL=$2 MODE=$3 BODY=$4
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
cp "$BODY" "$LAB/state/custom.check.sh"; chmod 0700 "$LAB/state/custom.check.sh"
FM_HOME="$LAB" "$ROOT/bin/fm-check-register.sh" custom || { echo register failed; exit 1; }
path=/usr/bin:/bin
force=0
case $MODE in
  force-fallback) force=1 ;;
  no-timeout-path)
    path="$LAB/nobin"; mkdir -p "$path"
    for f in /usr/bin/*; do case ${f##*/} in timeout|gtimeout) ;; *) ln -s "$f" "$path/" ;; esac; done ;;
esac
echo "== $LABEL (mode=$MODE, root=$ROOT)"
PATH="$path" command -v timeout >/dev/null && echo "timeout on PATH: yes" || echo "timeout on PATH: no"
start=$(date +%s)
rc=0
env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
  FM_HOME="$LAB" FM_CHECK_TIMEOUT=2 FM_CHECK_INTERVAL=0 FM_POLL=0.05 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 \
  FM_CHECK_FORCE_FALLBACK=$force PATH="$path" \
  /usr/bin/timeout 40 "$ROOT/bin/fm-watch.sh" > "$LAB/out" 2> "$LAB/err" || rc=$?
echo "watcher rc=$rc elapsed=$(( $(date +%s) - start ))s"
echo "-- watcher stdout:"; cat "$LAB/out"
echo "-- leftover check processes:"; { ps -eo pid=,args= | grep -E "^ *[0-9]+ fm-lab-marker" || echo none; }
rm -rf "$LAB"

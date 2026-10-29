#!/usr/bin/env bash
# Live driver: real herdr 0.9.5, isolated fm-lab-* session, disposable lab home.
set -u
WT=$1
cd "$WT"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); bin/fm-lab-home.sh create "$LAB" >/dev/null
S=$(bin/fm-herdr-lab.sh name extsrv)
echo "lab home: <tmp>/$(basename "$LAB")  session: $S"
cleanup() { bin/fm-herdr-lab.sh teardown "$S" >/dev/null 2>&1; echo "teardown rc=$?"; rm -rf "$LAB"; }
trap cleanup EXIT
running() { HERDR_SESSION="$S" herdr status --json --session "$S" 2>/dev/null | jq -r '.server.running // false'; }
server_pids() { pgrep -u "$UID" -f "herdr server --session $S\$" | tr '\n' ' '; }
ensure() { env FM_HOME="$LAB" FM_SNAPSHOT_NOW=2026-01-01T00:00:00Z FM_CREW_STATE_NO_FORGE=1 FM_HERDR_SENTINEL=kept \
  bash -c '. bin/backends/herdr.sh; fm_backend_herdr_server_ensure "$1"' _ "$S"; }

echo "== operator service (lab helper) starts the server"
bin/fm-herdr-lab.sh provision "$S" || exit 1
echo "running=$(running) pids=[$(server_pids)]"
bin/fm-herdr-lab.sh stop "$S" >/dev/null; sleep 1
echo "after service stop: running=$(running) pids=[$(server_pids)]"

echo; echo "== S1: session listed in config/herdr-server-external, service down"
printf 'some-other-session\n  %s \n' "$S" > "$LAB/config/herdr-server-external"
t0=$(date +%s); out=$(ensure 2>&1); rc=$?; t1=$(date +%s)
echo "ensure rc=$rc elapsed=$((t1-t0))s"; echo "stderr: $out" | sed "s#$LAB#<lab>#g"
echo "after: running=$(running) pids=[$(server_pids)]"

echo; echo "== S2: listed, service brings server back during the wait"
ensure > "$LAB/s2.out" 2>&1 & epid=$!
sleep 2; echo "during wait (2s): running=$(running) pids=[$(server_pids)]"
bin/fm-herdr-lab.sh provision "$S" || echo "service restart failed"
wait "$epid"; echo "ensure rc=$? stderr=[$(cat "$LAB/s2.out")]"
echo "after: running=$(running) server process count=$(server_pids | wc -w)"
bin/fm-herdr-lab.sh stop "$S" >/dev/null; sleep 1

echo; echo "== S3: session not listed, Firstmate starts the server with per-call vars scrubbed"
printf 'some-other-session\n' > "$LAB/config/herdr-server-external"
echo "before: running=$(running) pids=[$(server_pids)]"
ensure; echo "ensure rc=$?"
echo "after: running=$(running) pids=[$(server_pids)]"
for p in $(server_pids); do
  echo "server pid $p environment (FM_*/sentinel names only):"
  tr '\0' '\n' < /proc/$p/environ | grep -E '^(FM_[A-Z_]*|CLAUDECODE)=' | sed 's/=.*//' | sort | sed 's/^/  /'
  for v in FM_SNAPSHOT_NOW FM_CREW_STATE_NO_FORGE FM_HOME CLAUDECODE; do
    tr '\0' '\n' < /proc/$p/environ | grep -q "^$v=" && echo "  LEAKED $v" || echo "  absent $v"
  done
  tr '\0' '\n' < /proc/$p/environ | grep -q '^FM_HERDR_SENTINEL=kept' && echo "  kept FM_HERDR_SENTINEL"
done

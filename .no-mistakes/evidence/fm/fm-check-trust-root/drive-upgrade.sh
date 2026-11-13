#!/usr/bin/env bash
# Register a check with the old version, upgrade, then run the documented one-time re-register.
set -u
NEW=$1 OLD=$2
LABS=(); trap 'rm -rf -- "${LABS[@]}"' EXIT
new_lab() { LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LABS+=("$LAB"); "$NEW/bin/fm-lab-home.sh" create "$LAB" >/dev/null; S="$LAB/state"
  printf '#!/usr/bin/env bash\ntouch %q\necho legacy check ran\n' "$LAB/ran" > "$S/legacy.check.sh"; chmod 0700 "$S/legacy.check.sh"
  echo "-- old version registers:"; FM_HOME="$LAB" "$OLD/bin/fm-check-register.sh" legacy; ls "$S" | grep trust; }
watch_once() {
  rm -f "$S/.last-check"
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    FM_HOME="$LAB" FM_CHECK_INTERVAL=0 FM_POLL=0.1 FM_HEARTBEAT=999999 timeout 8 "$NEW/bin/fm-watch.sh" 2>&1 | tail -2
}
echo "== A. upgraded watcher, old state/ record only"; new_lab; watch_once
[ -e "$LAB/ran" ] && echo "RESULT: old state/ record still trusted" || echo "RESULT: old state/ record ignored"
echo "== B. upgraded home after the documented one-time step"; new_lab
FM_HOME="$LAB" "$NEW/bin/fm-check-register.sh" legacy; ls "$LAB/config/trust"
watch_once
[ -e "$LAB/ran" ] && echo "RESULT: re-registered check executed" || echo "RESULT: re-registered check NOT executed"
echo "-- unregister removes both the new and the leftover state/ record:"
FM_HOME="$LAB" "$NEW/bin/fm-check-unregister.sh" legacy; ls -A "$S" | grep -c trust | sed 's/^/trust files in state: /'; ls -A "$LAB/config/trust" | wc -l | sed 's/^/trust files in config\/trust: /'

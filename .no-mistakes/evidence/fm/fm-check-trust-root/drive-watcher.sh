#!/usr/bin/env bash
# Drive the real bin/fm-watch.sh against a disposable lab home.
set -u
ROOT=$1
LABS=()
trap 'rm -rf -- "${LABS[@]}"' EXIT
new_lab() { LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LABS+=("$LAB"); "$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null; S="$LAB/state"; }
new_lab
watch_once() {
  rm -f "$S/.last-check"
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    FM_HOME="$LAB" FM_CHECK_INTERVAL=0 FM_POLL=0.1 FM_HEARTBEAT=999999 timeout 8 "$ROOT/bin/fm-watch.sh" 2>&1 | tail -3
  echo "watcher rc=${PIPESTATUS[0]}"
}
mk() { printf '#!/usr/bin/env bash\ntouch %q\necho "%s check ran"\n' "$LAB/$1.ran" "$1" > "$S/$1.check.sh"; chmod 0700 "$S/$1.check.sh"; }

echo "== 1. forged state/-only trust record (issue repro, via the real watcher)"
mk evil
hash=$(sha256sum "$S/evil.check.sh" | awk '{print $1}')
printf 'fm-custom-check-v1\n%s\n' "$hash" > "$S/evil.check-trust"; chmod 0600 "$S/evil.check-trust"
watch_once
[ -e "$LAB/evil.ran" ] && echo "RESULT: forged check executed" || echo "RESULT: forged check refused (not executed)"
new_lab

echo "== 2. operator-registered check"
mk good
FM_HOME="$LAB" "$ROOT/bin/fm-check-register.sh" good
ls -l "$LAB/config/trust/" | sed 1d
ls "$S" | grep -c check-trust | sed 's/^/trust records under state\/: /'
watch_once
[ -e "$LAB/good.ran" ] && echo "RESULT: registered check executed" || echo "RESULT: registered check NOT executed"

echo "== 3. state/ writer swaps bytes of registered check"
new_lab; mk good; FM_HOME="$LAB" "$ROOT/bin/fm-check-register.sh" good; rm -f "$LAB/good.ran"; printf '#!/usr/bin/env bash\ntouch %q\necho tampered\n' "$LAB/good.ran" > "$S/good.check.sh"; chmod 0700 "$S/good.check.sh"
watch_once
[ -e "$LAB/good.ran" ] && echo "RESULT: tampered check executed" || echo "RESULT: tampered check refused"

echo "== 4. unregister removes config/trust record"
FM_HOME="$LAB" "$ROOT/bin/fm-check-unregister.sh" good; echo "unregister rc=$?"
ls -A "$LAB/config/trust/"; echo "(listing of config/trust ends)"

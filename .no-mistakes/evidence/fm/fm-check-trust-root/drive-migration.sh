#!/usr/bin/env bash
# Live: a check registered under the old layout (trust in state/) is refused until the documented re-register.
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
S=$LAB/state
clean() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
sweep() { rm -f "$S/.last-check" "$S/.wake-queue" "$LAB/old-ran"; clean FM_CHECK_INTERVAL=0 FM_POLL=0.1 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 timeout 8 "$ROOT/bin/fm-watch.sh" >"$LAB/w.out" 2>"$LAB/w.err"; rc=$?; sed "s/^/   out: /" "$LAB/w.out" "$LAB/w.err" | head -4; (exit $rc); echo "   watcher exit=$? (124 = sweep stayed silent until bound)"; }
printf '#!/usr/bin/env bash\ntouch %q\necho old-ran\n' "$LAB/old-ran" > "$S/old.check.sh"; chmod 700 "$S/old.check.sh"
printf 'fm-custom-check-v1\n%s\n' "$(sha256sum "$S/old.check.sh" | cut -d' ' -f1)" > "$S/old.check-trust"; chmod 600 "$S/old.check-trust"
echo "-- before re-register (only legacy state/old.check-trust):"; sweep
[ -e "$LAB/old-ran" ] && echo "RESULT legacy-record: RAN" || echo "RESULT legacy-record: IGNORED"
echo "-- documented step: bin/fm-check-register.sh old"; clean "$ROOT/bin/fm-check-register.sh" old
for i in 1 2 3; do sweep; [ -e "$LAB/old-ran" ] && break; done  # a first exit may be an unrelated resurfaced wake
[ -e "$LAB/old-ran" ] && echo "RESULT after-re-register: RAN" || echo "RESULT after-re-register: DID NOT RUN"
echo "-- when watch: retire + re-arm path"
W=$ROOT/bin/fm-procevent-when.sh
clean "$W" arm w --interval 0.1 --stable 1 --condition true --action touch "$LAB/w-fired" >/dev/null
sid=$(clean "$W" source-id w); mv "$LAB/config/trust/$sid.when-trust" "$S/when/$sid.trust"  # simulate old-layout watch
clean timeout 10 "$W" run "$sid" 2>&1 | grep -o '"class":"[a-z-]*"' | head -1 | sed 's/^/   old-layout outcome: /'
[ -e "$LAB/w-fired" ] && echo "RESULT old-layout-when: FIRED" || echo "RESULT old-layout-when: REFUSED"
clean "$W" retire w 2>&1 | sed 's/^/   retire: /'
[ -e "$S/when/$sid.trust" ] && echo "   legacy state/when trust left behind" || echo "   legacy state/when trust removed by retire"
rm -f "$S/when/$sid.fired"
clean "$W" arm w --interval 0.1 --stable 1 --condition true --action touch "$LAB/w-fired" 2>&1 | head -1 | sed 's/^/   re-arm: /'
clean timeout 10 "$W" run "$sid" >/dev/null 2>&1
[ -e "$LAB/w-fired" ] && echo "RESULT re-armed-when: FIRED" || echo "RESULT re-armed-when: DID NOT FIRE"
rm -rf "$LAB"; echo "== lab removed"

#!/usr/bin/env bash
# Live driver: real fm-watch.sh / fm-check-register.sh / fm-procevent-when.sh against a disposable lab home.
# Usage: drive-trust-root.sh <firstmate-root> <label>
set -u
ROOT=$1; LABEL=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null 2>&1 || mkdir -p "$LAB/state" "$LAB/config" "$LAB/data" "$LAB/projects"
S=$LAB/state
clean() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
echo "== [$LABEL] lab home: (tmp)/$(basename "$LAB")"
# 1. Issue repro: forged state-only trust record
printf '#!/usr/bin/env bash\ntouch %q\necho evil-ran\n' "$LAB/evil-ran" > "$S/evil.check.sh"; chmod 700 "$S/evil.check.sh"
h=$(sha256sum "$S/evil.check.sh" | cut -d' ' -f1)
printf 'fm-custom-check-v1\n%s\n' "$h" > "$S/evil.check-trust"; chmod 600 "$S/evil.check-trust"
# 2. Legit check registered by the operator entrypoint
printf '#!/usr/bin/env bash\ntouch %q\necho good-ran\n' "$LAB/good-ran" > "$S/good.check.sh"; chmod 700 "$S/good.check.sh"
echo "-- register good:"; clean "$ROOT/bin/fm-check-register.sh" good; echo "   exit=$?"
echo "-- trust files:"; (cd "$LAB" && find . -name '*trust*' | sort | sed 's/^/   /')
echo "-- run real watcher one sweep (bounded 20s):"
clean FM_CHECK_INTERVAL=0 FM_POLL=0.1 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 timeout 20 "$ROOT/bin/fm-watch.sh" > "$LAB/watch.out" 2> "$LAB/watch.err"
echo "   watcher exit=$?"
sed 's/^/   stdout: /' "$LAB/watch.out" | head -5
grep -h 'check' "$S/.wake-queue" 2>/dev/null | sed 's/^/   wake-queue: /' | head -5
grep -hi 'reject\|refus\|unauth' "$S"/*.log "$LAB/watch.err" 2>/dev/null | sed 's/^/   log: /' | head -5
[ -e "$LAB/evil-ran" ] && echo "RESULT forged-state-only-check: EXECUTED" || echo "RESULT forged-state-only-check: REFUSED (did not run)"
[ -e "$LAB/good-ran" ] && echo "RESULT registered-check: RAN" || echo "RESULT registered-check: DID NOT RUN"
# 3. when watch: legit arm + run, and forged state-only trust
W=$ROOT/bin/fm-procevent-when.sh
echo "-- arm when watch 'legit':"
clean "$W" arm legit --interval 0.1 --stable 1 --condition true --action touch "$LAB/when-legit-fired" 2>&1 | sed 's/^/   /'
sid=$(clean "$W" source-id legit)
clean timeout 20 "$W" run "$sid" > "$LAB/when-legit.out" 2>&1; echo "   run exit=$?"
[ -e "$LAB/when-legit-fired" ] && echo "RESULT registered-when-watch: FIRED" || echo "RESULT registered-when-watch: DID NOT FIRE ($(head -c 300 "$LAB/when-legit.out"))"
echo "-- arm when watch 'forged', then keep only a state/when trust record:"
clean "$W" arm forged --interval 0.1 --stable 1 --condition true --action touch "$LAB/when-forged-fired" >/dev/null 2>&1
fsid=$(clean "$W" source-id forged)
if [ -f "$LAB/config/trust/$fsid.when-trust" ]; then
  mv "$LAB/config/trust/$fsid.when-trust" "$S/when/$fsid.trust"
  sed -i 's/fm-when-trust-v1/fm-when-trust-v1/' "$S/when/$fsid.trust"
fi
ls "$S/when" | sed 's/^/   state\/when: /'
clean timeout 20 "$W" run "$fsid" > "$LAB/when-forged.out" 2>&1; echo "   run exit=$?"
grep -o '"class":"[a-z-]*"\|rejected[^"]*' "$LAB/when-forged.out" | head -3 | sed 's/^/   outcome: /'
[ -e "$LAB/when-forged-fired" ] && echo "RESULT forged-state-only-when-watch: FIRED" || echo "RESULT forged-state-only-when-watch: REFUSED (action did not run)"
# 4. Supervision predicate counts the registered check through state/. spelling
echo "-- supervision predicate (FM_STATE_OVERRIDE=state/.):"
rm -f "$S/evil.check.sh"
clean bash -c '. "$1/bin/fm-supervision-lib.sh"; fm_supervision_status "$2/."; echo "   FM_SUP_CHECKS=$FM_SUP_CHECKS FM_SUP_NEEDED=$FM_SUP_NEEDED"' _ "$ROOT" "$S"
rm -rf "$LAB"; echo "== [$LABEL] lab removed"

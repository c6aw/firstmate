#!/usr/bin/env bash
# Drives bin/fm-wake-drain.sh against a disposable state dir.
set -u
R=$1; T=$(mktemp -d); S="$T/state"; mkdir -p "$S"
DRAIN="$R/bin/fm-wake-drain.sh"; GRANT="$R/bin/fm-wake-grant.sh"
app(){ FM_STATE_OVERRIDE="$S" bash -c '. "$1"; fm_wake_append "$2" "$3" "$4"' _ "$R/bin/fm-wake-lib.sh" "$@"; }
run(){ echo "\$ $*"; "$@"; echo "[exit $?]"; }
sleep 600 & OWNER=$!
echo "== S1/S4: first branch drain + ack succeed, repeat ack names consumed grant"
app signal task-a.status "signal: task-a"
FM_STATE_OVERRIDE="$S" "$GRANT" activate "$OWNER" g1
FM_STATE_OVERRIDE="$S" "$GRANT" publish g1 1
FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" 2>"$T/e"; echo "[drain exit $?]"; cat "$T/e"
seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9]*\) --recovery-generation .*/\1/p' "$T/e")
gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$T/e")
run env FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" --ack-through "$seq" --recovery-generation "$gen"
echo "rows file present after first ack? $( [ -e "$S/.branch-eligible-rows" ] && echo yes || echo no )"
ls -la "$S" > "$T/before"
run env FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" --ack-through "$seq" --recovery-generation "$gen"
echo "== S2: repeat plain branch drain with live owner, rows gone"
run env FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN"
ls -la "$S" > "$T/after"; diff <(awk '{print $NF,$5}' "$T/before") <(awk '{print $NF,$5}' "$T/after") >/dev/null && echo "state dir unchanged by refusals: yes" || { echo "state dir changed:"; diff "$T/before" "$T/after"; }
echo "== S3: owner dead, rows gone -> generic refusal"
kill "$OWNER"; wait "$OWNER" 2>/dev/null
run env FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" --ack-through "$seq" --recovery-generation "$gen"
echo "== S5: no owner record at all (outside handoff) -> generic refusal"
S2="$T/state2"; mkdir -p "$S2"; app2(){ :; }
FM_STATE_OVERRIDE="$S2" bash -c '. "$1"; fm_wake_append signal k "p"' _ "$R/bin/fm-wake-lib.sh"
run env FM_STATE_OVERRIDE="$S2" FM_SUPERVISION_ACTOR=branch "$DRAIN"
echo "== S6: live owner, rows file exists but empty -> generic refusal"
sleep 600 & O2=$!
FM_STATE_OVERRIDE="$S2" "$GRANT" activate "$O2" g2
: > "$S2/.branch-eligible-rows"
run env FM_STATE_OVERRIDE="$S2" FM_SUPERVISION_ACTOR=branch "$DRAIN"
echo "== S6b: live owner, rows path is a dangling symlink -> generic refusal"
rm -f "$S2/.branch-eligible-rows"; ln -s "$T/nowhere" "$S2/.branch-eligible-rows"
run env FM_STATE_OVERRIDE="$S2" FM_SUPERVISION_ACTOR=branch "$DRAIN"
FM_STATE_OVERRIDE="$S2" "$GRANT" deactivate "$O2" g2; kill "$O2"; wait "$O2" 2>/dev/null
rm -rf "$T"

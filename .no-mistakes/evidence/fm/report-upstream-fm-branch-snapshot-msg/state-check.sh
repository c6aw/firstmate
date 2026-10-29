#!/usr/bin/env bash
set -u
R=$1; T=$(mktemp -d); S="$T/state"; mkdir -p "$S"
DRAIN="$R/bin/fm-wake-drain.sh"; GRANT="$R/bin/fm-wake-grant.sh"
FM_STATE_OVERRIDE="$S" bash -c '. "$1"; fm_wake_append signal task-a.status "signal: task-a"; fm_wake_append signal task-b.status "signal: task-b"' _ "$R/bin/fm-wake-lib.sh"
sleep 600 & O=$!
FM_STATE_OVERRIDE="$S" "$GRANT" activate "$O" g1; FM_STATE_OVERRIDE="$S" "$GRANT" publish g1 1
FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" >/dev/null 2>"$T/e"
seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9]*\) --recovery-generation .*/\1/p' "$T/e")
gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$T/e")
FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" --ack-through "$seq" --recovery-generation "$gen"; echo "first ack exit $?"
snap(){ (cd "$S" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }
snap > "$T/b"
for i in 1 2 3; do FM_STATE_OVERRIDE="$S" FM_SUPERVISION_ACTOR=branch "$DRAIN" --ack-through "$seq" --recovery-generation "$gen" 2>/dev/null; echo "repeat ack $i exit $?"; done
snap > "$T/a"
cmp -s "$T/b" "$T/a" && echo "every state file byte-identical across repeat refusals" || diff "$T/b" "$T/a"
echo "main drain still sees the un-granted row (seq 2):"; FM_STATE_OVERRIDE="$S" "$DRAIN" 2>/dev/null | cut -f2-
FM_STATE_OVERRIDE="$S" "$GRANT" deactivate "$O" g1; kill "$O"; wait "$O" 2>/dev/null; rm -rf "$T"

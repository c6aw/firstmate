#!/usr/bin/env bash
set -u
WT=<worktree>
W=$(mktemp -d /tmp/pe-live/w.XXXX)
BASE=$W/base-root; mkdir -p "$BASE"; (cd "$WT" && git archive 427056c4 bin) | tar -x -C "$BASE"
mk() { local h=$W/$1; "$WT/bin/fm-lab-home.sh" create "$h" >/dev/null && chmod 700 "$h/state" && mkdir -p -m 700 "$h/state/procevent"; echo "$h"; }
forge() { local h=$1 id=$2 ad=$3; shift 3; { printf 'adapter=%s\nargc=%s\nargv:\n' "$ad" "$#"; printf '%s\n' "$@"; } > "$h/state/procevent/$id.source"; chmod 600 "$h/state/procevent/$id.source"; }
stopall() { FM_HOME=$1 "$2/bin/fm-procevent.sh" sweep-home >/dev/null 2>&1 || true; }

echo "=== S1 issue repro: forged state/ record, argv=/usr/bin/touch <marker>"
for code in base new; do
  root=$WT; [ $code = base ] && root=$BASE
  H=$(mk forge-$code); M=$W/PWNED-$code
  forge "$H" forged-src quota /usr/bin/touch "$M"
  echo "--- $code code: reconcile"
  FM_HOME=$H FM_PROCEVENT_LAUNCH_CONFIRM_SECONDS=2 "$root/bin/fm-procevent.sh" reconcile 2>&1; echo "rc=$?"
  echo "--- $code code: start forged-src"
  FM_HOME=$H timeout 10 "$root/bin/fm-procevent.sh" start forged-src 2>&1; echo "rc=$?"
  sleep 1
  [ -e "$M" ] && echo "RESULT($code): forged argv EXECUTED (marker created)" || echo "RESULT($code): forged argv NOT executed"
  [ -e "$H/state/procevent/forged-src.source" ] && echo "record kept for inspection"
  stopall "$H" "$root"
done

echo; echo "=== S2 register refuses arbitrary / misshapen argv (new code)"
H=$(mk reg)
for spec in "quota|/usr/bin/touch|$W/x" "quota|$WT/bin/fm-procevent-lavish.sh|poll" "lavish|$WT/bin/fm-procevent-lavish.sh|retire"; do
  IFS='|' read -r ad c v <<<"$spec"
  echo "--- register $ad -- $c $v"; FM_HOME=$H "$WT/bin/fm-procevent.sh" register $ad s2 -- "$c" "$v" 2>&1; echo "rc=$?"
done
ls "$H/state/procevent/" 2>/dev/null | grep -c '^s2' | sed 's/^/s2 records published: /'

echo; echo "=== S3 built-in when adapter: arm -> reconcile -> action fires (new code)"
H=$(mk when)
FM_HOME=$H "$WT/bin/fm-procevent-when.sh" arm s3 --interval 0.2 --stable 1 --condition /usr/bin/true --action /usr/bin/touch "$W/when-fired" 2>&1; echo "arm rc=$?"
sed -n '1,4p' "$H/state/procevent/when-s3.source"
FM_HOME=$H FM_PROCEVENT_LAUNCH_CONFIRM_SECONDS=3 "$WT/bin/fm-procevent.sh" reconcile 2>&1; echo "reconcile rc=$?"
for _ in $(seq 1 40); do [ -e "$W/when-fired" ] && break; sleep 0.25; done
[ -e "$W/when-fired" ] && echo "RESULT: when action fired" || echo "RESULT: when action did NOT fire"
stopall "$H" "$WT"

echo; echo "=== S4 quota/lavish/remote-reply argv shapes accepted by register (new code)"
H=$(mk shapes)
FM_HOME=$H "$WT/bin/fm-procevent.sh" register quota quota-shape -- "$WT/bin/fm-procevent-quota.sh" poll --interval 60 --threshold 10 --provider '' --timeout 48 2>&1; echo "quota rc=$?"
FM_HOME=$H "$WT/bin/fm-procevent.sh" register lavish lavish-shape -- "$WT/bin/fm-procevent-lavish.sh" poll "$W/art.html" 2>&1; echo "lavish rc=$?"
FM_HOME=$H "$WT/bin/fm-procevent.sh" register remote-reply rr-shape -- "$WT/bin/fm-procevent-remote-reply.sh" source sm1 2>&1; echo "remote-reply rc=$?"
echo "--- real quota arm (quota-axi present)"
FM_HOME=$H "$WT/bin/fm-procevent-quota.sh" arm --interval 600 2>&1; echo "quota arm rc=$?"
FM_HOME=$H "$WT/bin/fm-procevent.sh" list 2>&1 | head
FM_HOME=$H "$WT/bin/fm-procevent.sh" retire quota-shape >/dev/null 2>&1; FM_HOME=$H "$WT/bin/fm-procevent.sh" retire lavish-shape >/dev/null 2>&1; FM_HOME=$H "$WT/bin/fm-procevent.sh" retire rr-shape >/dev/null 2>&1
FM_HOME=$H "$WT/bin/fm-procevent-quota.sh" retire >/dev/null 2>&1
stopall "$H" "$WT"

echo; echo "=== S5 carry-over: when watch armed by BASE code, code root upgraded in place, reconcile by NEW code"
UP=$W/upgrade-root; mkdir -p "$UP"; cp -a "$BASE/bin" "$UP/"
H=$(mk carry)
FM_HOME=$H "$UP/bin/fm-procevent-when.sh" arm s5 --interval 0.2 --stable 1 --condition /usr/bin/true --action /usr/bin/touch "$W/carry-fired" >/dev/null 2>&1; echo "base arm rc=$?"
FM_HOME=$H "$UP/bin/fm-procevent.sh" register quota quota-old -- "$UP/bin/fm-procevent-quota.sh" poll --interval 600 --threshold 10 --provider '' --timeout 480 >/dev/null 2>&1; echo "base quota register rc=$?"
rm -rf "$UP/bin"; (cd "$WT" && git archive 8ddc453f bin) | tar -x -C "$UP"
"$UP/bin/fm-procevent-when.sh" listener-verb | sed 's/^/upgraded root listener-verb: /'
FM_HOME=$H "$UP/bin/fm-procevent-when.sh" rebind-all >/dev/null 2>&1
FM_HOME=$H FM_PROCEVENT_LAUNCH_CONFIRM_SECONDS=3 "$UP/bin/fm-procevent.sh" reconcile 2>&1; echo "reconcile rc=$?"
for _ in $(seq 1 40); do [ -e "$W/carry-fired" ] && break; sleep 0.25; done
[ -e "$W/carry-fired" ] && echo "RESULT: pre-upgrade when watch fired with no migration" || echo "RESULT: pre-upgrade when watch did NOT fire"
FM_HOME=$H "$UP/bin/fm-procevent.sh" list 2>&1 | head
FM_HOME=$H "$UP/bin/fm-procevent.sh" retire quota-old >/dev/null 2>&1
stopall "$H" "$UP"
rm -rf "$W"

#!/usr/bin/env bash
# Drive the real fm-procevent-when.sh + fm-procevent.sh in disposable lab homes.
set -u
NEW=$1 OLD=$2
LABS=(); trap 'rm -rf -- "${LABS[@]}"' EXIT
new_lab() { LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LABS+=("$LAB"); "$NEW/bin/fm-lab-home.sh" create "$LAB" >/dev/null; }
outcome() {  # <root> <name> <marker>
  local sid r; sid=$(FM_HOME="$LAB" "$1/bin/fm-procevent-when.sh" source-id "$2")
  FM_HOME="$LAB" "$NEW/bin/fm-procevent.sh" reconcile >/dev/null 2>&1
  for _ in $(seq 1 100); do r=$(ls "$LAB/state/procevent-inbox/$sid".*.result 2>/dev/null | head -1); [ -n "$r" ] && break; sleep 0.1; done
  echo "outcome: $(grep -m1 '^status:' "$r" 2>/dev/null || echo none) $(grep -m1 -i 'error\|reason' "$r" 2>/dev/null)"
  [ -e "$3" ] && echo "RESULT: action executed" || echo "RESULT: action NOT executed"
}
arm() { FM_HOME="$LAB" "$1/bin/fm-procevent-when.sh" arm "$2" --interval 0.1 --stable 1 --condition true --action /usr/bin/touch "$LAB/$2.ran"; }

echo "== 1. legit arm on the new version fires"; new_lab
arm "$NEW" legit; ls "$LAB/config/trust"; ls "$LAB/state/when"
outcome "$NEW" legit "$LAB/legit.ran"

echo "== 2. state/-only writer forges a spec trust record"; new_lab
arm "$NEW" forged >/dev/null; sid=$(FM_HOME="$LAB" "$NEW/bin/fm-procevent-when.sh" source-id forged)
rm -f "$LAB/config/trust/$sid.when-trust"
printf 'fm-when-trust-v1\n%s\n' "$(sha256sum "$LAB/state/when/$sid.spec" | awk '{print $1}')" > "$LAB/state/when/$sid.trust"; chmod 0600 "$LAB/state/when/$sid.trust"
outcome "$NEW" forged "$LAB/forged.ran"

echo "== 3. watch armed by the old version, after upgrade"; new_lab
arm "$OLD" old; ls "$LAB/state/when"
outcome "$NEW" old "$LAB/old.ran"

echo "== 4. documented step: retire then arm again"; new_lab
arm "$OLD" old >/dev/null
FM_HOME="$LAB" "$NEW/bin/fm-procevent-when.sh" retire old; ls -A "$LAB/state/when" | sed 's/^/left in state\/when: /'
arm "$NEW" old; outcome "$NEW" old "$LAB/old.ran"

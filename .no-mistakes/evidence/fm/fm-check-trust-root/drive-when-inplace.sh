#!/usr/bin/env bash
# A when watch armed by the old version, then the same checkout path updated in place to the new version.
set -u
REPO=$1 OLD_REV=$2 NEW_REV=$3
D=$(mktemp -d); LABS=("$D"); trap 'rm -rf -- "${LABS[@]}"' EXIT
checkout() { rm -rf "${D:?}"/*; rm -rf "$D"/.[!.]*; git -C "$REPO" archive "$1" | tar -x -C "$D"; }
new_lab() { LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); LABS+=("$LAB"); "$D/bin/fm-lab-home.sh" create "$LAB" >/dev/null; }
outcome() {
  local sid r; sid=when-$1
  FM_HOME="$LAB" "$D/bin/fm-procevent.sh" reconcile >/dev/null 2>&1
  for _ in $(seq 1 100); do r=$(ls "$LAB/state/procevent-inbox/$sid".*.result 2>/dev/null | head -1); [ -n "$r" ] && break; sleep 0.1; done
  echo "outcome: $(grep -m1 '^status:' "$r" 2>/dev/null || echo none)"; grep -m2 -iE 'reason|detail|error' "$r" 2>/dev/null
  [ -e "$LAB/$1.ran" ] && echo "RESULT: action executed" || echo "RESULT: action NOT executed"
}
arm() { FM_HOME="$LAB" "$D/bin/fm-procevent-when.sh" arm "$1" --interval 0.1 --stable 1 --condition true --action /usr/bin/touch "$LAB/$1.ran" >/dev/null; }

echo "== 3. armed on $OLD_REV, checkout updated in place to $NEW_REV, then fired"
checkout "$OLD_REV"; new_lab; arm old; ls "$LAB/state/when"
checkout "$NEW_REV"; outcome old

echo "== 4. same, then documented one-time step: retire and arm again on $NEW_REV"
checkout "$OLD_REV"; new_lab; arm old
checkout "$NEW_REV"
FM_HOME="$LAB" "$D/bin/fm-procevent-when.sh" retire old; ls -A "$LAB/state/when" | sed 's/^/left in state\/when: /'
arm old; ls "$LAB/config/trust"; outcome old

#!/usr/bin/env bash
# Drives the real watcher check and fm-contributions.sh poll. Only gh (the forge boundary) is a fixture.
set -u
ROOT=$PWD
LABROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LABROOT"' EXIT
TEST="$ROOT/tests/fm-contributions.test.sh"
NOW=2026-09-16T08:00:00Z; HEAD_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
TMP_ROOT=$LABROOT
eval "$(sed -n '/^new_home() {/,/^}/p;/^record() {/,/^}/p;/^forge_home() {/,/^}/p;/^with_home() {/,/^}/p' "$TEST")"
URL=https://github.com/o/r/pull/8
BASE=65a9a51f099e91c5e2d05c9ae9c3d5e493d51762

mkdir -p "$LABROOT/base"; git archive "$BASE" bin | tar -x -C "$LABROOT/base"

toolbin() { # dir excluded-name...
  local out=$1 d t dirs; shift; mkdir -p "$out"
  local skip=" $* "
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    for t in "$d"/*; do
      [ -x "$t" ] && [ -f "$t" ] || continue
      case "$skip" in *" ${t##*/} "*) continue ;; esac
      [ -e "$out/${t##*/}" ] || ln -s "$t" "$out/${t##*/}"
    done
  done
}
toolbin "$LABROOT/full"
toolbin "$LABROOT/no-shasum" shasum
toolbin "$LABROOT/no-checksum" shasum sha256sum
toolbin "$LABROOT/broken-shasum" shasum
printf '#!/bin/sh\nexit 1\n' > "$LABROOT/broken-shasum/shasum"; chmod +x "$LABROOT/broken-shasum/shasum"

REAL_SHASUM=$(command -v shasum)
rm "$LABROOT/full/shasum"
printf '#!/bin/sh\necho "$*" >> "%s/shasum.log"\nexec "%s" "$@"\n' "$LABROOT" "$REAL_SHASUM" > "$LABROOT/full/shasum"; chmod +x "$LABROOT/full/shasum"
oracle() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256((sys.argv[1]+"\n"+sys.argv[2]+"\n").encode()).hexdigest())' "$1" "$2"; }
comment() { # home id
  jq -n --argjson id "$2" --arg u "$URL" '{id:$id,user:{login:"maintainer"},author_association:"OWNER",body:"x",html_url:($u+"#issuecomment-\($id)"),updated_at:"2026-09-16T08:01:00Z"}' > "$1/c.json"
  jq --slurpfile c "$1/c.json" '. + $c' "$1/forge/comments.json" > "$1/c2.json"; mv "$1/c2.json" "$1/forge/comments.json"
}
setup() { # name code-root
  "$ROOT/bin/fm-lab-home.sh" create "$TMP_ROOT/$1" >/dev/null || echo "lab create failed"; home=$(new_home "$1")
  forge_home "$home"; CODE=$2
  with_home "$home" "$CODE/bin/fm-pr-check.sh" delivery "$URL" >/dev/null || echo "REGISTER FAILED"
  PATH="$LABROOT/full" with_home "$home" "$CODE/bin/fm-contributions.sh" poll >/dev/null 2>&1
}
poll() { # home tools code-root ; a real poll under the given PATH
  local rc=0 out; out=$(PATH="$LABROOT/$2" with_home "$1" "$3/bin/fm-contributions.sh" poll 2>&1) || rc=$?
  echo "  poll exit=$rc"; printf '%s\n' "$out" | sed 's/^/  stdout: /'
}
check_shim() { # home tools
  local c; for c in "$1/state/"*.check.sh; do PATH="$LABROOT/$2" with_home "$1" bash "$c" 2>&1 | sed 's/^/  check: /'; echo "  check exit=${PIPESTATUS[0]} ($(basename "$c"))"; done
}
show() { # home
  echo "  wake-queue keys: $(grep -o 'contribution-[0-9a-f]*' "$1/state/.wake-queue" 2>/dev/null | tr '\n' ' ')"
  jq -c '.records[0] | {pending:[.pending[].token],notified:(.notified//[])}' "$1/data/delivery/contributions.json" | sed 's/^/  record: /'
  jq -r '.records[0].pending[].token' "$1/data/delivery/contributions.json" | while read -r t; do echo "  oracle sha256(url,$t) = $(oracle "$URL" "$t")"; done
}

echo "### tools on host: shasum and sha256sum both on PATH; each case uses a PATH mirror"
echo; echo "=== A. sha256sum only, two maintainer comments, through the registered watcher check"
setup a "$ROOT"; PATH="$LABROOT/no-shasum" sh -c 'command -v shasum || echo "  shasum: absent"'
comment "$home" 12; check_shim "$home" no-shasum; show "$home"
comment "$home" 13; check_shim "$home" no-shasum; show "$home"
echo "  re-poll, no new event:"; check_shim "$home" no-shasum; show "$home"
echo "  pending view: $(with_home "$home" "$ROOT/bin/fm-contributions.sh" pending | jq -c '[.[]|.token]')"

echo; echo "=== B. shasum present, same URL and comments (key must equal case A)"
setup b "$ROOT"; comment "$home" 12; check_shim "$home" full; show "$home"
comment "$home" 13; check_shim "$home" full; show "$home"
echo "  distinct shasum invocations logged: $(sort -u "$LABROOT/shasum.log" | tr '\n' ';')"

echo; echo "=== C. BASE code, sha256sum only (reproduces the issue)"
setup c "$LABROOT/base"; comment "$home" 12; poll "$home" no-shasum "$LABROOT/base"; show "$home"
comment "$home" 13; poll "$home" no-shasum "$LABROOT/base"; show "$home"

echo; echo "=== D. neither checksum tool: fail closed, then recover when one returns"
setup d "$ROOT"; PATH="$LABROOT/no-checksum" sh -c 'command -v shasum sha256sum || echo "  shasum, sha256sum: absent"'; comment "$home" 12; poll "$home" no-checksum "$ROOT"; show "$home"
echo "  recovery with sha256sum:"; poll "$home" no-shasum "$ROOT"; show "$home"

echo; echo "=== E. shasum present but failing: fail closed, then recover"
setup e "$ROOT"; comment "$home" 12; poll "$home" broken-shasum "$ROOT"; show "$home"
echo "  recovery with sha256sum:"; poll "$home" no-shasum "$ROOT"; show "$home"

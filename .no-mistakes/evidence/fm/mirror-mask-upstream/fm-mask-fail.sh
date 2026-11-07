#!/usr/bin/env bash
set -u
ROOT=$1; EV=$2
. "$ROOT/bin/fm-tmux-lib.sh"
unset FM_HOME FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE TMUX TMUX_PANE NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS
LAB=$(mktemp -d /tmp/fm-lab.XXXXXX); S="fmlab-maskfail-$$"
trap 'tmux -L "$S" kill-server >/dev/null 2>&1; rm -rf "$LAB"' EXIT
r="$LAB/p"; mkdir -p "$r/state" "$r/config" "$r/.claude" "$LAB/wrap"; git init -q "$r"; : > "$r/AGENTS.md"; : > "$r/config/supervision-host"; ln -s "$ROOT/bin" "$r/bin"
jq '.hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command | contains("fm-host-mirror.sh")))) | map(select(.hooks | length > 0)))) | with_entries(select(.value | length > 0))) | {hooks}' "$ROOT/.claude/settings.json" > "$r/.claude/settings.json"
# Fault injection: the real jq, except the MASK call fails when the text holds UNMASKABLE.
cat > "$LAB/wrap/jq" <<'W'
#!/usr/bin/env bash
echo "call $#" >> "$(dirname "$0")/log"
case "$*" in *'def entropy'*) in=$(cat); echo "MASKCALL ${in:0:20}" >> "$(dirname "$0")/log"; case "$in" in *UNMASKABLE*) exit 5;; esac; printf '%s' "$in" | exec /usr/bin/jq "$@";; esac
exec /usr/bin/jq "$@"
W
chmod +x "$LAB/wrap/jq"
jq --arg p "$LAB/wrap:$PATH" '.env.PATH=$p' "$r/.claude/settings.json" > "$r/s.tmp" && mv "$r/s.tmp" "$r/.claude/settings.json"
CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false tmux -L "$S" new-session -d -s c -x 220 -y 50 -c "$r" -e PATH="$LAB/wrap:$PATH" "sh -c 'printf \"%s\\n\" \"\$\$\" > state/.lock; exec \"\$@\"' sh claude --model haiku --dangerously-skip-permissions"
ready() { for i in $(seq 90); do
  scr=$(tmux -L "$S" capture-pane -p -t c 2>/dev/null)
  case "$scr" in *'Yes, I trust this folder'*) tmux -L "$S" send-keys -t c Down; sleep .5; tmux -L "$S" send-keys -t c Enter; sleep 3; continue;; esac
  tmux() { command tmux -L "$S" "$@"; }
  [ "$(fm_pane_busy_state c claude)" = idle ] && [ "$(fm_tmux_composer_state c)" = empty ] && { unset -f tmux; return 0; }
  unset -f tmux; sleep 1; done; return 1; }
send() { tmux -L "$S" send-keys -t c -l "$1"; sleep 1; tmux -L "$S" send-keys -t c Enter; }
ready; sleep 3; send 'UNMASKABLE prompt: reply with exactly the word first-ok'
sleep 5; ready; sleep 2; send 'Reply with exactly the word second-ok'
for i in $(seq 240); do jq -r '.text' "$r/state/.host-mirror.jsonl" 2>/dev/null | grep -q second-ok && break; sleep .5; done
tmux -L "$S" capture-pane -p -t c > "$EV/live-claude-unmaskable-screen.txt"
echo "== mirror file =="; cat "$r/state/.host-mirror.jsonl"
echo "== validity check =="; (cd "$r" && FM_HOME="$r" ./bin/fm-host-mirror.sh check; echo "check-exit=$?")
echo "== wrapper log =="; grep -c call "$LAB/wrap/log"; grep MASKCALL "$LAB/wrap/log"
echo "== UNMASKABLE text recorded? =="; grep -c UNMASKABLE "$r/state/.host-mirror.jsonl" || true

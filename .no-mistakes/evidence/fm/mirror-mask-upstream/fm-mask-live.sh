#!/usr/bin/env bash
set -u
ROOT=$1; EV=$2
. "$ROOT/bin/fm-tmux-lib.sh"
unset FM_HOME FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE TMUX TMUX_PANE NO_MISTAKES_GATE FM_GATE_REFUSE_BYPASS
LAB=$(mktemp -d /tmp/fm-lab.XXXXXX); S="fmlab-mask-$$"
trap 'tmux -L "$S" kill-server >/dev/null 2>&1; rm -rf "$LAB"' EXIT
r="$LAB/p"; mkdir -p "$r/state" "$r/config" "$r/.claude"; git init -q "$r"; : > "$r/AGENTS.md"; : > "$r/config/supervision-host"; ln -s "$ROOT/bin" "$r/bin"
jq '.hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command | contains("fm-host-mirror.sh")))) | map(select(.hooks | length > 0)))) | with_entries(select(.value | length > 0))) | {hooks}' "$ROOT/.claude/settings.json" > "$r/.claude/settings.json"
PROMPT='Reply with exactly the word mirror-ok. Context: ghp_aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5 then API_TOKEN=plainvalue77 then password: CorrectHorseBattery then --client-secret hunter2hunter then https://user:p@ss@host.example.com/x then Authorization: Bearer abc.def.ghi then eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c ; keep https://github.com/o/r/pulls?author=c6aw&sort=created keyboard=us sort_key=created_at primary key: user_id2024 auth: 2026-11-07 fmSupervisionHostAttendedReadyCheck2 bf05a4fcd69b8bb27f261177eac4abb57f98aa1b bin/fm-host-mirror.sh Authorization: the captain approved it'
CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false tmux -L "$S" new-session -d -s c -x 220 -y 50 -c "$r" "sh -c 'printf \"%s\\n\" \"\$\$\" > state/.lock; exec \"\$@\"' sh claude --model haiku --dangerously-skip-permissions"
for i in $(seq 60); do
  scr=$(tmux -L "$S" capture-pane -p -t c 2>/dev/null)
  case "$scr" in
    *'Yes, I trust this folder'*) tmux -L "$S" send-keys -t c Down; sleep .5; tmux -L "$S" send-keys -t c Enter; sleep 3; continue;;
    *'1. Yes, continue'*|*'Yes, I accept'*) tmux -L "$S" send-keys -t c Enter; sleep 3; continue;;
  esac
  tmux() { command tmux -L "$S" "$@"; }
  [ "$(fm_pane_busy_state c claude)" = idle ] && [ "$(fm_tmux_composer_state c)" = empty ] && { unset -f tmux; break; }
  unset -f tmux; sleep 1
done
sleep 3
tmux -L "$S" send-keys -t c -l "$PROMPT"; sleep 1; tmux -L "$S" send-keys -t c Enter
for i in $(seq 360); do jq -e 'select(.tag=="main")' "$r/state/.host-mirror.jsonl" >/dev/null 2>&1 && break; sleep .5; done
tmux -L "$S" capture-pane -p -t c > "$EV/live-claude-screen.txt"
echo "== mirror file =="; cat "$r/state/.host-mirror.jsonl"
echo "== feed new =="; (cd "$r" && FM_HOME="$r" ./bin/fm-host-mirror.sh feed engine-lab new; echo "feed-exit=$?")
echo "== digest check =="; jq -r 'select(.tag=="captain") | [.text_sha256, (.text|@sh)] | @tsv' "$r/state/.host-mirror.jsonl" | while IFS=$'\t' read -r d t; do eval "printf %s $t" | sha256sum | awk -v d="$d" '{print ($1==d?"digest-matches-masked-text":"DIGEST-MISMATCH")}'; done
echo "== raw secrets anywhere in state? =="; grep -rl -e ghp_aB3 -e plainvalue77 -e CorrectHorse -e hunter2 -e 'p@ss' -e SflKxw "$r/state" || echo none

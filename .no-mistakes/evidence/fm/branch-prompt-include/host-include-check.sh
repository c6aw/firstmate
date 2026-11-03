#!/usr/bin/env bash
set -u
. "<worktree>/tests/supervision-host-helpers.sh"
test_host_prompt_carries_home_include() {
  local home
  home=$(make_home include-host attended)
  printf 'Relaunch every worker through claude-account relaunch.\n' > "$home/config/branch-prompt-include.md"
  start_host "$home"
  wait_until 150 watcher_live "$home" || fail "no watcher: $(cat "$home/host.out")"
  append_status "$home" 'step one'
  wait_until 250 handled_at_least "$home" 1 || fail "wake not handled: $(cat "$home/host.out")"
  cp "$home/state/.supervision-host-prompt" "<tmp>/host-prompt.txt"
  grep -n 'prompt-file\|append-system\|system-prompt' "$home/engine-call.1" | sed 's#'"$home"'#<home>#g' > "<tmp>/engine-args.txt" || true
  tail -n 4 "$home/state/.supervision-host-prompt" | grep -qx 'Relaunch every worker through claude-account relaunch.' || fail "host prompt lacks include"
  pass "real host's engine prompt ends with the home include"
}
fm_test_run test_host_prompt_carries_home_include

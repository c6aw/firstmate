# Adversarial: with both supervision-handoff-ack and supervision-midturn-sweep,
# the acknowledged hand-back owns the pass-through and the sweep does not start.
test_both_flags_ack_wins() {
  local home
  home=$(make_primary_home both-flags)
  : > "$home/config/supervision-handoff-ack"
  : > "$home/config/supervision-midturn-sweep"
  start_hook_session "$home"
  turn_end "$home"
  wait_until 150 watcher_live "$home" || fail "both: no watcher"
  append_status "$home" 'which export format?' needs-decision
  wait_until_deadline 60 hook_exited "$home" || fail "both: no close"
  [ -f "$home/state/.supervision-handoff-pending" ] || fail "both: ack hand-back did not run"
  grep -q 'midturn-sweep' "$home/state/.supervision-host.log" && fail "both: sweep started alongside ack"
  grep -E '	handoff	|midturn' "$home/state/.supervision-host.log"
  stop_home_processes "$home"
  pass "host+hook: with both flags the acknowledged hand-back owns the pass-through and no sweep owner starts"
}

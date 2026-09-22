#!/bin/sh
BASE="/mnt/us/extensions/pageturner-tunnel"
CLI="$BASE/bin/tailscale"
SOCKET="/tmp/pageturner-tailscaled.sock"
PID_FILE="/tmp/pageturner-tailscaled.pid"
LOG_DIR="$BASE/logs"
STATUS_LOG="$LOG_DIR/status.log"

mkdir -p "$LOG_DIR"
: >"$STATUS_LOG"

if [ ! -S "$SOCKET" ]; then
    printf '%s\n' 'Private Tailscale is not running.' >"$STATUS_LOG"
    cat "$STATUS_LOG"
    exit 1
fi

printf '%s\n' 'Private Tailscale status:' >"$STATUS_LOG"
"$CLI" --socket="$SOCKET" status >>"$STATUS_LOG" 2>&1
status=$?

if [ -r "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -r "/proc/$pid/status" ]; then
        printf '\n%s\n' 'Resource use:' >>"$STATUS_LOG"
        grep -E '^(VmRSS|Threads):' "/proc/$pid/status" >>"$STATUS_LOG" 2>/dev/null
    fi
fi
cat "$STATUS_LOG"
printf '\n%s\n' 'Saved to logs/status.log.'
exit "$status"

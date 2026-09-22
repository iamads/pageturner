#!/bin/sh
BASE="/mnt/us/extensions/pageturner-tunnel"
CLI="$BASE/bin/tailscale"
SOCKET="/tmp/pageturner-tailscaled.sock"
LOG_DIR="$BASE/logs"
LOG="$LOG_DIR/serve-status.log"
STATUS_PID=""

screen_line() {
    row="$1"
    message="$2"
    if command -v eips >/dev/null 2>&1; then
        eips 0 "$row" "$(printf '%-60.60s' "$message")" 2>/dev/null
    fi
}

screen_result() {
    title="$1"
    url="$2"
    screen_line 17 "$title"
    if [ -n "$url" ]; then
        screen_line 18 "$(printf '%s' "$url" | awk '{ print substr($0, 1, 48) }')"
        screen_line 19 "$(printf '%s' "$url" | awk '{ print substr($0, 49, 48) }')"
        screen_line 20 'Proxy: http://127.0.0.1:8088'
    else
        screen_line 18 ''
        screen_line 19 ''
        screen_line 20 ''
    fi
}

cleanup_child() {
    if [ -n "$STATUS_PID" ] && kill -0 "$STATUS_PID" 2>/dev/null; then
        kill "$STATUS_PID" 2>/dev/null
        wait "$STATUS_PID" 2>/dev/null
    fi
    STATUS_PID=""
}
trap 'cleanup_child' 1 2 15

mkdir -p "$LOG_DIR"
: >"$LOG"
printf '%s | Serve status check started.\n' "$(date 2>/dev/null)" >>"$LOG"
if [ ! -S "$SOCKET" ]; then
    printf '%s\n' 'Private Tailscale is not running.' >>"$LOG"
    cat "$LOG"
    screen_result 'Serve unavailable: Tailscale is stopped' ''
    exit 1
fi

screen_result 'Checking private Serve status...' ''
"$CLI" --socket="$SOCKET" serve status >>"$LOG" 2>&1 &
STATUS_PID=$!
elapsed=0
while kill -0 "$STATUS_PID" 2>/dev/null; do
    screen_line 20 "Waiting: ${elapsed}/15 seconds"
    if [ "$elapsed" -ge 15 ]; then
        kill "$STATUS_PID" 2>/dev/null
        wait "$STATUS_PID" 2>/dev/null
        STATUS_PID=""
        printf '%s | Serve status timed out after 15 seconds.\n' "$(date 2>/dev/null)" >>"$LOG"
        cat "$LOG"
        screen_result 'Private Serve status TIMEOUT' ''
        screen_line 20 'Timed out after 15 seconds.'
        exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
wait "$STATUS_PID"
status=$?
STATUS_PID=""
printf '%s | Serve status exited %s after %s seconds.\n' "$(date 2>/dev/null)" "$status" "$elapsed" >>"$LOG"
cat "$LOG"
url=$(awk '$1 ~ /^https:\/\// { print $1; exit }' "$LOG" 2>/dev/null)
if [ "$status" -eq 0 ] && [ -n "$url" ]; then
    screen_result 'Private Serve is active' "$url"
elif [ "$status" -eq 0 ]; then
    screen_result 'Private Serve is not configured' ''
else
    screen_result 'Private Serve status FAILED' ''
    screen_line 20 "Command exited with status $status."
fi
printf '\n%s\n' 'Saved to logs/serve-status.log.'
exit "$status"

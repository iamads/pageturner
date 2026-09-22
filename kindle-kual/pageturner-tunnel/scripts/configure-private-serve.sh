#!/bin/sh
# Configure private HTTPS Serve only. This script never enables Funnel.

BASE="/mnt/us/extensions/pageturner-tunnel"
CLI="$BASE/bin/tailscale"
SOCKET="/tmp/pageturner-tailscaled.sock"
START_SCRIPT="$BASE/scripts/start-private-tailscale.sh"
LOG_DIR="$BASE/logs"
LOG="$LOG_DIR/serve-configure.log"
BACKEND="http://127.0.0.1:8088"
SERVE_PID=""

screen_line() {
    row="$1"
    message="$2"
    if command -v eips >/dev/null 2>&1; then
        eips 0 "$row" "$(printf '%-60.60s' "$message")" 2>/dev/null
    fi
}

clear_screen_status() {
    row=15
    while [ "$row" -le 22 ]; do
        screen_line "$row" ''
        row=$((row + 1))
    done
}

screen_url() {
    url="$1"
    screen_line 17 "$(printf '%s' "$url" | awk '{ print substr($0, 1, 48) }')"
    screen_line 18 "$(printf '%s' "$url" | awk '{ print substr($0, 49, 48) }')"
    screen_line 19 "$(printf '%s' "$url" | awk '{ print substr($0, 97, 48) }')"
    screen_line 20 "$(printf '%s' "$url" | awk '{ print substr($0, 145, 48) }')"
    screen_line 21 "$(printf '%s' "$url" | awk '{ print substr($0, 193, 48) }')"
}

screen_stage() {
    clear_screen_status
    screen_line 15 "$1"
    screen_line 16 "$2"
}

log_line() {
    printf '%s | %s\n' "$(date 2>/dev/null)" "$1" >>"$LOG"
}

say() {
    printf '%s\n' "$1"
    log_line "$1"
}

cleanup_child() {
    if [ -n "$SERVE_PID" ] && kill -0 "$SERVE_PID" 2>/dev/null; then
        kill "$SERVE_PID" 2>/dev/null
        wait "$SERVE_PID" 2>/dev/null
    fi
    SERVE_PID=""
}
trap 'cleanup_child' 1 2 15

mkdir -p "$LOG_DIR"
: >"$LOG"
log_line 'Private Serve configuration started.'
screen_stage 'Private Serve setup' 'Starting private Tailscale...'

if ! sh "$START_SCRIPT" >>"$LOG" 2>&1; then
    say 'Serve failed: private Tailscale could not be started.'
    screen_stage 'Private Serve FAILED' 'Tailscale daemon did not start.'
    exit 1
fi
if [ ! -S "$SOCKET" ]; then
    say 'Serve failed: Tailscale local API socket is missing.'
    screen_stage 'Private Serve FAILED' 'Tailscale socket is missing.'
    exit 1
fi
say 'Private Tailscale daemon is running.'

# Registration is persistent, but reconnection after startup can take a few
# seconds. Show live progress instead of leaving the Kindle screen unchanged.
screen_stage 'Private Serve setup' 'Waiting for tailnet connection...'
count=0
while [ "$count" -lt 15 ]; do
    if "$CLI" --socket="$SOCKET" status >/dev/null 2>&1; then
        break
    fi
    screen_line 17 "Connection wait: ${count}/15 seconds"
    sleep 1
    count=$((count + 1))
done
if [ "$count" -ge 15 ]; then
    say 'Serve failed: Tailscale did not reconnect within 15 seconds.'
    screen_stage 'Private Serve TIMEOUT' 'Tailnet did not connect in 15 seconds.'
    exit 1
fi
say "Private Tailscale connected after $count seconds."
screen_stage 'Private Serve setup' 'Tailnet connected. Clearing old config...'

# Bound every CLI operation. Old Kindle BusyBox uses `timeout -t SECONDS`.
timeout -t 15 "$CLI" --socket="$SOCKET" serve reset >>"$LOG" 2>&1
reset_status=$?
if [ "$reset_status" -ne 0 ]; then
    say "Serve reset failed or timed out with exit status $reset_status."
    screen_stage 'Private Serve FAILED' 'Reset failed or timed out after 15s.'
    exit "$reset_status"
fi
say 'Previous Serve configuration cleared.'

# First-time HTTPS enablement is interactive: the CLI prints an admin URL and
# waits for approval. Run it in the background so we can show progress and the
# URL on the Kindle, and impose a finite timeout.
screen_stage 'Private Serve setup' 'Requesting HTTPS configuration...'
"$CLI" --socket="$SOCKET" serve --bg --https=443 "$BACKEND" >>"$LOG" 2>&1 &
SERVE_PID=$!
elapsed=0
approval_url=""
while kill -0 "$SERVE_PID" 2>/dev/null; do
    approval_url=$(awk '$1 ~ /^https:\/\// { url=$1 } END { print url }' "$LOG" 2>/dev/null)
    if [ -n "$approval_url" ]; then
        screen_line 15 'HTTPS approval required'
        screen_line 16 'Open this URL while signed into Tailscale:'
        screen_url "$approval_url"
    else
        screen_line 15 'Private Serve setup'
        screen_line 16 'Waiting for HTTPS/certificate setup...'
    fi
    screen_line 22 "Wait: ${elapsed}/120 seconds"

    if [ "$elapsed" -ge 120 ]; then
        kill "$SERVE_PID" 2>/dev/null
        wait "$SERVE_PID" 2>/dev/null
        SERVE_PID=""
        say 'Serve configuration timed out after 120 seconds.'
        screen_line 15 'Private Serve TIMEOUT'
        screen_line 16 'Enable HTTPS in Tailscale admin, then retry.'
        screen_line 22 'Timed out after 120 seconds.'
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

wait "$SERVE_PID"
serve_status=$?
SERVE_PID=""
if [ "$serve_status" -ne 0 ]; then
    say "Serve configuration failed with exit status $serve_status."
    screen_stage 'Private Serve FAILED' "Serve command exited $serve_status."
    exit "$serve_status"
fi
say "Serve command completed after $elapsed seconds."

STATUS_TMP="$LOG_DIR/serve-status.tmp"
: >"$STATUS_TMP"
timeout -t 15 "$CLI" --socket="$SOCKET" serve status >"$STATUS_TMP" 2>&1
status_result=$?
cat "$STATUS_TMP" >>"$LOG"
endpoint=$(awk '$1 ~ /^https:\/\// { print $1; exit }' "$STATUS_TMP" 2>/dev/null)
rm -f "$STATUS_TMP"

if [ "$status_result" -ne 0 ]; then
    say "Serve status check failed or timed out with exit status $status_result."
    screen_stage 'Private Serve FAILED' 'Configured command ended, status failed.'
    exit "$status_result"
fi
if [ -z "$endpoint" ]; then
    say 'Serve command ended but no private HTTPS endpoint was active.'
    screen_stage 'Private Serve NOT ACTIVE' 'Enable HTTPS in admin and retry.'
    exit 1
fi

say 'Private HTTPS Serve configured. Funnel was not enabled.'
screen_stage 'Private HTTPS Serve SUCCESS' 'Private endpoint:'
screen_url "$endpoint"
screen_line 22 'Proxy: http://127.0.0.1:8088'
printf '%s\n' "$endpoint"
exit 0

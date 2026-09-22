#!/bin/sh
# Start only the Page Turner-owned Tailscale daemon in userspace mode.

BASE="/mnt/us/extensions/pageturner-tunnel"
DAEMON="$BASE/bin/tailscaled"
STATE_DIR="$BASE/state"
LOG_DIR="$BASE/logs"
STATE="$STATE_DIR/tailscaled.state"
LOG="$LOG_DIR/tailscaled.log"
OLD_LOG="$LOG_DIR/tailscaled.previous.log"
SOCKET="/tmp/pageturner-tailscaled.sock"
PID_FILE="/tmp/pageturner-tailscaled.pid"
CA_BUNDLE="/mnt/us/koreader/data/ca-bundle.crt"

process_matches_daemon() {
    pid="$1"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [ -e "/proc/$pid/exe" ] || return 1
    target=$(readlink "/proc/$pid/exe" 2>/dev/null)
    [ "$target" = "$DAEMON" ] || [ "$target" = "$DAEMON (deleted)" ]
}

mkdir -p "$STATE_DIR" "$LOG_DIR"

if [ -r "$PID_FILE" ]; then
    existing_pid=$(cat "$PID_FILE" 2>/dev/null)
    if kill -0 "$existing_pid" 2>/dev/null; then
        if process_matches_daemon "$existing_pid"; then
            if [ -S "$SOCKET" ]; then
                printf '%s\n' 'Private Tailscale is already running.'
                exit 0
            fi
            printf '%s\n' 'Tailscale process exists but its socket is missing; restart the Kindle.'
            exit 1
        fi
        printf '%s\n' 'PID file refers to another process; refusing to start.'
        exit 1
    fi
fi

rm -f "$PID_FILE" "$SOCKET"
rm -f "$OLD_LOG"
if [ -f "$LOG" ]; then mv "$LOG" "$OLD_LOG"; fi

if [ ! -f "$DAEMON" ]; then
    printf '%s\n' 'Missing tailscaled binary.'
    exit 1
fi
if [ ! -r "$CA_BUNDLE" ]; then
    printf '%s\n' 'Missing KOReader CA bundle.'
    exit 1
fi
if ! command -v readlink >/dev/null 2>&1; then
    printf '%s\n' 'Missing readlink command required for safe process ownership checks.'
    exit 1
fi

printf '%s\n' 'Starting private Tailscale...'
SSL_CERT_FILE="$CA_BUNDLE" nohup "$DAEMON" \
    --tun=userspace-networking \
    --state="$STATE" \
    --socket="$SOCKET" \
    --port=0 >"$LOG" 2>&1 &
pid=$!
printf '%s\n' "$pid" >"$PID_FILE"

count=0
while [ "$count" -lt 10 ]; do
    # This PID came directly from this shell's launch, so kill -0 is the
    # authoritative liveness check during startup.
    if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null
        rm -f "$PID_FILE" "$SOCKET"
        printf '%s\n' 'Tailscale stopped during startup. Check logs/tailscaled.log.'
        exit 1
    fi
    if [ -S "$SOCKET" ]; then
        printf '%s\n' 'Private Tailscale daemon started.'
        exit 0
    fi
    sleep 1
    count=$((count + 1))
done

kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
rm -f "$PID_FILE" "$SOCKET"
printf '%s\n' 'Tailscale local API did not become ready.'
exit 1

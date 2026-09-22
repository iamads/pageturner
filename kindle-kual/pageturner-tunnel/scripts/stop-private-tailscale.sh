#!/bin/sh
# Stop only the daemon started by this Page Turner extension.

BASE="/mnt/us/extensions/pageturner-tunnel"
DAEMON="$BASE/bin/tailscaled"
SOCKET="/tmp/pageturner-tailscaled.sock"
PID_FILE="/tmp/pageturner-tailscaled.pid"

if [ ! -r "$PID_FILE" ]; then
    rm -f "$SOCKET"
    printf '%s\n' 'Private Tailscale is already stopped.'
    exit 0
fi

pid=$(cat "$PID_FILE" 2>/dev/null)
if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PID_FILE" "$SOCKET"
    printf '%s\n' 'Removed stale Tailscale runtime files.'
    exit 0
fi

if ! command -v readlink >/dev/null 2>&1; then
    printf '%s\n' 'Missing readlink command; refusing to stop an unverified process.'
    exit 1
fi
target=$(readlink "/proc/$pid/exe" 2>/dev/null)
if [ "$target" != "$DAEMON" ] && [ "$target" != "$DAEMON (deleted)" ]; then
    printf '%s\n' 'Refusing to stop an unverified process.'
    exit 1
fi

printf '%s\n' 'Stopping private Tailscale...'
kill "$pid" 2>/dev/null
count=0
while kill -0 "$pid" 2>/dev/null && [ "$count" -lt 5 ]; do
    sleep 1
    count=$((count + 1))
done
if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
fi
wait "$pid" 2>/dev/null
rm -f "$PID_FILE" "$SOCKET"
printf '%s\n' 'Private Tailscale stopped.'

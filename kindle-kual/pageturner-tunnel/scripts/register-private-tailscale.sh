#!/bin/sh
# Register this Kindle using a one-off auth key stored in private/auth.key.
# The key is passed by file path, never placed directly in process arguments or logs.

BASE="/mnt/us/extensions/pageturner-tunnel"
CLI="$BASE/bin/tailscale"
AUTH_KEY="$BASE/private/auth.key"
SOCKET="/tmp/pageturner-tailscaled.sock"
LOG_DIR="$BASE/logs"
REGISTER_LOG="$LOG_DIR/register.log"
START_SCRIPT="$BASE/scripts/start-private-tailscale.sh"

mkdir -p "$LOG_DIR" "$BASE/private"
if ! : >"$REGISTER_LOG"; then
    printf '%s\n' 'Cannot create logs/register.log.'
    exit 1
fi

say() {
    printf '%s\n' "$1"
    printf '%s\n' "$1" >>"$REGISTER_LOG"
}

say 'Registration preflight started.'

if [ ! -f "$CLI" ]; then
    say 'Preflight failed: tailscale binary is missing.'
    exit 1
fi
say 'Preflight: tailscale binary present.'

if [ ! -f "$AUTH_KEY" ]; then
    say 'Preflight failed: private/auth.key is missing.'
    exit 1
fi
if [ ! -s "$AUTH_KEY" ]; then
    say 'Preflight failed: private/auth.key is empty.'
    exit 1
fi
say 'Preflight: auth-key file present and non-empty.'

# Reject obviously malformed/multiline files without printing their content.
line_count=$(awk 'NF { count++ } END { print count+0 }' "$AUTH_KEY" 2>/dev/null)
if [ "$line_count" != "1" ]; then
    say "Preflight failed: auth-key file has $line_count non-empty lines; expected 1."
    exit 1
fi
say 'Preflight: auth-key file has one non-empty line.'

say 'Starting or reusing the private Tailscale daemon...'
if ! sh "$START_SCRIPT" >>"$REGISTER_LOG" 2>&1; then
    say 'Registration stopped: daemon startup failed.'
    exit 1
fi
if [ ! -S "$SOCKET" ]; then
    say 'Registration stopped: local API socket is missing.'
    exit 1
fi
say 'Preflight: local API socket present.'

say 'Registering Kindle with the private tailnet...'
"$CLI" --socket="$SOCKET" up \
    --auth-key="file:$AUTH_KEY" \
    --hostname=pageturner-kindle \
    --accept-routes=false \
    --accept-dns=false \
    --ssh=false >>"$REGISTER_LOG" 2>&1
status=$?

if [ "$status" -ne 0 ]; then
    say "Registration failed with exit status $status. The auth key was retained for a retry."
    say 'Review logs/register.log locally; never share the key.'
    exit "$status"
fi

if rm -f "$AUTH_KEY"; then
    say 'Registration succeeded; consumed auth-key file deleted.'
else
    say 'Registration succeeded, but delete private/auth.key manually.'
fi

"$CLI" --socket="$SOCKET" status >>"$REGISTER_LOG" 2>&1
say 'Registration complete. Run Show private Tailscale status.'
exit 0

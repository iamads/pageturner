#!/bin/sh
# Launch-only compatibility test. This script never starts the Tailscale daemon.

BASE="/mnt/us/extensions/pageturner-tunnel"
REPORT="/mnt/us/pageturner-tailscale-launch-test.txt"
TEMP="${REPORT}.tmp"

run_version_test() {
    label="$1"
    binary="$2"
    argument="$3"

    printf '\n[%s]\n' "$label"
    if [ ! -f "$binary" ]; then
        printf '%s\n' 'result: binary missing'
        return
    fi

    printf 'command: %s %s\n' "$label" "$argument"
    if command -v timeout >/dev/null 2>&1; then
        # The older BusyBox on Kindle firmware 5.12.3 uses `-t SECS`;
        # newer GNU/BusyBox variants also accept this spelling.
        timeout -t 15 "$binary" "$argument" 2>&1
        status=$?
    else
        "$binary" "$argument" 2>&1
        status=$?
    fi
    printf 'exit_status: %s\n' "$status"
}

umask 077
rm -f "$TEMP"

{
    printf '%s\n' 'Page Turner / current Tailscale launch test'
    printf '%s\n' 'Version-only commands were used. No daemon, login, state, or Funnel was started.'
    printf '%s\n' 'Expected package: official Tailscale 1.102.4 for 32-bit ARM.'
    printf 'kernel: '; uname -r 2>/dev/null || printf '%s\n' 'unavailable'
    printf 'machine: '; uname -m 2>/dev/null || printf '%s\n' 'unavailable'

    run_version_test 'tailscale' "$BASE/bin/tailscale" 'version'
    run_version_test 'tailscaled' "$BASE/bin/tailscaled" '--version'
} >"$TEMP" 2>&1

if [ ! -s "$TEMP" ]; then
    rm -f "$TEMP"
    printf '%s\n' 'Could not write launch-test report.'
    exit 1
fi

mv -f "$TEMP" "$REPORT"
printf '%s\n' 'Launch-test report created:'
printf '%s\n' "$REPORT"

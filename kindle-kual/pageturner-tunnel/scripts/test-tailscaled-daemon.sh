#!/bin/sh
# Time-bounded, logged-out tailscaled smoke test using in-memory state.

BASE="/mnt/us/extensions/pageturner-tunnel"
DAEMON="$BASE/bin/tailscaled"
CLI="$BASE/bin/tailscale"
REPORT="/mnt/us/pageturner-tailscaled-daemon-test.txt"
TEMP="${REPORT}.tmp"
SOCKET="/tmp/pageturner-tailscaled-smoke.sock"
LOG="/tmp/pageturner-tailscaled-smoke.log"
PID=""

stop_test_daemon() {
    if [ -n "$PID" ]; then
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null
            count=0
            while kill -0 "$PID" 2>/dev/null && [ "$count" -lt 5 ]; do
                sleep 1
                count=$((count + 1))
            done
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null
            fi
        fi
        wait "$PID" 2>/dev/null
    fi
    PID=""
    rm -f "$SOCKET" "$LOG"
}

write_process_metrics() {
    if [ -n "$PID" ] && [ -r "/proc/$PID/status" ]; then
        grep -E '^(Name|State|VmPeak|VmSize|VmRSS|VmData|Threads):' "/proc/$PID/status" 2>/dev/null
    else
        printf '%s\n' 'process_metrics: unavailable'
    fi
}

trap 'stop_test_daemon; rm -f "$TEMP"' 1 2 15
umask 077
rm -f "$TEMP" "$SOCKET" "$LOG"

{
    printf '%s\n' 'Page Turner / temporary tailscaled daemon test'
    printf '%s\n' 'Mode: userspace networking, in-memory ephemeral state, logged out.'
    printf '%s\n' 'No authentication, persistent node state, Serve, or Funnel was configured.'
    printf 'kernel: '; uname -r 2>/dev/null || printf '%s\n' 'unavailable'
    printf 'machine: '; uname -m 2>/dev/null || printf '%s\n' 'unavailable'

    if [ ! -f "$DAEMON" ] || [ ! -f "$CLI" ]; then
        printf '%s\n' 'result: required binary missing'
    else
        printf '\n[start]\n'
        TS_NO_LOGS_NO_SUPPORT=true "$DAEMON" \
            --tun=userspace-networking \
            --state=mem: \
            --socket="$SOCKET" \
            --port=0 >"$LOG" 2>&1 &
        PID=$!
        printf 'pid_created: yes\n'

        sleep 3
        if kill -0 "$PID" 2>/dev/null; then
            printf 'alive_after_3_seconds: yes\n'
            printf 'local_api_socket: '
            if [ -S "$SOCKET" ]; then printf '%s\n' 'present'; else printf '%s\n' 'absent'; fi

            printf '\n[local_api_status]\n'
            if command -v timeout >/dev/null 2>&1; then
                timeout -t 10 "$CLI" --socket="$SOCKET" status 2>&1
                cli_status=$?
            else
                "$CLI" --socket="$SOCKET" status 2>&1
                cli_status=$?
            fi
            printf 'status_exit_code: %s\n' "$cli_status"

            printf '\n[metrics_after_3_seconds]\n'
            write_process_metrics
            sleep 12
            printf '\n[stability]\n'
            if kill -0 "$PID" 2>/dev/null; then
                printf 'alive_after_15_seconds: yes\n'
                write_process_metrics
            else
                printf 'alive_after_15_seconds: no\n'
            fi
        else
            printf 'alive_after_3_seconds: no\n'
        fi

        printf '\n[daemon_log_classification]\n'
        if [ -r "$LOG" ]; then
            printf 'line_count: '
            wc -l <"$LOG" 2>/dev/null || printf '%s\n' 'unavailable'
            printf 'fatal_or_panic_lines: '
            grep -iE 'fatal|panic' "$LOG" 2>/dev/null | wc -l
            printf 'error_lines: '
            grep -i 'error' "$LOG" 2>/dev/null | wc -l
        else
            printf '%s\n' 'log: unavailable'
        fi

        printf '\n[shutdown]\n'
        stop_test_daemon
        printf 'test_daemon_running_after_cleanup: '
        if [ -n "$PID" ]; then printf '%s\n' 'unknown'; else printf '%s\n' 'no'; fi
        printf 'temporary_socket_present: '
        if [ -e "$SOCKET" ]; then printf '%s\n' 'yes'; else printf '%s\n' 'no'; fi
        printf 'temporary_log_present: '
        if [ -e "$LOG" ]; then printf '%s\n' 'yes'; else printf '%s\n' 'no'; fi
    fi
} >"$TEMP" 2>&1

if [ ! -s "$TEMP" ]; then
    stop_test_daemon
    rm -f "$TEMP"
    printf '%s\n' 'Could not write daemon-test report.'
    exit 1
fi

mv -f "$TEMP" "$REPORT"
printf '%s\n' 'Temporary daemon-test report created:'
printf '%s\n' "$REPORT"

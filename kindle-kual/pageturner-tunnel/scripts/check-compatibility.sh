#!/bin/sh
# Read-only compatibility inventory for the Page Turner Tailscale experiment.
# The only write is the report placed at the root of Kindle USB storage.

REPORT="/mnt/us/pageturner-compatibility.txt"
TEMP="${REPORT}.tmp"

write_command_status() {
    command_name="$1"
    if command -v "$command_name" >/dev/null 2>&1; then
        printf '%s: available\n' "$command_name"
    else
        printf '%s: unavailable\n' "$command_name"
    fi
}

write_file_status() {
    label="$1"
    path="$2"
    if [ -e "$path" ]; then
        printf '%s: present\n' "$label"
    else
        printf '%s: absent\n' "$label"
    fi
}

umask 077
rm -f "$TEMP"

{
    printf '%s\n' 'Page Turner / Tailscale compatibility report'
    printf '%s\n' 'No Tailscale binary was installed or executed.'
    printf '\n[time]\n'
    date -u 2>/dev/null || date 2>/dev/null || printf '%s\n' 'date: unavailable'

    printf '\n[kernel]\n'
    printf 'system: '; uname -s 2>/dev/null || printf '%s\n' 'unavailable'
    printf 'release: '; uname -r 2>/dev/null || printf '%s\n' 'unavailable'
    printf 'version: '; uname -v 2>/dev/null || printf '%s\n' 'unavailable'
    printf 'machine: '; uname -m 2>/dev/null || printf '%s\n' 'unavailable'
    if command -v getconf >/dev/null 2>&1; then
        printf 'userspace_bits: '
        getconf LONG_BIT 2>/dev/null || printf '%s\n' 'unavailable'
    else
        printf '%s\n' 'userspace_bits: unavailable'
    fi

    printf '\n[cpu]\n'
    if [ -r /proc/cpuinfo ]; then
        # Deliberately omit Serial and other device identifiers.
        awk -F: '
            /^[[:space:]]*(Processor|model name|CPU architecture|CPU variant|CPU part|CPU revision|Features|Hardware)[[:space:]]*:/ {
                key=$1; value=$2
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                line=key ": " value
                if (!seen[line]++) print line
            }
        ' /proc/cpuinfo 2>/dev/null
    else
        printf '%s\n' 'cpuinfo: unavailable'
    fi

    printf '\n[memory_kib]\n'
    if [ -r /proc/meminfo ]; then
        grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree):' /proc/meminfo 2>/dev/null
    else
        printf '%s\n' 'meminfo: unavailable'
    fi

    printf '\n[storage_kib]\n'
    df -k /mnt/us 2>/dev/null || printf '%s\n' '/mnt/us: unavailable'
    df -k /tmp 2>/dev/null || printf '%s\n' '/tmp: unavailable'

    printf '\n[network_support]\n'
    write_file_status 'tun_device' '/dev/net/tun'
    write_file_status 'koreader_ca_bundle' '/mnt/us/koreader/data/ca-bundle.crt'
    if [ -w /mnt/us ]; then
        printf '%s\n' 'usb_storage_writable: yes'
    else
        printf '%s\n' 'usb_storage_writable: no'
    fi

    printf '\n[commands]\n'
    write_command_status sh
    write_command_status tar
    write_command_status gzip
    write_command_status wget
    write_command_status curl
    write_command_status openssl

    printf '\n[privacy]\n'
    printf '%s\n' 'CPU serial, book data, Wi-Fi details, credentials, and Page Turner tokens were not collected.'
} >"$TEMP" 2>/dev/null

if [ ! -s "$TEMP" ]; then
    rm -f "$TEMP"
    printf '%s\n' 'Could not write compatibility report.'
    exit 1
fi

mv -f "$TEMP" "$REPORT"
printf '%s\n' 'Compatibility report created:'
printf '%s\n' "$REPORT"

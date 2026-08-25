#!/bin/sh

# Audit the resolved Docker-enabled kernel configuration using the pinned Moby
# check-config script. Generated reports remain in the private work directory.

set -eu

config="${CONFIG_FILE:-/rt7-work/build/kernel/config-test/.config}"
tool="${MOBY_CHECK_CONFIG:-/rt7-work/downloads/moby-check-config.sh}"
report="${REPORT_FILE:-/rt7-work/device-dumps/moby-check-merged-config.txt}"
expected='fda4343e9b50c47896653ca774ccbe9614bfcdb60f080d2b6277baf27efc0a71'

if [ ! -r "$config" ]; then
    printf 'error: merged kernel config not readable: %s\n' "$config" >&2
    exit 1
fi

if [ ! -r "$tool" ]; then
    printf 'error: Moby check-config not readable: %s\n' "$tool" >&2
    exit 1
fi

actual="$(sha256sum "$tool" | awk '{print $1}')"
if [ "$actual" != "$expected" ]; then
    printf 'error: Moby check-config SHA-256 mismatch: %s\n' "$actual" >&2
    exit 1
fi

mkdir -p "$(dirname "$report")"
bash "$tool" "$config" | tee "$report"

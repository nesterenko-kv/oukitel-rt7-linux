#!/bin/sh

# Fetch the pinned upstream Docker kernel audit script into the private work
# directory and verify it before use.

set -eu

url='https://raw.githubusercontent.com/moby/moby/2fea1c603bf5bfbc1f480383dcf10abe87cbeaf0/contrib/check-config.sh'
expected='fda4343e9b50c47896653ca774ccbe9614bfcdb60f080d2b6277baf27efc0a71'
destination="${1:-/rt7-work/downloads/moby-check-config.sh}"

mkdir -p "$(dirname "$destination")"
temporary="$(mktemp "${destination}.tmp.XXXXXX")"
trap 'rm -f "$temporary"' EXIT HUP INT TERM

curl --fail --location --silent --show-error "$url" --output "$temporary"
actual="$(sha256sum "$temporary" | awk '{print $1}')"

if [ "$actual" != "$expected" ]; then
    printf 'error: expected SHA-256 %s but downloaded %s\n' "$expected" "$actual" >&2
    exit 1
fi

mv "$temporary" "$destination"
trap - EXIT HUP INT TERM
printf 'verified Moby check-config: %s\n' "$destination"

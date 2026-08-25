#!/bin/sh

# Install the exact Android clang release recorded in the official RT7 kernel
# build string into a Linux-native Docker volume.

set -eu

url='https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-11.0.0_r1/clang-r383902.tar.gz'
expected='b405185894767ab9eaa23febc7ad549aa970ad3997ff7182f46d545e19c26a86'
archive="${TOOLCHAIN_ARCHIVE:-/rt7-work/downloads/clang-r383902-android-11.0.0_r1.tar.gz}"
destination="${TOOLCHAIN_DIR:-/work/toolchain/clang-r383902}"

verify_toolchain() {
    "$destination/bin/clang" --version | grep -q 'based on r383902'
}

if verify_toolchain 2>/dev/null; then
    printf 'clang-r383902 already prepared at %s\n' "$destination"
    exit 0
fi

mkdir -p "$(dirname "$archive")"
if [ ! -r "$archive" ]; then
    temporary="$(mktemp "${archive}.tmp.XXXXXX")"
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    curl --fail --location --silent --show-error "$url" --output "$temporary"
    mv "$temporary" "$archive"
    trap - EXIT HUP INT TERM
fi

actual="$(sha256sum "$archive" | awk '{print $1}')"
if [ "$actual" != "$expected" ]; then
    printf 'error: toolchain archive SHA-256 mismatch: %s\n' "$actual" >&2
    exit 1
fi

if [ -e "$destination" ] && [ -n "$(ls -A "$destination" 2>/dev/null)" ]; then
    printf 'error: incomplete toolchain destination is not empty: %s\n' "$destination" >&2
    exit 1
fi

mkdir -p "$destination"
tar -xzf "$archive" -C "$destination"

if ! verify_toolchain; then
    printf 'error: extracted toolchain did not identify as clang-r383902\n' >&2
    exit 1
fi

printf 'prepared clang-r383902 at %s\n' "$destination"

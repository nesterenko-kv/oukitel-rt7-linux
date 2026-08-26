#!/bin/sh

# Fetch the pinned AOSP boot-image and AVB tools into the private work tree.

set -eu

tools_root="${ANDROID_TOOLS_DIR:-/rt7-work/tools/android-13.0.0_r1}"

prepare_repo() {
    label="$1"
    url="$2"
    ref="$3"
    commit="$4"
    destination="$5"

    if [ -d "$destination/.git" ]; then
        actual="$(git -C "$destination" rev-parse HEAD)"
        if [ "$actual" != "$commit" ]; then
            printf 'error: %s contains unexpected commit %s\n' "$destination" "$actual" >&2
            exit 1
        fi
        if ! git -C "$destination" diff --quiet || \
            ! git -C "$destination" diff --cached --quiet; then
            printf 'error: %s contains local changes\n' "$destination" >&2
            exit 1
        fi
        printf '%s already prepared at %s\n' "$label" "$destination"
        return
    fi

    if [ -e "$destination" ] && [ -n "$(ls -A "$destination" 2>/dev/null)" ]; then
        printf 'error: destination is not empty: %s\n' "$destination" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$destination")"
    git clone --depth 1 --branch "$ref" "$url" "$destination"

    actual="$(git -C "$destination" rev-parse HEAD)"
    if [ "$actual" != "$commit" ]; then
        printf 'error: expected %s but cloned %s\n' "$commit" "$actual" >&2
        exit 1
    fi

    printf 'prepared %s %s at %s\n' "$label" "$commit" "$destination"
}

prepare_repo \
    mkbootimg \
    'https://android.googlesource.com/platform/system/tools/mkbootimg' \
    'android-13.0.0_r1' \
    '6cb944b82c819b691bc21d8228e155f1db07a446' \
    "$tools_root/mkbootimg"

prepare_repo \
    avb \
    'https://android.googlesource.com/platform/external/avb' \
    'android-13.0.0_r1' \
    '8261ecd67956f6e9647ff5fd4aeb829f75fb3f66' \
    "$tools_root/avb"

python3 "$tools_root/mkbootimg/unpack_bootimg.py" --help >/dev/null
python3 "$tools_root/mkbootimg/mkbootimg.py" --help >/dev/null
python3 "$tools_root/avb/avbtool.py" version

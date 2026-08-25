#!/bin/sh

# Apply the small, reviewable compatibility patch series to the pinned kernel
# checkout. The operation is idempotent and refuses ambiguous source state.

set -eu

kernel_dir="${KERNEL_DIR:-/work/kernel}"
modules_dir="${MODULES_DIR:-/work/modules}"
kernel_patch_dir="${KERNEL_PATCH_DIR:-/project/patches/kernel}"
modules_patch_dir="${MODULES_PATCH_DIR:-/project/patches/modules}"

if [ ! -d "$kernel_dir/.git" ]; then
    printf 'error: kernel source not prepared: %s\n' "$kernel_dir" >&2
    exit 1
fi

apply_series() {
    source_dir="$1"
    patch_dir="$2"

    [ -d "$patch_dir" ] || return 0
    if [ ! -d "$source_dir/.git" ]; then
        printf 'error: source checkout not prepared: %s\n' "$source_dir" >&2
        exit 1
    fi

    for patch in "$patch_dir"/*.patch; do
        [ -e "$patch" ] || continue

        if git -C "$source_dir" apply --ignore-space-change --reverse --check "$patch" 2>/dev/null; then
            printf 'already applied: %s\n' "$(basename "$patch")"
        elif git -C "$source_dir" apply --ignore-space-change --check "$patch"; then
            git -C "$source_dir" apply --ignore-space-change "$patch"
            printf 'applied: %s\n' "$(basename "$patch")"
        else
            printf 'error: patch does not apply cleanly: %s\n' "$patch" >&2
            exit 1
        fi
    done
}

apply_series "$kernel_dir" "$kernel_patch_dir"
apply_series "$modules_dir" "$modules_patch_dir"

#!/bin/sh

# Populate the Linux-only Docker volume used for the kernel checkout. A named
# volume is required because the source contains names such as aux.c that cannot
# be checked out on a Windows filesystem.

set -eu

prepare_repo() {
    label="$1"
    url="$2"
    branch="$3"
    commit="$4"
    destination="$5"
    cache="$6"

    if [ -d "$destination/.git" ]; then
        actual="$(git -C "$destination" rev-parse HEAD)"
        if [ "$actual" != "$commit" ]; then
            printf 'error: %s contains unexpected commit %s\n' "$destination" "$actual" >&2
            exit 1
        fi
        printf '%s source already prepared at %s\n' "$label" "$destination"
        return
    fi

    if [ -e "$destination" ] && [ -n "$(ls -A "$destination" 2>/dev/null)" ]; then
        printf 'error: destination is not empty: %s\n' "$destination" >&2
        exit 1
    fi

    if git --git-dir="$cache" rev-parse --is-bare-repository >/dev/null 2>&1; then
        printf 'using local bare cache: %s\n' "$cache"
        git clone --no-checkout --no-hardlinks "$cache" "$destination"
        git -C "$destination" checkout --detach "$commit"
    else
        git clone --depth 1 --single-branch --branch "$branch" "$url" "$destination"
    fi

    actual="$(git -C "$destination" rev-parse HEAD)"
    if [ "$actual" != "$commit" ]; then
        printf 'error: expected %s but cloned %s\n' "$commit" "$actual" >&2
        exit 1
    fi

    printf 'prepared %s source %s at %s\n' "$label" "$commit" "$destination"
}

prepare_repo \
    kernel \
    'https://github.com/oppo-source/android_kernel_oppo_mtk_4.19.git' \
    'oppo/mtk_t_13.0.0' \
    'f1ac3e53f433c6b68e2f6f37191e488d2bd41557' \
    "${KERNEL_DIR:-/work/kernel}" \
    "${KERNEL_CACHE:-/rt7-work/sources/android_kernel_oppo_mtk_4.19.git}"

prepare_repo \
    modules \
    'https://github.com/oppo-source/android_kernel_modules_oppo_mtk_4.19.git' \
    'oppo/mtk_t_13.0.0' \
    'aa8b40a3f646040b2c58b695373407731718daed' \
    "${MODULES_DIR:-/work/modules}" \
    "${MODULES_CACHE:-/rt7-work/sources/android_kernel_modules_oppo_mtk_4.19.git}"

/bin/sh /project/scripts/link-kernel-sources.sh
printf 'linked external vendor tree: /work/vendor -> /work/modules/vendor\n'

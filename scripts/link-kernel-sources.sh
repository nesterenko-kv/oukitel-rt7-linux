#!/bin/sh

# Recreate links normally supplied by the full Android build checkout. OPPO's
# kernel and external module repositories are kept in separate Docker volumes.

set -eu

ensure_link() {
    link="$1"
    target="$2"

    if { [ -e "$link" ] || [ -L "$link" ]; } && [ ! -L "$link" ]; then
        printf 'error: %s exists and is not a symbolic link\n' "$link" >&2
        exit 1
    fi

    ln -sfn "$target" "$link"
}

ensure_link /work/vendor /work/modules/vendor
ensure_link /vnd /work/modules

# This directory is populated by Android's vendor module assembly rather than
# represented as a symlink in the public kernel repository.
if [ -d /work/kernel/.git ]; then
    ensure_link \
        /work/kernel/sound/soc/codecs/audio \
        /work/modules/vendor/oplus/kernel_4.19/audio
fi

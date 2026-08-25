#!/system/bin/sh
# Read-only, allowlisted hardware inventory for Android recovery/porting work.
# The output intentionally excludes serial numbers, radio identifiers, network
# addresses, accounts, and partition contents.

set -eu

section() {
    printf '\n## %s\n' "$1"
}

prop() {
    value="$(getprop "$1")"
    if [ -n "$value" ]; then
        printf '%s=%s\n' "$1" "$value"
    fi
}

section "identity"
for name in \
    ro.product.brand \
    ro.product.manufacturer \
    ro.product.model \
    ro.product.device \
    ro.product.board \
    ro.board.platform \
    ro.hardware \
    ro.boot.hardware \
    ro.boot.hardware.sku \
    ro.mediatek.platform \
    ro.mediatek.version.branch \
    ro.mediatek.version.release; do
    prop "$name"
done

section "software"
for name in \
    ro.build.version.release \
    ro.build.version.sdk \
    ro.build.version.security_patch \
    ro.build.type \
    ro.build.tags \
    ro.build.flavor \
    ro.treble.enabled \
    ro.virtual_ab.enabled \
    ro.build.ab_update; do
    prop "$name"
done
uname -a

section "verified boot"
for name in \
    ro.boot.slot_suffix \
    ro.boot.slot \
    ro.boot.dynamic_partitions \
    ro.boot.virtual_ab.enabled \
    ro.boot.verifiedbootstate \
    ro.boot.vbmeta.device_state \
    ro.boot.flash.locked \
    ro.boot.avb_version; do
    prop "$name"
done

section "cpu"
awk '
    /^processor[[:space:]]*:/ ||
    /^CPU implementer[[:space:]]*:/ ||
    /^CPU architecture[[:space:]]*:/ ||
    /^CPU variant[[:space:]]*:/ ||
    /^CPU part[[:space:]]*:/ ||
    /^CPU revision[[:space:]]*:/ ||
    /^Hardware[[:space:]]*:/ { print }
' /proc/cpuinfo

section "memory"
awk '/^(MemTotal|SwapTotal|CmaTotal|VmallocTotal):/ { print }' /proc/meminfo

section "filesystems"
cat /proc/filesystems

section "mounts"
awk '{ print $1, $2, $3, $4 }' /proc/mounts | \
    sed -E 's#(/data/media/)[0-9]+#\1USER#g'

section "block devices"
for path in /dev/block/by-name /dev/block/bootdevice/by-name \
    /dev/block/platform/*/by-name; do
    if [ -d "$path" ]; then
        printf 'by-name=%s\n' "$path"
        ls -l "$path"
        break
    fi
done

section "loaded modules"
cat /proc/modules 2>/dev/null || true

section "input devices"
awk '
    /^I:/ || /^N:/ || /^P:/ || /^S:/ || /^H:/ || /^B:/ || /^$/ { print }
' /proc/bus/input/devices 2>/dev/null || true

section "power supplies"
for supply in /sys/class/power_supply/*; do
    [ -d "$supply" ] || continue
    printf 'name=%s\n' "${supply##*/}"
    for field in type present online status health technology capacity \
        voltage_now current_now current_max voltage_max temp; do
        if [ -r "$supply/$field" ]; then
            printf '%s=' "$field"
            cat "$supply/$field"
        fi
    done
done

section "kernel config checksum"
if [ -r /proc/config.gz ]; then
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum /proc/config.gz
    else
        printf 'present=/proc/config.gz\n'
    fi
else
    printf 'unavailable\n'
fi

#!/bin/sh

# Inject only the host's ADB public key into the pinned stock recovery ramdisk.
# The personalized result must stay in the private sibling work directory.

set -eu

stock_ramdisk=${STOCK_RAMDISK:-/rt7-work/firmware/unpacked/V1.4.8/boot/ramdisk}
expected_stock_sha256=${EXPECTED_STOCK_SHA256:-2ccef512b82aa029939334cae4745e23ec0923e9c2b096e3d0258ef26f7d0028}
adb_public_key=${ADB_PUBLIC_KEY:-/rt7-work/keys/adbkey.pub}
output=${OUTPUT_RAMDISK:-/rt7-work/build/boot/rt7-v148-recovery-adb-personalized.ramdisk.gz}

for input in "$stock_ramdisk" "$adb_public_key"; do
    if [ ! -f "$input" ]; then
        printf 'error: required input is not a file: %s\n' "$input" >&2
        exit 1
    fi
done

case "$output" in
    /rt7-work/build/boot/*.ramdisk.gz) ;;
    *)
        printf 'error: output must be a .ramdisk.gz under /rt7-work/build/boot\n' >&2
        exit 1
        ;;
esac

actual_stock_sha256=$(sha256sum "$stock_ramdisk" | cut -d ' ' -f 1)
if [ "$actual_stock_sha256" != "$expected_stock_sha256" ]; then
    printf 'error: stock ramdisk hash mismatch: %s\n' "$actual_stock_sha256" >&2
    exit 1
fi

if ! awk '
    NF != 2 || $1 !~ /^[A-Za-z0-9+\/=]+$/ { invalid=1 }
    { lines++ }
    END { exit invalid || lines != 1 }
' "$adb_public_key"; then
    printf 'error: ADB public key must be one standard adbkey.pub line\n' >&2
    exit 1
fi

workdir=$(mktemp -d)
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT INT TERM

tree=$workdir/tree
mkdir -p "$tree"
(
    cd "$tree"
    gzip -dc "$stock_ramdisk" | cpio -idmu --no-absolute-filenames
)

for required in system/bin/init system/bin/adbd system/bin/sh plat_file_contexts sepolicy; do
    if [ ! -e "$tree/$required" ]; then
        printf 'error: stock recovery ramdisk is missing %s\n' "$required" >&2
        exit 1
    fi
done

if ! grep -q '^/adb_keys[[:space:]]' "$tree/plat_file_contexts"; then
    printf 'error: stock policy has no /adb_keys file-context rule\n' >&2
    exit 1
fi

install -m 0640 -o 0 -g 2000 "$adb_public_key" "$tree/adb_keys"
find "$tree" -xdev -exec touch -h -d '@0' {} +

candidate=$workdir/ramdisk.gz
(
    cd "$tree"
    find . -xdev -print0 \
        | LC_ALL=C sort -z \
        | cpio --null --create --format=newc --reproducible 2>/dev/null \
        | gzip -9 -n > "$candidate"
)

verify=$workdir/verify
mkdir -p "$verify"
(
    cd "$verify"
    gzip -dc "$candidate" | cpio -idmu --no-absolute-filenames 2>/dev/null
)
cmp "$adb_public_key" "$verify/adb_keys"
test "$(stat -c %a "$verify/adb_keys")" = 640
test "$(stat -c %u "$verify/adb_keys")" = 0
test "$(stat -c %g "$verify/adb_keys")" = 2000

mkdir -p "$(dirname "$output")"
if [ -e "$output" ]; then
    if cmp -s "$candidate" "$output"; then
        printf 'personalized ramdisk already exists and is identical: %s\n' "$output"
    else
        printf 'error: refusing to overwrite different output: %s\n' "$output" >&2
        exit 1
    fi
else
    mv "$candidate" "$output"
fi

printf 'personalized recovery ramdisk: %s\n' "$output"
sha256sum "$output"

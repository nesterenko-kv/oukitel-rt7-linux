#!/bin/sh
set -eu

ROOTFS_TAR=${ROOTFS_TAR:-/rt7-work/rootfs/rt7-debian-bookworm-arm64.rootfs.tar}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-/rt7-work/keys/rt7_admin_ed25519.pub}
OUTPUT_IMAGE=${OUTPUT_IMAGE:-/rt7-work/rootfs/rt7-debian-bookworm-arm64.ext4}
IMAGE_SIZE=${IMAGE_SIZE:-4G}
FILESYSTEM_UUID=${FILESYSTEM_UUID:-52543700-0000-4000-8000-000000000001}
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1787529600}

for input in "${ROOTFS_TAR}" "${SSH_PUBLIC_KEY}"; do
    if [ ! -f "${input}" ]; then
        echo "required input not found: ${input}" >&2
        exit 1
    fi
done

case "${OUTPUT_IMAGE}" in
    /rt7-work/rootfs/*.ext4) ;;
    *)
        echo "output must be an .ext4 file under /rt7-work/rootfs" >&2
        exit 1
        ;;
esac

if [ -e "${OUTPUT_IMAGE}" ]; then
    echo "refusing to overwrite: ${OUTPUT_IMAGE}" >&2
    exit 1
fi

if [ "$(wc -l < "${SSH_PUBLIC_KEY}")" -ne 1 ] \
    || ! grep -Eq '^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$' "${SSH_PUBLIC_KEY}"; then
    echo "SSH public key must contain one valid-looking Ed25519 key" >&2
    exit 1
fi

workdir=$(mktemp -d)
cleanup() {
    rm -rf "${workdir}"
}
trap cleanup EXIT INT TERM

rootdir=${workdir}/rootfs
mkdir -p "${rootdir}"
tar --extract \
    --file "${ROOTFS_TAR}" \
    --directory "${rootdir}" \
    --numeric-owner \
    --xattrs \
    --xattrs-include='*'

if ! file -L "${rootdir}/bin/sh" | grep -q 'ARM aarch64'; then
    echo "root filesystem is not ARM64" >&2
    exit 1
fi

install -d -m 0700 -o 1000 -g 1000 "${rootdir}/home/rt7/.ssh"
install -m 0600 -o 1000 -g 1000 \
    "${SSH_PUBLIC_KEY}" "${rootdir}/home/rt7/.ssh/authorized_keys"

truncate -s "${IMAGE_SIZE}" "${OUTPUT_IMAGE}"
E2FSPROGS_FAKE_TIME=${SOURCE_DATE_EPOCH} \
    mkfs.ext4 \
        -F \
        -L rt7-debian \
        -U "${FILESYSTEM_UUID}" \
        -O '^orphan_file' \
        -E "hash_seed=${FILESYSTEM_UUID},lazy_itable_init=0,lazy_journal_init=0" \
        -d "${rootdir}" \
        "${OUTPUT_IMAGE}"

E2FSPROGS_FAKE_TIME=${SOURCE_DATE_EPOCH} e2fsck -fn "${OUTPUT_IMAGE}"

actual_uuid=$(dumpe2fs -h "${OUTPUT_IMAGE}" 2>/dev/null \
    | sed -n 's/^Filesystem UUID:[[:space:]]*//p')
if [ "${actual_uuid}" != "${FILESYSTEM_UUID}" ]; then
    echo "unexpected filesystem UUID: ${actual_uuid}" >&2
    exit 1
fi

if dumpe2fs -h "${OUTPUT_IMAGE}" 2>/dev/null \
    | grep '^Filesystem features:' | grep -qw orphan_file; then
    echo "unsupported ext4 orphan_file feature is enabled" >&2
    exit 1
fi

key_stat=$(debugfs -R 'stat /home/rt7/.ssh/authorized_keys' "${OUTPUT_IMAGE}" 2>/dev/null)
echo "${key_stat}" | grep -q 'User:[[:space:]]*1000'
echo "${key_stat}" | grep -q 'Group:[[:space:]]*1000'
echo "${key_stat}" | grep -q 'Mode:[[:space:]]*0600'

echo "Created validated RT7 Debian ext4 image: ${OUTPUT_IMAGE}"
sha256sum "${OUTPUT_IMAGE}"

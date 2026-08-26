#!/bin/bash

# Exercise the Android recovery toybox -> ext4 loop -> Debian chroot handoff.
# Run only in the disposable privileged ARM64 Docker smoke-test container.

set -euo pipefail

recovery=${RECOVERY_TREE:-/rt7-work/firmware/unpacked/V1.4.8/ramdisk-tree}
image=${ROOTFS_IMAGE:-/rt7-work/rootfs/rt7-debian-bookworm-arm64-handoff-smoke-v2.ext4}
starter=/project/scripts/rt7-recovery-linux-start.sh
remote_image=$recovery/tmp/rt7-debian-recovery-test.ext4
remote_starter=$recovery/tmp/rt7-recovery-linux-start.sh
root=$recovery/mnt/rt7-debian
prep=/tmp/rt7-handoff-prep

for required in "$recovery/system/bin/sh" "$image" "$starter"; do
    test -e "$required"
done

cleanup() {
    set +e
    if test -s "$root/run/docker.pid"; then
        kill "$(cat "$root/run/docker.pid")" 2>/dev/null
    fi
    if test -s "$root/run/sshd.pid"; then
        kill "$(cat "$root/run/sshd.pid")" 2>/dev/null
    fi
    sleep 1
    umount -R "$root/sys" "$root/proc" "$root/dev" 2>/dev/null
    umount "$root" 2>/dev/null
    if test -s "$recovery/tmp/rt7-debian.loop"; then
        losetup -d "$(cat "$recovery/tmp/rt7-debian.loop")" 2>/dev/null
    fi
    umount "$remote_image" "$remote_starter" 2>/dev/null
    umount -R "$recovery/sys" "$recovery/proc" "$recovery/dev" 2>/dev/null
    umount "$prep" 2>/dev/null
    if test -n "${prep_loop:-}"; then
        losetup -d "$prep_loop" 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

# Docker Desktop's nested test cannot manipulate host iptables. Change only
# the disposable handoff image; the target recovery image keeps iptables=true.
mkdir -p "$prep"
prep_loop=$(losetup -f --show "$image")
mount -t ext4 "$prep_loop" "$prep"
jq '.iptables=false' "$prep/etc/docker/daemon.json" > /tmp/rt7-daemon.json
install -m 0644 /tmp/rt7-daemon.json "$prep/etc/docker/daemon.json"
umount "$prep"
losetup -d "$prep_loop"
prep_loop=

mount --rbind /dev "$recovery/dev"
mount --make-rslave "$recovery/dev"
# Android toybox reports loop devices under /dev/block. Docker Desktop exposes
# the same devices directly under /dev, so mirror Android's names for the test.
mkdir -p /dev/block
for loopdev in /dev/loop[0-9]*; do
    test -b "$loopdev" || continue
    link=/dev/block/$(basename "$loopdev")
    test -e "$link" || ln -s "../$(basename "$loopdev")" "$link"
done
mount --rbind /proc "$recovery/proc"
mount --make-rslave "$recovery/proc"
mount --rbind /sys "$recovery/sys"
mount --make-rslave "$recovery/sys"
touch "$remote_image" "$remote_starter"
mount --bind "$image" "$remote_image"
mount --bind "$starter" "$remote_starter"

chroot "$recovery" /system/bin/sh \
    /tmp/rt7-recovery-linux-start.sh \
    /tmp/rt7-debian-recovery-test.ext4

grep -q cgroup "$root/proc/mounts"
test -r "$root/sys/fs/cgroup/cgroup.controllers"

attempt=0
until chroot "$root" /usr/local/sbin/rt7-healthcheck; do
    attempt=$((attempt + 1))
    if test "$attempt" -ge 30; then
        cat "$root/var/log/rt7/dockerd.log" >&2
        exit 1
    fi
    sleep 1
done

echo 'Android recovery -> Debian SSH/Docker handoff smoke test passed'

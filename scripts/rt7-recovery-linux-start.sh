#!/system/bin/sh

# Mount a Debian ext4 image from recovery RAM and start its SSH/Docker stack.
# This is intentionally manual: nothing starts merely because recovery booted.

set -eu

PATH=/system/bin
export PATH

image=${1:-/tmp/rt7-debian-recovery-test.ext4}
root=/mnt/rt7-debian
loop_state=/tmp/rt7-debian.loop

if [ "$(id -u)" -ne 0 ]; then
    echo 'error: recovery Linux starter must run as root' >&2
    exit 1
fi
if [ ! -f "$image" ]; then
    echo "error: Debian image not found: $image" >&2
    exit 1
fi

# Stock Android normally prepares its cgroup hierarchy outside recovery. If
# recovery exposes none at all, create the cgroup-v1 layout Docker 20 expects.
if [ ! -r /sys/fs/cgroup/cgroup.controllers ] \
    && ! grep -q ' cgroup ' /proc/mounts; then
    mkdir -p /sys/fs/cgroup
    mount -t tmpfs -o mode=0755 cgroup-root /sys/fs/cgroup
    for controllers in \
        blkio \
        cpu,cpuacct \
        cpuset \
        devices \
        freezer \
        hugetlb \
        memory \
        net_cls,net_prio \
        perf_event \
        pids; do
        mkdir -p "/sys/fs/cgroup/$controllers"
        mount -t cgroup -o "$controllers" cgroup "/sys/fs/cgroup/$controllers"
    done
fi

mkdir -p "$root"
if ! mountpoint -q "$root"; then
    loopdev=$(losetup -f)
    losetup "$loopdev" "$image"
    if ! mount -t ext4 -o rw,noatime "$loopdev" "$root"; then
        losetup -d "$loopdev"
        exit 1
    fi
    echo "$loopdev" > "$loop_state"
fi

for source in /dev /proc /sys; do
    target=$root$source
    mkdir -p "$target"
    if ! mountpoint -q "$target"; then
        mount --rbind "$source" "$target"
        mount -o rslave none "$target"
    fi
done

# Toybox 0.8.4 accepts --rbind but does not carry nested mounts across it.
# Bind the two nested mounts Debian needs explicitly: PTYs for SSH and the
# controller hierarchy for Docker.
for source in /dev/pts /sys/fs/cgroup; do
    target=$root$source
    mkdir -p "$target"
    if mountpoint -q "$source" && ! mountpoint -q "$target"; then
        mount --rbind "$source" "$target"
        mount -o rslave none "$target"
    fi
done

chroot "$root" /usr/local/sbin/rt7-chroot-start
echo 'RT7 Debian requested; use adb forward tcp:22007 tcp:22 for SSH'

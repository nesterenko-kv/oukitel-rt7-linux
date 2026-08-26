#!/bin/sh
set -eu

test "$(dpkg --print-architecture)" = arm64
test "$(id -u rt7)" = 1000
test "$(passwd -S rt7 | cut -d ' ' -f 2)" = L
test ! -e /etc/ssh/ssh_host_ed25519_key
test "$(readlink -f /usr/sbin/iptables)" = /usr/sbin/xtables-legacy-multi
test "$(jq -r .iptables /etc/docker/daemon.json)" = true
test "$(systemctl is-enabled ssh.service)" = enabled
test "$(systemctl is-enabled docker.service)" = enabled

# Docker Desktop's nested container does not expose usable iptables tables and
# has an OverlayFS root. Put Docker data on ext4 and disable only the nested
# test's iptables integration. The target rootfs keeps iptables enabled.
install -d -m 0711 /var/lib/docker
truncate -s 768M /tmp/docker-data.ext4
mkfs.ext4 -q -F /tmp/docker-data.ext4
mount -o loop /tmp/docker-data.ext4 /var/lib/docker
test "$(stat -f -c %T /var/lib/docker)" = ext2/ext3

jq '.iptables=false' /etc/docker/daemon.json > /tmp/daemon.json
install -m 0644 /tmp/daemon.json /etc/docker/daemon.json

ssh-keygen -q -t ed25519 -N '' -f /tmp/rt7-smoke-client
install -m 0600 -o rt7 -g rt7 \
    /tmp/rt7-smoke-client.pub /home/rt7/.ssh/authorized_keys
/usr/local/sbin/rt7-chroot-start

attempt=0
until docker info >/tmp/docker-info 2>/tmp/docker-error; do
    attempt=$((attempt + 1))
    if [ "${attempt}" -ge 30 ]; then
        cat /var/log/rt7/dockerd.log >&2
        cat /tmp/docker-error >&2
        exit 1
    fi
    sleep 1
done

/usr/local/sbin/rt7-healthcheck
docker info --format \
    'cgroup={{.CgroupDriver}} version={{.ServerVersion}} storage={{.Driver}}'
test "$(ps -o comm= -p "$(cat /run/docker.pid)")" = dockerd
test -s /run/sshd.pid
test "$(ps -o comm= -p "$(cat /run/sshd.pid)")" = sshd
echo 'ARM64 SSH/Docker smoke test passed'

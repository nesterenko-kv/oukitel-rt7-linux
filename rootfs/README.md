# Debian root filesystem

This directory defines the first headless Debian ARM64 userspace. It is based
on the pinned official Debian 12 ARM64 image and the Debian archive snapshots
from 2026-08-24. Generated images and device-specific SSH keys remain in the
private sibling work directory.

The image contains:

- OpenSSH with passwords and root login disabled;
- Debian's `docker.io`, containerd, and runc packages;
- systemd for a later standalone boot;
- `rt7-chroot-start` for the first Android-assisted boot;
- nftables/iptables, iproute2, kmod, and basic recovery tools.

Docker initially uses the legacy iptables frontend. It is the better-tested
path on the stock-derived Linux 4.19 kernel; nftables userspace remains
installed for later migration.

The `rt7` account is locked until an SSH public key is provisioned. Host SSH
keys are intentionally deleted at build time and generated on the tablet.

Build, smoke-test, and export the ARM64 root filesystem from the repository
root:

```powershell
./scripts/build-rootfs.ps1
```

QEMU smoke tests can run the ARM64 userspace on Docker Desktop. They validate
the package architecture and actually start ARM64 `sshd` and `dockerd` with
Docker data on an ext4 loop filesystem. They do not prove that the tablet
kernel and hardware work.

The current keyless rootfs tar was reproduced byte-for-byte across two clean
exports:

```text
SHA256  8b6c5aea5d623f03eda1d45ccf14c3ccbe2a5e609afb5cb9ce9b1e9c76845483
Size    407961600 bytes
```

After exporting the BuildKit root filesystem tar into the private work
directory, package it as a writable ext4 image:

```powershell
docker compose build rootfs-packager
docker compose run --rm rootfs-packager
```

The packager injects only the private work directory's public SSH key. It uses
a fixed filesystem UUID, disables the post-4.19 `orphan_file` feature, runs a
read-only `e2fsck`, verifies key ownership/mode, and refuses to overwrite an
existing image. The resulting hash is intentionally device-owner-specific
because the public key is part of the filesystem. The raw image defaults to
4 GiB and can later be enlarged with `resize2fs`.

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

`smoke-test-recovery-handoff.sh` additionally runs the stock recovery's ARM64
toybox shell and validates the complete loop-mount/chroot handoff into a
disposable Debian image. It still cannot emulate the MediaTek boot chain,
SELinux transition, USB gadget, or tablet peripherals.

The current keyless rootfs tar was reproduced byte-for-byte across two clean
exports:

```text
SHA256  db3b8f1b20ecba8502f2d8edf1a0b02e916b083432fc38d0bc674fc91e5fb01c
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

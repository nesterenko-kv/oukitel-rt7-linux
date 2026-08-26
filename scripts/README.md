# Tooling

Host-side scripts must default to read-only inspection. Any command capable of
flashing, erasing, or unlocking a device must require an explicit target and a
separate confirmation.

The kernel preparation and configuration scripts run inside the reproducible
builder container from the repository root:

```sh
docker compose build kernel-builder
docker compose run --rm kernel-builder /project/scripts/prepare-kernel-source.sh
docker compose run --rm kernel-builder /project/scripts/merge-kernel-config.sh
docker compose run --rm kernel-builder /project/scripts/fetch-moby-check-config.sh
docker compose run --rm kernel-builder /project/scripts/audit-kernel-config.sh
docker compose run --rm kernel-builder /project/scripts/prepare-toolchain.sh
docker compose run --rm kernel-builder /project/scripts/prepare-android-boot-tools.sh
docker compose run --rm kernel-builder /project/scripts/apply-kernel-patches.sh
docker compose run --rm kernel-builder /project/scripts/build-kernel.sh
```

The build script fixes kernel build identity, timestamp, and debug-info output
paths for reproducibility. `Image`, `Image.gz`, `System.map`, the resolved
`kernel.config`, and `SHA256SUMS` are written under
`../oukitel-rt7-linux-work/build/kernel/artifacts/`, never to the public tree.

`build-test-boot-image.py` performs an offline safety gate before replacing a
kernel: the pinned tools must reproduce the stock boot payload byte-for-byte,
then the custom image must preserve the original ramdisk, DTB, and all header
arguments. Its required output name includes `unsigned-do-not-flash`, and the
script refuses to write build artifacts into the public repository.

`capture-recovery-baseline.py` runs only in the `recovery-reader` container. It
prints a fixed read-only plan by default and needs `--execute` before it opens a
USB device. It cannot select arbitrary partitions or accept arbitrary
mtkclient commands; see `docs/recovery.md`.

`attach-rt7-usb.ps1` validates that a selected usbipd-win BUSID belongs to an
RT7/MediaTek device. It is a dry run unless `-Execute` is provided.

`build-rootfs.ps1` builds the pinned Debian ARM64 image, runs the privileged
ext4/OverlayFS SSH and Docker smoke test, and exports the rootfs tar into the
private work directory. It refuses to overwrite an existing artifact.

`prepare-recovery-ramdisk.sh` injects the owner's ADB public key into the
pinned stock recovery ramdisk and validates the personalized archive. The
result stays private. `rt7-recovery-linux-start.sh` mounts a transferred ext4
image and starts Debian manually; `start-recovery-linux.ps1` performs the
guarded transfer through the existing `rt7-adb` Docker server, hash check, ADB
port forward, and SSH/Docker health check.

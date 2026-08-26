# Tooling

Host-side scripts must default to read-only inspection. Any command capable of
flashing, erasing, or unlocking a device must require an explicit target and a
separate confirmation.

The pinned ADB/fastboot container is started with:

```sh
docker compose build android-tools
docker compose up -d android-tools
```

It keeps the controlling host key in the Compose-managed `adb-home` volume and
mounts only Docker Desktop's USB bus, with a cgroup rule limited to USB character
devices (major 189). The default clients are Ubuntu's pinned
34.0.4 usbfs build because the checksum-pinned Google libusb binaries return
`EIO` for the RT7 interface forwarded by usbipd-win; both variants remain in
the image for diagnosis. `inspect-rt7-fastboot.ps1` validates one
RT7-family product and runs only a fixed list of `getvar` queries plus
`flashing get_unlock_ability`; it has no boot, flash, erase, or unlock path.

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
mtkclient commands. It verifies complete primary/backup GPT structures and two
independent reads of every allowlisted artifact; see `docs/recovery.md`.

Its offline safety tests are:

```sh
python -m unittest discover -s tests -v
docker compose run --rm --entrypoint /opt/venv/bin/python recovery-reader \
    /project/tests/smoke_mtkclient_gpt_patch.py
docker compose run --rm --entrypoint /opt/venv/bin/python recovery-reader \
    /project/tests/smoke_mtkclient_usb_filter.py
pwsh -File tests/inspect-rt7-fastboot.Tests.ps1
```

`attach-rt7-usb.ps1` validates that a selected usbipd-win BUSID belongs to an
RT7/MediaTek device. It is a dry run unless `-Execute` is provided.
`wait-bind-rt7-brom.ps1` polls for the short-lived MediaTek preloader/BROM
identities (`0e8d:2000` and `0e8d:0003`) and, only when run elevated with
`-Execute`, shares and attaches those exact BUSIDs. Its explicit `-Force` mode
prevents the Windows COM driver from winning the short preloader handoff and is
reversible with `usbipd unbind`. Forced binding is performed only after an exact
MediaTek boot identity has been resolved to a connected BUSID; hardware-ID force
binding is intentionally avoided because usbipd-win 5.3 may persist it without
the requested forced flag. Elevation is checked only when a binding must be
created or replaced; an already forced identity can be attached from a normal
PowerShell process.

`build-rootfs.ps1` builds the pinned Debian ARM64 image, runs the privileged
ext4/OverlayFS SSH and Docker smoke test, and exports the rootfs tar into the
private work directory. It refuses to overwrite an existing artifact.

`prepare-recovery-ramdisk.sh` injects the owner's ADB public key into the
pinned stock recovery ramdisk and validates the personalized archive. The
result stays private. `rt7-recovery-linux-start.sh` mounts a transferred ext4
image and starts Debian manually; `start-recovery-linux.ps1` performs the
guarded transfer through the existing `rt7-adb` Docker server, hash check, ADB
port forward, and SSH/Docker health check.

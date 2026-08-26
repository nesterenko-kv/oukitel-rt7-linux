# Boot-chain baseline

This document records read-only observations. It does not authorize flashing
or bootloader unlocking.

## Running device

- Android build: `OUKITEL_P07_NFC_EEA_V04_20231205`
- Linux release: `4.19.191`
- Boot scheme: A/B partitions with a dynamic `super` partition
- Verified Boot state: green
- Bootloader state: locked

The exact installed `boot_a`, `vbmeta*`, and preloader images have not been
captured. A newer firmware package is therefore a useful reference but is not
yet a complete rollback path for the installed December 2023 build.

## Official V1.4.8 reference

The latest official Android 13 archive contains a 40 MiB `boot.img`, an 8 MiB
`dtbo.img`, three AVB metadata images, a scatter map, and `super.img`. Its
scatter map defines both A and B boot-chain partitions, but the update payload
populates the A-side entries only. That does not prove slot B is safe to use on
the running device.

The reference `boot.img` has:

- Android boot image header version 2 and 2 KiB pages;
- a gzip-compressed 12,725,131-byte ARM64 kernel;
- a 12,232,215-byte gzip ramdisk;
- one DT table entry, compatible with `mediatek,MT6853`;
- command line `bootopt=64S3,32N2,64N2 buildvariant=user`;
- kernel build `4.19.191`, compiled with Android clang 11.0.1 based on
  `clang-r383902`.

Strings in the same official V1.4.8 `lk.img` include the MediaTek fastboot
command handler `cmd_boot`, the `boot` command, download-buffer handling, and
the standard `flashing get_unlock_ability` / `flashing unlock` flow. This is
strong evidence that a nonpersistent `fastboot boot` experiment exists in the
reference LK. The exact installed December 2023 `lk_a` still has to be dumped
and checked before relying on that path.

Once the tablet is manually placed in fastboot and its USB device is attached
to Docker Desktop, `scripts/inspect-rt7-fastboot.ps1` queries the exact product,
slot, lock state, security state, maximum download size, and unlock ability.
The inspection helper contains no boot or persistent-write operation.

The extracted V1.4.8 kernel configuration has the same 5,870 symbols as the
running stock configuration. Only two symbol values differ: the newer image
adds two camera sensors and enables `CONFIG_ODM_BATTERY_ID_ADC`. This is strong
compatibility evidence for the selected source base, but it is not proof that a
locally built image is bootable.

## First safe boot experiment

Before any experiment, the project must have:

1. at least 80% battery;
2. an exact-device bootloader-unlock procedure;
3. verified copies of the running device's boot-critical metadata or an
   equivalent tested recovery route;
4. a reproducible kernel build and boot-image repack test;
5. a way to restore the original active slot from a host.

The reproducible kernel build and byte-identical stock payload round trip are
now complete. The exact rollback and host-restoration requirements are not.

Never flash `preloader`, `nvram`, `nvdata`, `persist`, `protect1`, or
`protect2` as part of Linux bring-up.

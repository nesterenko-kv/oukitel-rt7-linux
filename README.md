# Linux for OUKITEL RT7 TITAN 5G

Experimental, community-driven Linux enablement for the OUKITEL RT7 TITAN
5G (`P07_NFC_EEA`, MediaTek MT6853/Dimensity 720).

The initial target is a recoverable Debian ARM64 environment with SSH and a
native Docker Engine. Android may remain as the early hardware bootstrap while
device support is moved to Linux incrementally.

> [!WARNING]
> There is no flashable release yet. Do not flash images produced by this
> repository until the recovery procedure has been documented and tested on
> the exact device variant.

## Current target

- Device: OUKITEL RT7 TITAN 5G
- Android device: `P07_NFC_EEA`
- Board project: `tP758`
- SoC: MediaTek MT6853V/ZA
- Stock kernel: Linux 4.19.191
- Partition layout: A/B with dynamic partitions and AVB

## Progress

- Read-only, privacy-conscious device inventory collector
- Pinned Linux 4.19.191 MT6853-compatible kernel and external module sources
- Captured and hashed stock kernel configuration
- Audited stock Docker support with Moby's `check-config.sh`
- Required and recommended Docker kernel configuration fragments
- Merged configuration passes every generally necessary Moby Docker check
- Exact official Android clang-r383902 toolchain pinned and verified
- Reproducible ARM64 Linux 4.19.191 compile baseline built successfully
- Official same-variant Android 13 recovery reference identified
- Known public-source omissions tracked explicitly in `docs/source-gaps.md`

The first successful `Image` is 29,151,232 bytes and reproduced the same
SHA-256 across two consecutive builds. See `docs/kernel-build.md` for hashes,
validation, and the remaining blockers. It is a research artifact, not a
flashable release.

## Repository policy

This public repository contains only redistributable material:

- source code and build scripts;
- kernel configuration fragments and patches;
- documentation and hardware notes;
- URLs, hashes, and reproducible download instructions.

Stock firmware, extracted proprietary binaries, device dumps, signing keys,
serial numbers, IMEI data, and build output must stay outside this repository.
The sibling local directory `../oukitel-rt7-linux-work/` is reserved for those
artifacts.

## Layout

- `configs/` - kernel and system configuration fragments
- `containers/` - pinned local build environments
- `docs/` - device, build, recovery, and porting documentation
- `patches/` - reviewable patches against upstream source trees
- `rootfs/` - reproducible Debian root filesystem definitions
- `scripts/` - host-side build, inspection, and packaging tools

## Windows build environment

The kernel cannot be checked out directly on NTFS because the upstream tree
contains filenames reserved by Windows. It also references an external OPPO
module tree through symbolic links. Use the two Docker named volumes defined in
`compose.yaml`:

```sh
docker compose build kernel-builder
docker compose run --rm kernel-builder /project/scripts/prepare-kernel-source.sh
docker compose run --rm kernel-builder /project/scripts/merge-kernel-config.sh
docker compose run --rm kernel-builder /project/scripts/fetch-moby-check-config.sh
docker compose run --rm kernel-builder /project/scripts/audit-kernel-config.sh
docker compose run --rm kernel-builder /project/scripts/prepare-toolchain.sh
docker compose run --rm kernel-builder /project/scripts/build-kernel.sh
```

Set `RT7_WORK_DIR` when the private sibling work directory is stored somewhere
other than `../oukitel-rt7-linux-work`.

## Safety rules

- Preserve stock Android in slot A until rollback has been tested.
- Prefer temporary booting; use slot B only when temporary boot is unavailable.
- Never publish or overwrite `preloader`, NVRAM/NVDATA, IMEI, persist, or
  protect partitions.
- Do not flash while the battery is below 80%.
- Verify every downloaded and generated artifact before use.

## License

The project license has not been selected yet. GPL-2.0-only is the proposed
default because the project will contain Linux kernel patches.

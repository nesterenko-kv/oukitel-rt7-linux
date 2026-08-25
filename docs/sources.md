# Source and firmware provenance

Machine-readable pins are stored in [`sources.lock`](../sources.lock). Large
source checkouts, toolchains, firmware archives, and extracted images remain in
the private sibling work directory.

## Kernel source base

The initial source base is OPPO's public MediaTek Android 13 kernel tree at
commit `f1ac3e53f433c6b68e2f6f37191e488d2bd41557` on branch
`oppo/mtk_t_13.0.0`:

<https://github.com/oppo-source/android_kernel_oppo_mtk_4.19>

At the pinned commit:

- the kernel Makefile identifies Linux 4.19.191;
- `build.config.mtk.aarch64` selects LLVM and `clang-r383902`;
- the tree contains MT6853 platform support;
- every symbol in `configs/docker-required.config` exists in its Kconfig files.

This is a compatible starting point, not proof that it is the complete
corresponding source for the RT7 board-specific stock kernel.

The kernel repository refers to code supplied by OPPO's external MediaTek 4.19
module tree. That companion source is pinned at commit
`aa8b40a3f646040b2c58b695373407731718daed` on the matching
`oppo/mtk_t_13.0.0` branch:

<https://github.com/oppo-source/android_kernel_modules_oppo_mtk_4.19>

The builder keeps both repositories in Linux-native Docker volumes and
recreates the links normally supplied by a full Android source checkout.

## Stock kernel configuration

`/proc/config.gz` was captured read-only from the running stock system and kept
outside Git. Its SHA-256 is:

```text
f88570fb45bb35f01aadf088393cff341ef3d00a67995f162f38d1e11f28df2d
```

The pinned Moby audit reports seven missing generally necessary symbols in the
stock kernel. `configs/docker-required.config` enables those symbols and the
IPVS dependencies needed by one of them. Recommended but nonessential features
are kept separate in `configs/docker-recommended.config`.

After Kconfig dependency resolution, the merged configuration passes every
"Generally Necessary" check in the pinned Moby audit. AppArmor and the optional
Btrfs/ZFS storage drivers remain absent; SELinux and OverlayFS are enabled.

## Firmware

OUKITEL's public download catalog currently links the RT7 TITAN 5G Android 13
folder containing:

```text
TP758_OQ_P07_NFC_6853_T0_EEA_V1.4.8_S251017.zip
```

The downloaded 2,585,630,382-byte archive passes a complete 7-Zip CRC test.
Its SHA-256 is:

```text
a54838940bd9d92fbce9aa2fd155f00d9973baecf60f9f273b769f8d28dbcd62
```

This matches the device's `TP758`, `P07 NFC`, `MT6853`, `T0`, and `EEA`
identifiers, but it is newer than the installed build
`OUKITEL_P07_NFC_EEA_V04_20231205`.

The expected package corresponding to the installed build is:

```text
TP758_OQ_P07_NFC_6853_T0_EEA_V1.2.9_S231205.zip
```

That older package is not currently present in OUKITEL's public Google Drive
folder. A third-party copy must not be trusted for recovery until its contents,
signatures, and partition metadata have been compared with an official package
or a verified device capture.

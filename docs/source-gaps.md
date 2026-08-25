# Public source gaps

The selected OPPO source is much closer to the RT7 firmware than a generic
upstream kernel, but it is not the exact OUKITEL source release. Buildable does
not mean every tablet peripheral is supported.

## Camera sensors

The stock RT7 configuration names these sensor directories:

```text
imx582_mipi_raw
s5kgd1_mipi_raw
bf2253_mipi_raw
imx350_mipi_raw
gc02m2_mipi_raw
gc5035sub_mipi_raw
gc8034_mipi_raw
gc5035_mipi_raw
```

Only `imx350_mipi_raw` and `gc5035_mipi_raw` exist in the pinned public kernel
tree. `configs/source-compat.config` therefore limits the build to those two
directories. This is expected to leave some or all RT7 cameras unavailable; it
must not be presented as full hardware support.

Missing vendor drivers should be replaced only with legally redistributable
source or a clean implementation. Binary-only camera components remain outside
the repository.

## NFC driver duplication

The stock configuration enables both `CONFIG_NFC_CHIP_SUPPORT` and
`CONFIG_ST_NFC_CHIP_SUPPORT`, but this public tree maps them to two independent
ST21NFC implementations that export the same symbols. The running RT7 exposes
the `power_stats` sysfs attribute implemented by `drivers/nfc/st21nfc-i2c`.
`configs/source-compat.config` therefore keeps that driver and disables the
older `drivers/misc/mediatek/nfc` copy to avoid duplicate symbols at link time.

## OPPO feature injection

The public kernel's top-level build injects a broad set of ColorOS feature
macros unconditionally. The OUKITEL stock configuration does not enable their
matching Hans, charging, project-info, or device-info implementations. Several
files in the drop also use ordinary comments where preprocessor guards were
apparently intended, so simply disabling the macros is not a buildable path.

For a compile baseline, `scripts/merge-kernel-config.sh` derives only the
`CONFIG_OPLUS_*` selections from the pinned MT6853 defconfig and overlays them
on the stock RT7 configuration. This satisfies the source tree's internal
assumptions, but it may compile device-specific OPPO behavior that is wrong for
the RT7. The resulting image is a research artifact, not a boot candidate,
until those subsystems are audited against the RT7 device tree and hardware.

## Compile compatibility patches

The pinned trees also assume pieces of a full ColorOS checkout that are absent
or inconsistent in the public repositories. The ordered patches provide only
the minimum link-time compatibility needed by the stock non-WALT, non-SIA
configuration. They connect an existing MT6853 EEPROM implementation and add
safe disabled-feature fallbacks; they do not claim to implement missing RT7
hardware.

These patches are sufficient to produce an ARM64 `Image`, but all OPPO charger,
scheduler, health, audio, and project-info paths still require an RT7-specific
runtime audit before the image can be treated as bootable.

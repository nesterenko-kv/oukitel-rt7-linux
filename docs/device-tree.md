# Device-tree baseline

The official V1.4.8 boot image and `dtbo.img` each contain one Android DT table
entry. The entries have no board ID or revision selector, so the only overlay
is applied to the only base tree.

```text
base DTB:       6aee33f20be015b37779551ae3af9e13554efd4ebd07cd133c76a3ce112ac716
DTBO overlay:   470f798d2eef0be5ce2ac71a1eccc6aaf1f51fb1093c55bbdab74dc64b3b11a3
merged DTB:     4faece46398b657660fe4b875aa7c591c419730ee328b237f3e34d5583f7e3ad
```

The pinned `fdtoverlay` operation succeeds. The merged tree is kept in the
private work directory; proprietary firmware-derived blobs are not committed.

## Relevant bindings

The merged tree confirms:

- MT6853 CPU, UFS, integrated MediaTek Wi-Fi/Bluetooth, and USB controllers;
- an MT6359 primary PMIC and MT6360 Type-C/charging/secondary-PMIC functions;
- a 1200x1920 Goodix touch configuration and Goodix fingerprint binding;
- an enabled DSI controller with three possible panel nodes;
- board GPIO and I2C assignments for NFC, cameras, regulators, and Type-C.

The DSI graph currently points at `tft,hx8279,vdo`; the overlay also contains
`nt36672a,rt4801,vdo` and `truly,td4330,vdo`. The public source contains drivers
for the latter two but no HX8279 panel driver. The bootloader also supplies an
LCM name at runtime, so the actual fitted panel must be read from the running
device before display support is claimed.

The headless bring-up path deliberately retains the stock DTB and DTBO rather
than compiling a guessed replacement. Display, cameras, audio, and charging
remain nonessential for the first SSH/Docker boot but must be audited before a
general-purpose Linux release.

# Read-only recovery baseline

No custom image should be booted until the exact installed boot chain has been
captured from the tablet and validated. The official V1.4.8 archive is a useful
reference, but the tablet currently runs the older December 2023 build.

## Recovery transport

The supported Windows path uses `usbipd-win` to attach the MediaTek USB device
to the `docker-desktop` WSL distribution. `mtkclient` then runs inside a pinned
Linux container with no runtime network. This avoids installing the old UsbDk
filter driver on the Windows host.

The pinned `mtkclient` v2.1.4 source contains an explicit MT6853 configuration:

- hardware code `0x996`;
- DA code `0x6853`;
- XFLASH mode and `mt6853_payload.bin`;
- MT6853 support inside the bundled `MTK_DA_V5.bin`.

This is strong tool-side evidence, not proof that the tablet accepts the DA.
The first device connection must remain read-only.

## Captured scope

`scripts/capture-recovery-baseline.py` has a fixed command plan. It reads:

- primary and backup GPT;
- `boot`, `dtbo`, `lk`, `tee`, and all three `vbmeta` partitions for slots A
  and B;
- `misc`, `para`, and `seccfg` for A/B and lock-state recovery;
- the first 512 KiB from UFS LU0 and LU1 as the two preloader copies.

It deliberately excludes `userdata`, `metadata`, `nvram`, `nvdata`, `persist`,
`protect1`, and `protect2`. All results stay under the private sibling work
directory and are hashed after exact-size validation.

## Host preparation and dry run

On Windows, verify that Docker Desktop and usbipd-win are available:

```powershell
usbipd list
docker compose build recovery-reader
docker compose run --rm recovery-reader
```

The final command prints the exact read-only plan without touching a device.
The runtime container has no network access.

## Physical capture

When the tablet is connected in a MediaTek preloader/BROM mode, note its BUSID
from `usbipd list`. Validate the target first, then attach it with automatic
reconnect:

```powershell
./scripts/attach-rt7-usb.ps1 -BusId <BUSID>
./scripts/attach-rt7-usb.ps1 -BusId <BUSID> -Execute
docker compose run --rm recovery-reader --execute
```

The helper refuses a BUSID unless Windows reports a MediaTek/RT7 USB device. If
the device has not been shared previously, it prints the one elevated `bind`
command required by usbipd-win. Attaching and detaching are reversible host
operations; neither writes tablet flash.

Entering BROM usually requires a powered-off device and a volume-key chord
while connecting USB. Do not use any `mtkclient` write, erase, unlock, or
`seccfg` modification command during this milestone.

Successful completion produces `SHA256SUMS.txt` beside the private dumps. Save
a second offline copy before any bootloader unlock or boot experiment.

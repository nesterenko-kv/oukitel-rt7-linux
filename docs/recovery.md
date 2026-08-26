# Read-only recovery baseline

No custom image should be booted until the exact installed boot chain has been
captured from the tablet and validated. The official V1.4.8 archive is a useful
reference, but the tablet currently runs the older December 2023 build.
During the 2026-08-26 audit, OUKITEL's current public
[RT7 TITAN 5G/A13 folder](https://drive.google.com/drive/folders/1VtYQelAQStPexSykWkVSRKdJDMZ2AaBX)
listed only V1.4.8, not the installed V1.2.9/S231205 archive. Community mirrors
are not accepted as the sole rollback source.

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

- complete primary and backup GPT spans, including both partition-entry arrays;
- `boot`, `dtbo`, `lk`, `tee`, and all three `vbmeta` partitions for slots A
  and B;
- `misc`, `para`, and `seccfg` for A/B and lock-state recovery;
- the first 512 KiB from UFS LU0 and LU1 as the two preloader copies.

It deliberately excludes `userdata`, `metadata`, `nvram`, `nvdata`, `persist`,
`protect1`, and `protect2`. All results stay under the private sibling work
directory. Every artifact is read twice during the same DA session; the two
copies must be byte-identical.

Pinned mtkclient v2.1.4 normally writes a truncated primary GPT and labels a
slice of that data as `gpt_backup.bin`. The recovery-reader image applies the
reviewable `containers/mtkclient/mtkclient-gpt-capture.patch`, which reads both
complete GPT spans from the LBAs declared by the primary header. The validator
then checks both header CRCs, both partition-array CRCs, mirrored LBA pointers,
identical primary/backup entries, partition sizes, boot-image magic, and the
two independent read passes.

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

The DA and exploit path executes volatile code in tablet RAM and may reset the
device; "read-only" here specifically means that the fixed command allowlist
contains no persistent-storage write, erase, unlock, or patch operation.

The wrapper also fixes the USB transport to the real MediaTek BootROM identity
`0e8d:0003`. The RT7 can expose an Android META composite interface as
`0e8d:200e`; that interface contains ADB and CDC endpoints and is deliberately
rejected instead of being mistaken for a preloader.

Successful completion produces `pass1/`, `pass2/`, `SHA256SUMS.txt`, and a
parsed `capture-manifest.json` under the private output directory. Save the
whole verified directory to a second offline medium before any bootloader
unlock or boot experiment.

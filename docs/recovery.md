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

Windows treats the short-lived `0e8d:2000` preloader and `0e8d:0003` BootROM
identities as devices distinct from Android. To catch, share, and attach both
transports without racing Device Manager, start this helper from an elevated
PowerShell before connecting the powered-off tablet:

```powershell
./scripts/wait-bind-rt7-brom.ps1 -Execute -Force
```

It accepts exactly one connected `0e8d:2000` or `0e8d:0003` device, binds only
its resolved BUSID, attaches it to Docker Desktop, follows a preloader-to-BROM
reconnect, and exits after BootROM is attached. It never opens the device or
sends it a USB command itself.

The helper deliberately resolves the connected USB identity first and invokes
`usbipd bind --force --busid <BUSID>`. Do not replace that operation with
`--force --hardware-id`: usbipd-win 5.3 may return success for the latter while
persisting `IsForced=false`, which lets the Windows serial driver win the next
sub-second preloader handoff.

The default 25 ms polling interval is intentional: the RT7's `0e8d:0003`
BootROM identity can disappear into the next boot mode before usbipd-win's
multi-second `--auto-attach` retry observes it. Keep the helper running until it
reports that BootROM has been attached; do not run a second auto-attach loop for
the same BUSID in parallel.

`-Force` is explicit because it temporarily prevents Windows from claiming the
two short-lived serial interfaces. This is needed when the host COM driver wins
the sub-second race; it affects only the host binding and is reversible with
`usbipd unbind --hardware-id 0e8d:2000` and the equivalent `0e8d:0003` command.

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

The wrapper fixes USB discovery to MediaTek's vendor and mtkclient's known boot
transport PIDs. This lets it follow the RT7 from the short-lived preloader
(`0e8d:2000`) into BootROM (`0e8d:0003`) while excluding Android's META
composite interface (`0e8d:200e`) and all non-MediaTek USB vendors.

Successful completion produces `pass1/`, `pass2/`, `SHA256SUMS.txt`, and a
parsed `capture-manifest.json` under the private output directory. Save the
whole verified directory to a second offline medium before any bootloader
unlock or boot experiment.

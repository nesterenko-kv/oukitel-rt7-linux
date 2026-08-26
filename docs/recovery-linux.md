# Nonpersistent recovery Linux handoff

The first on-device milestone intentionally avoids Android userdata,
standalone systemd boot, and persistent installation. A personalized developer
boot image enters the stock recovery userspace with:

- the Docker-enabled MT6853 Linux 4.19 kernel;
- the stock recovery DTB and recovery files;
- only the controlling host's ADB public key added to the ramdisk;
- `selinux=0` for this recovery boot only.

After recovery ADB appears, `start-recovery-linux.ps1` uses the existing
`rt7-adb` Docker server to transfer a 1 GiB ext4 image to `/tmp`, validates its
SHA-256 on the tablet, runs the public handoff script, forwards local TCP port
22007 to SSH port 22, and executes the Debian SSH/Docker health check. The
image lives in RAM and disappears at reboot. Normal Android remains untouched.

The handoff path has been exercised offline using the actual ARM64 toybox from
the pinned stock recovery ramdisk. The test validated loop setup, ext4 mount,
recursive `/dev`, `/proc`, `/sys`, PTY and cgroup binds, Debian chroot, SSH host
key generation, and a running native Docker daemon using OverlayFS.

The recovery-test kernel was also rebuilt from scratch in two distinct output
directories. Both `Image` and `Image.gz` were byte-identical; the reproducible
compressed kernel SHA-256 is
`83c0c0462df3d0a8c1bd6fb63c63452560701b8a55d267f9696c3a2254ced430`.

## Mandatory on-device gates

The generated boot payload is unsigned, personalized, and not a flashable
release. Before any boot attempt:

1. Capture the exact installed GPT and both-slot boot-chain partitions with
   the read-only procedure in `docs/recovery.md`.
2. Verify the tablet's actual installed `boot_a`, `boot_b`, DTBO, VBMeta, LK,
   and preloader hashes rather than assuming the public V1.4.8 package matches.
3. Confirm whether the bootloader implements nonpersistent `fastboot boot`.
4. Unlock only after accepting the Android userdata wipe and confirming the
   rollback files are readable.
5. Keep stock Android in slot A. Do not write preloader, NVRAM/NVDATA, persist,
   protect, metadata, or userdata.

If `fastboot boot` is rejected, do not convert this experiment into an
inactive-slot flash until the exact slot state and rollback path have been
captured and tested.

Once a temporary recovery boot is active and ADB reports `ro.bootmode` as
`recovery` and `ro.hardware` as `mt6853`, the guarded host command is:

```powershell
./scripts/start-recovery-linux.ps1
```

The script refuses normal Android mode or unexpected hardware. The first test
uses SSH through ADB forwarding; Wi-Fi, LTE, display integration, suspend, and
persistent root storage are later milestones.

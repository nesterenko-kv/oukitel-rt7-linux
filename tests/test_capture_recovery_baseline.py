from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock
import zlib


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts/capture-recovery-baseline.py"
SPEC = importlib.util.spec_from_file_location("capture_recovery_baseline", SCRIPT)
assert SPEC and SPEC.loader
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


SECTOR_SIZE = 512
DISK_SECTORS = 4096
FIRST_USABLE_LBA = 34
LAST_USABLE_LBA = DISK_SECTORS - 34
ENTRY_COUNT = 128
ENTRY_SIZE = 128
ENTRY_SECTORS = ENTRY_COUNT * ENTRY_SIZE // SECTOR_SIZE
DISK_GUID = bytes.fromhex("00112233445566778899aabbccddeeff")


def make_entries(partitions: tuple[tuple[str, int], ...]) -> bytes:
    entries = bytearray(ENTRY_COUNT * ENTRY_SIZE)
    next_lba = FIRST_USABLE_LBA
    for index, (partition_name, sectors) in enumerate(partitions):
        entry = bytearray(ENTRY_SIZE)
        entry[:16] = bytes.fromhex("af3dc60f838472478e793d69d8477de4")
        entry[16:32] = (index + 1).to_bytes(16, "little")
        struct.pack_into("<QQQ", entry, 32, next_lba, next_lba + sectors - 1, 0)
        name = partition_name.encode("utf-16-le")
        entry[56 : 56 + len(name)] = name
        entries[index * ENTRY_SIZE : (index + 1) * ENTRY_SIZE] = entry
        next_lba += sectors
    return bytes(entries)


def make_header(
    *, current_lba: int, backup_lba: int, entry_start_lba: int, entries_crc: int
) -> bytes:
    header = bytearray(capture.GPT_HEADER.size)
    capture.GPT_HEADER.pack_into(
        header,
        0,
        b"EFI PART",
        0x00010000,
        capture.GPT_HEADER.size,
        0,
        0,
        current_lba,
        backup_lba,
        FIRST_USABLE_LBA,
        LAST_USABLE_LBA,
        DISK_GUID,
        entry_start_lba,
        ENTRY_COUNT,
        ENTRY_SIZE,
        entries_crc,
    )
    struct.pack_into("<I", header, 16, zlib.crc32(header) & 0xFFFFFFFF)
    return bytes(header).ljust(SECTOR_SIZE, b"\0")


def make_gpt_pair(
    partitions: tuple[tuple[str, int], ...] = (("boot_a", 64),),
) -> tuple[bytes, bytes]:
    entries = make_entries(partitions)
    entries_crc = zlib.crc32(entries) & 0xFFFFFFFF

    primary = bytearray(FIRST_USABLE_LBA * SECTOR_SIZE)
    primary[0x1FE:0x200] = b"\x55\xaa"
    primary[SECTOR_SIZE : 2 * SECTOR_SIZE] = make_header(
        current_lba=1,
        backup_lba=DISK_SECTORS - 1,
        entry_start_lba=2,
        entries_crc=entries_crc,
    )
    primary[2 * SECTOR_SIZE : (2 + ENTRY_SECTORS) * SECTOR_SIZE] = entries

    backup_start_lba = DISK_SECTORS - 1 - ENTRY_SECTORS
    backup = bytearray((ENTRY_SECTORS + 1) * SECTOR_SIZE)
    backup[: ENTRY_SECTORS * SECTOR_SIZE] = entries
    backup[ENTRY_SECTORS * SECTOR_SIZE :] = make_header(
        current_lba=DISK_SECTORS - 1,
        backup_lba=1,
        entry_start_lba=backup_start_lba,
        entries_crc=entries_crc,
    )
    return bytes(primary), bytes(backup)


class GptValidationTests(unittest.TestCase):
    def test_complete_mirrored_gpt_is_accepted(self) -> None:
        primary, backup = make_gpt_pair()
        parsed = capture.parse_gpt_pair(primary, backup)
        self.assertEqual(parsed["sector_size"], SECTOR_SIZE)
        self.assertEqual(parsed["backup_lba"], DISK_SECTORS - 1)
        self.assertEqual(parsed["partitions"]["boot_a"]["size"], 64 * SECTOR_SIZE)

    def test_truncated_primary_span_is_rejected(self) -> None:
        primary, backup = make_gpt_pair()
        with self.assertRaisesRegex(ValueError, "primary GPT span has size"):
            capture.parse_gpt_pair(primary[:-SECTOR_SIZE], backup)

    def test_corrupt_backup_entries_are_rejected(self) -> None:
        primary, backup = make_gpt_pair()
        corrupt = bytearray(backup)
        corrupt[0] ^= 0xFF
        with self.assertRaisesRegex(ValueError, "backup GPT entry-array CRC mismatch"):
            capture.parse_gpt_pair(primary, bytes(corrupt))


class CaptureManifestTests(unittest.TestCase):
    def test_two_matching_passes_produce_verified_manifest(self) -> None:
        partition_sizes = {name: SECTOR_SIZE for name in capture.PARTITIONS}
        primary, backup = make_gpt_pair(
            tuple((name, 1) for name in partition_sizes)
        )
        magic = {
            "boot_a": b"ANDROID!",
            "dtbo_a": b"\xd7\xb7\xab\x1e",
            "vbmeta_a": b"AVB0",
            "vbmeta_system_a": b"AVB0",
            "vbmeta_vendor_a": b"AVB0",
        }

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            for pass_name in capture.CAPTURE_PASSES:
                directory = output / pass_name
                directory.mkdir()
                (directory / "gpt.bin").write_bytes(primary)
                (directory / "gpt_backup.bin").write_bytes(backup)
                for name in partition_sizes:
                    payload = bytearray(SECTOR_SIZE)
                    prefix = magic.get(name, name.encode("ascii"))
                    payload[: len(prefix)] = prefix
                    (directory / f"{name}.bin").write_bytes(payload)
                preloader = bytearray(0x80000)
                preloader[:8] = b"PRELOAD!"
                (directory / "preloader_lu0.bin").write_bytes(preloader)
                (directory / "preloader_lu1.bin").write_bytes(preloader)

            with mock.patch.object(capture, "PARTITIONS", partition_sizes):
                capture.validate_capture(output)

            manifest = json.loads((output / "capture-manifest.json").read_text())
            self.assertEqual(manifest["format"], 2)
            self.assertEqual(
                manifest["artifacts"]["boot_a.bin"]["verified_copies"], 2
            )
            self.assertEqual(manifest["gpt"]["partitions"]["boot_a"]["size"], 512)
            self.assertEqual(
                len((output / "SHA256SUMS.txt").read_text().splitlines()),
                2 * len(manifest["artifacts"]),
            )

            second_boot = output / "pass2/boot_a.bin"
            corrupted = bytearray(second_boot.read_bytes())
            corrupted[-1] ^= 1
            second_boot.write_bytes(corrupted)
            with mock.patch.object(capture, "PARTITIONS", partition_sizes):
                with self.assertRaisesRegex(
                    SystemExit, "independent reads differ for boot_a.bin"
                ):
                    capture.validate_capture(output)


class ReadOnlyPlanTests(unittest.TestCase):
    def test_plan_reads_two_independent_passes(self) -> None:
        output = Path("/rt7-work/recovery/test-capture")
        plan = capture.build_plan(output)
        capture.validate_read_only_plan(plan, output)
        self.assertEqual(sum(command.startswith("gpt ") for command in plan), 2)
        self.assertTrue(
            any(str(output / "pass1" / "boot_a.bin") in command for command in plan)
        )
        self.assertTrue(
            any(str(output / "pass2" / "boot_a.bin") in command for command in plan)
        )
        self.assertFalse(any(command.startswith(("w ", "wo ", "e ")) for command in plan))

    def test_write_command_cannot_pass_allowlist(self) -> None:
        output = Path("/rt7-work/recovery/test-capture")
        plan = capture.build_plan(output)
        plan[1] = plan[1].replace("r ", "w ", 1)
        with self.assertRaisesRegex(SystemExit, "fixed allowlist"):
            capture.validate_read_only_plan(plan, output)

    def test_transport_accepts_only_mediatek_boot_vendor(self) -> None:
        command = capture.build_mtk_command(
            Path("/opt/mtkclient"),
            Path("/private/reference-preloader.bin"),
            Path("/private/read-only-plan.txt"),
        )
        self.assertEqual(
            command[2:4],
            ["--vid", "0x0E8D"],
        )
        self.assertNotIn("--pid", command)
        self.assertNotIn("0x200e", [argument.lower() for argument in command])

    def test_usb_debug_mode_is_explicit(self) -> None:
        normal = capture.build_mtk_command(
            Path("/opt/mtkclient"),
            Path("/private/reference-preloader.bin"),
            Path("/private/read-only-plan.txt"),
        )
        debug = capture.build_mtk_command(
            Path("/opt/mtkclient"),
            Path("/private/reference-preloader.bin"),
            Path("/private/read-only-plan.txt"),
            debug_usb=True,
        )
        self.assertNotIn("--debugmode", normal)
        self.assertIn("--debugmode", debug)
        self.assertEqual(
            [argument for argument in debug if argument != "--debugmode"],
            normal,
        )


if __name__ == "__main__":
    unittest.main()

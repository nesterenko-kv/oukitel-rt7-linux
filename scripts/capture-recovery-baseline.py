#!/usr/bin/env python3
"""Create or execute the fixed read-only RT7 recovery capture plan."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import zlib


MTKCLIENT_COMMIT = "4d29037104b1f378abedcace89ccd48e8a8aa314"
MTKCLIENT_GPT_PATCH_MARKER = "RT7_CAPTURE_GPT_V1"
BROM_VID = "0x0E8D"
BROM_PID = "0x0003"
PRELOADER_SHA256 = "e76b3bc6f70f263026088c19665d25b900956832efcc448804be921cc765fa26"
DEFAULT_PRELOADER = (
    "/rt7-work/firmware/extracted/V1.4.8/"
    "TP758_OQ_P07_NFC_6853_T0_EEA_V1.4.8_S251017/"
    "preloader_tp758_oq_p07_nfc_6853_t0_eea.bin"
)
DEFAULT_OUTPUT = "/rt7-work/recovery/rt7-installed-v04-20231205"
CAPTURE_PASSES = ("pass1", "pass2")
GPT_HEADER = struct.Struct("<8sIIIIQQQQ16sQIII")

# These contain the boot chain and A/B state only. Deliberately excluded:
# userdata, metadata, nvram, nvdata, persist, protect1, and protect2.
PARTITIONS = {
    "misc": 0x80000,
    "para": 0x80000,
    "seccfg": 0x800000,
    "vbmeta_a": 0x800000,
    "vbmeta_system_a": 0x800000,
    "vbmeta_vendor_a": 0x800000,
    "vbmeta_b": 0x800000,
    "vbmeta_system_b": 0x800000,
    "vbmeta_vendor_b": 0x800000,
    "lk_a": 0x200000,
    "boot_a": 0x2800000,
    "dtbo_a": 0x800000,
    "tee_a": 0x500000,
    "lk_b": 0x200000,
    "boot_b": 0x2800000,
    "dtbo_b": 0x800000,
    "tee_b": 0xB00000,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_path(value: str, label: str) -> Path:
    if any(character.isspace() for character in value) or any(
        character in value for character in ",;"
    ):
        raise SystemExit(f"{label} cannot contain whitespace, commas, or semicolons: {value}")
    return Path(value).resolve()


def validate_tool(mtk_root: Path) -> None:
    actual = subprocess.check_output(
        ["git", "-C", str(mtk_root), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual != MTKCLIENT_COMMIT:
        raise SystemExit(f"Unexpected mtkclient commit: {actual}")

    probe = (
        "from mtkclient.config.brom_config import hwconfig; "
        "c=hwconfig[0x996]; "
        "assert c.dacode==0x6853 and c.name=='MT6853'"
    )
    subprocess.run([sys.executable, "-c", probe], cwd=mtk_root, check=True)

    handler = mtk_root / "mtkclient/Library/DA/mtk_da_handler.py"
    if handler.read_text(encoding="utf-8").count(MTKCLIENT_GPT_PATCH_MARKER) != 1:
        raise SystemExit("Pinned mtkclient is missing the verified GPT capture patch")


def build_plan(output: Path) -> list[str]:
    # Use one command per partition. Upstream v2.1.4 retains the first detected
    # size inside a comma-separated `r` invocation, which is unsafe when the
    # requested partitions have different sizes.
    plan: list[str] = []
    for pass_name in CAPTURE_PASSES:
        pass_output = output / pass_name
        plan.append(f"gpt {pass_output}")
        plan.extend(
            f"r {name} {pass_output / f'{name}.bin'}" for name in PARTITIONS
        )
        plan.extend([
            f"ro 0x0 0x80000 {pass_output / 'preloader_lu0.bin'} --parttype lu0",
            f"ro 0x0 0x80000 {pass_output / 'preloader_lu1.bin'} --parttype lu1",
        ])
    return plan


def validate_read_only_plan(plan: list[str], output: Path) -> None:
    expected: list[list[str]] = []
    for pass_name in CAPTURE_PASSES:
        pass_output = output / pass_name
        expected.append(["gpt", str(pass_output)])
        expected.extend(
            ["r", name, str(pass_output / f"{name}.bin")]
            for name in PARTITIONS
        )
        expected.extend(
            [
                [
                    "ro",
                    "0x0",
                    "0x80000",
                    str(pass_output / "preloader_lu0.bin"),
                    "--parttype",
                    "lu0",
                ],
                [
                    "ro",
                    "0x0",
                    "0x80000",
                    str(pass_output / "preloader_lu1.bin"),
                    "--parttype",
                    "lu1",
                ],
            ]
        )
    actual = [command.split(" ") for command in plan]
    if actual != expected:
        raise SystemExit("Internal safety error: recovery plan is not the fixed allowlist")


def build_mtk_command(mtk_root: Path, preloader: Path, plan_file: Path) -> list[str]:
    # MediaTek's Android META composite interface also uses vendor 0x0e8d
    # (observed as PID 0x200e on the RT7). Without an exact filter mtkclient
    # mistakes its ADB bulk endpoints for a preloader and repeatedly attempts a
    # handshake. Recovery capture accepts only the real BootROM USB identity.
    return [
        sys.executable,
        str(mtk_root / "mtk.py"),
        "--vid",
        BROM_VID,
        "--pid",
        BROM_PID,
        "--preloader",
        str(preloader),
        "script",
        str(plan_file),
    ]


def parse_gpt_header(data: bytes, offset: int, label: str) -> dict[str, object]:
    if offset < 0 or offset + GPT_HEADER.size > len(data):
        raise ValueError(f"{label} GPT header is outside the captured span")
    values = GPT_HEADER.unpack_from(data, offset)
    keys = (
        "signature",
        "revision",
        "header_size",
        "header_crc32",
        "reserved",
        "current_lba",
        "backup_lba",
        "first_usable_lba",
        "last_usable_lba",
        "disk_guid",
        "partition_entry_start_lba",
        "num_partition_entries",
        "partition_entry_size",
        "partition_entry_crc32",
    )
    header = dict(zip(keys, values, strict=True))
    if header["signature"] != b"EFI PART":
        raise ValueError(f"{label} GPT signature is invalid")
    if header["revision"] != 0x00010000:
        raise ValueError(f"{label} GPT revision is unsupported")
    header_size = int(header["header_size"])
    if header_size < GPT_HEADER.size or offset + header_size > len(data):
        raise ValueError(f"{label} GPT header size is invalid")
    if header["reserved"] != 0:
        raise ValueError(f"{label} GPT reserved field is nonzero")

    header_bytes = bytearray(data[offset : offset + header_size])
    header_bytes[16:20] = b"\0\0\0\0"
    actual_crc = zlib.crc32(header_bytes) & 0xFFFFFFFF
    if actual_crc != header["header_crc32"]:
        raise ValueError(
            f"{label} GPT header CRC mismatch: {actual_crc:08x} != "
            f"{header['header_crc32']:08x}"
        )
    return header


def parse_gpt_entries(
    data: bytes,
    header: dict[str, object],
    capture_start_lba: int,
    sector_size: int,
    label: str,
) -> tuple[bytes, dict[str, dict[str, int]]]:
    count = int(header["num_partition_entries"])
    entry_size = int(header["partition_entry_size"])
    if count <= 0 or count > 4096 or entry_size < 128 or entry_size % 8:
        raise ValueError(f"{label} GPT partition-entry geometry is invalid")

    relative_lba = int(header["partition_entry_start_lba"]) - capture_start_lba
    offset = relative_lba * sector_size
    length = count * entry_size
    if offset < 0 or offset + length > len(data):
        raise ValueError(f"{label} GPT partition entries are outside the captured span")
    raw_entries = data[offset : offset + length]
    actual_crc = zlib.crc32(raw_entries) & 0xFFFFFFFF
    if actual_crc != header["partition_entry_crc32"]:
        raise ValueError(
            f"{label} GPT entry-array CRC mismatch: {actual_crc:08x} != "
            f"{header['partition_entry_crc32']:08x}"
        )

    partitions: dict[str, dict[str, int]] = {}
    for index in range(count):
        entry = raw_entries[index * entry_size : (index + 1) * entry_size]
        if entry[:16] == bytes(16):
            continue
        first_lba, last_lba = struct.unpack_from("<QQ", entry, 32)
        if first_lba > last_lba:
            raise ValueError(f"{label} GPT entry {index} has an invalid LBA range")
        if not (
            int(header["first_usable_lba"])
            <= first_lba
            <= last_lba
            <= int(header["last_usable_lba"])
        ):
            raise ValueError(f"{label} GPT entry {index} is outside usable storage")
        try:
            name = entry[56:128].decode("utf-16-le").split("\0", 1)[0]
        except UnicodeDecodeError as error:
            raise ValueError(f"{label} GPT entry {index} has an invalid name") from error
        if not name or name in partitions:
            raise ValueError(f"{label} GPT entry {index} has an empty or duplicate name")
        partitions[name] = {
            "first_lba": first_lba,
            "last_lba": last_lba,
            "size": (last_lba - first_lba + 1) * sector_size,
        }
    return raw_entries, partitions


def parse_gpt_pair(primary: bytes, backup: bytes) -> dict[str, object]:
    sector_size = next(
        (size for size in (0x200, 0x1000) if primary[size : size + 8] == b"EFI PART"),
        0,
    )
    if not sector_size:
        raise ValueError("primary GPT signature was not found at LBA 1")
    if primary[0x1FE:0x200] != b"\x55\xaa":
        raise ValueError("protective MBR signature is invalid")

    primary_header = parse_gpt_header(primary, sector_size, "primary")
    if primary_header["current_lba"] != 1:
        raise ValueError("primary GPT is not located at LBA 1")
    expected_primary_size = int(primary_header["first_usable_lba"]) * sector_size
    if len(primary) != expected_primary_size:
        raise ValueError(
            f"primary GPT span has size {len(primary)}, expected {expected_primary_size}"
        )

    backup_sectors = int(primary_header["first_usable_lba"]) - 1
    expected_backup_size = backup_sectors * sector_size
    if len(backup) != expected_backup_size:
        raise ValueError(
            f"backup GPT span has size {len(backup)}, expected {expected_backup_size}"
        )
    backup_start_lba = int(primary_header["backup_lba"]) - backup_sectors + 1
    backup_header_offset = (
        int(primary_header["backup_lba"]) - backup_start_lba
    ) * sector_size
    backup_header = parse_gpt_header(backup, backup_header_offset, "backup")

    mirrored_fields = (
        "first_usable_lba",
        "last_usable_lba",
        "disk_guid",
        "num_partition_entries",
        "partition_entry_size",
        "partition_entry_crc32",
    )
    if any(primary_header[field] != backup_header[field] for field in mirrored_fields):
        raise ValueError("primary and backup GPT headers disagree")
    if (
        backup_header["current_lba"] != primary_header["backup_lba"]
        or backup_header["backup_lba"] != primary_header["current_lba"]
    ):
        raise ValueError("backup GPT LBA pointers do not mirror the primary header")

    primary_entries, primary_partitions = parse_gpt_entries(
        primary, primary_header, 0, sector_size, "primary"
    )
    backup_entries, backup_partitions = parse_gpt_entries(
        backup, backup_header, backup_start_lba, sector_size, "backup"
    )
    if primary_entries != backup_entries or primary_partitions != backup_partitions:
        raise ValueError("primary and backup GPT partition arrays are not identical")

    return {
        "sector_size": sector_size,
        "disk_guid": bytes(primary_header["disk_guid"]).hex(),
        "primary_lba": int(primary_header["current_lba"]),
        "backup_lba": int(primary_header["backup_lba"]),
        "first_usable_lba": int(primary_header["first_usable_lba"]),
        "last_usable_lba": int(primary_header["last_usable_lba"]),
        "partitions": primary_partitions,
    }


def has_nonuniform_content(path: Path) -> bool:
    first: int | None = None
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            if first is None:
                first = block[0]
            if block != bytes([first]) * len(block):
                return True
    return False


def validate_capture_pass(directory: Path) -> dict[str, object]:
    fixed_sizes = dict(PARTITIONS)
    fixed_sizes["preloader_lu0"] = 0x80000
    fixed_sizes["preloader_lu1"] = 0x80000
    expected_names = {f"{name}.bin" for name in fixed_sizes}
    expected_names.update(("gpt.bin", "gpt_backup.bin"))
    actual_names = {path.name for path in directory.glob("*.bin")}

    failures: list[str] = []
    for name in sorted(expected_names - actual_names):
        failures.append(f"missing {directory.name}/{name}")
    for name in sorted(actual_names - expected_names):
        failures.append(f"unexpected private artifact {directory.name}/{name}")
    for name, size in fixed_sizes.items():
        path = directory / f"{name}.bin"
        if path.is_file() and path.stat().st_size != size:
            failures.append(
                f"wrong size for {directory.name}/{path.name}: "
                f"{path.stat().st_size}, expected {size}"
            )

    gpt: dict[str, object] | None = None
    primary_path = directory / "gpt.bin"
    backup_path = directory / "gpt_backup.bin"
    if primary_path.is_file() and backup_path.is_file():
        try:
            gpt = parse_gpt_pair(primary_path.read_bytes(), backup_path.read_bytes())
        except ValueError as error:
            failures.append(str(error))
    if gpt:
        gpt_partitions = gpt["partitions"]
        assert isinstance(gpt_partitions, dict)
        for name, expected_size in PARTITIONS.items():
            partition = gpt_partitions.get(name)
            if partition is None:
                failures.append(f"GPT is missing required partition {name}")
            elif partition["size"] != expected_size:
                failures.append(
                    f"GPT size for {name} is {partition['size']}, expected {expected_size}"
                )

    required_magic = {
        "boot_a": b"ANDROID!",
        "dtbo_a": b"\xd7\xb7\xab\x1e",
        "vbmeta_a": b"AVB0",
        "vbmeta_system_a": b"AVB0",
        "vbmeta_vendor_a": b"AVB0",
    }
    for name, magic in required_magic.items():
        path = directory / f"{name}.bin"
        if path.is_file():
            with path.open("rb") as stream:
                if stream.read(len(magic)) != magic:
                    failures.append(f"{directory.name}/{path.name} has invalid magic")

    for name in ("lk_a", "tee_a", "seccfg", "preloader_lu0", "preloader_lu1"):
        path = directory / f"{name}.bin"
        if path.is_file() and not has_nonuniform_content(path):
            failures.append(f"{directory.name}/{path.name} contains one repeated byte")

    if failures:
        raise SystemExit("Capture validation failed:\n- " + "\n- ".join(failures))
    assert gpt is not None
    return gpt


def validate_capture(output: Path) -> None:
    gpt_by_pass = {
        pass_name: validate_capture_pass(output / pass_name)
        for pass_name in CAPTURE_PASSES
    }
    if gpt_by_pass[CAPTURE_PASSES[0]] != gpt_by_pass[CAPTURE_PASSES[1]]:
        raise SystemExit("Capture validation failed: GPT differs between read passes")

    artifact_names = sorted(
        path.name for path in (output / CAPTURE_PASSES[0]).glob("*.bin")
    )
    artifacts: dict[str, dict[str, object]] = {}
    failures: list[str] = []
    checksum_lines: list[str] = []
    for name in artifact_names:
        paths = [output / pass_name / name for pass_name in CAPTURE_PASSES]
        hashes = [sha256(path) for path in paths]
        if len(set(hashes)) != 1:
            failures.append(f"independent reads differ for {name}")
        artifacts[name] = {
            "size": paths[0].stat().st_size,
            "sha256": hashes[0],
            "verified_copies": len(CAPTURE_PASSES),
        }
        checksum_lines.extend(
            f"{digest}  {pass_name}/{name}\n"
            for pass_name, digest in zip(CAPTURE_PASSES, hashes, strict=True)
        )
    if failures:
        raise SystemExit("Capture validation failed:\n- " + "\n- ".join(failures))

    slot_comparisons: dict[str, bool] = {}
    for base in ("boot", "dtbo", "lk", "tee", "vbmeta", "vbmeta_system", "vbmeta_vendor"):
        slot_comparisons[base] = (
            artifacts[f"{base}_a.bin"]["sha256"]
            == artifacts[f"{base}_b.bin"]["sha256"]
        )
    slot_comparisons["preloader_lu0_lu1"] = (
        artifacts["preloader_lu0.bin"]["sha256"]
        == artifacts["preloader_lu1.bin"]["sha256"]
    )

    checksum_manifest = output / "SHA256SUMS.txt"
    checksum_manifest.write_text(
        "".join(checksum_lines), encoding="ascii", newline="\n"
    )
    capture_manifest = output / "capture-manifest.json"
    capture_manifest.write_text(
        json.dumps(
            {
                "format": 2,
                "mtkclient_commit": MTKCLIENT_COMMIT,
                "gpt_capture_patch": MTKCLIENT_GPT_PATCH_MARKER,
                "read_passes": list(CAPTURE_PASSES),
                "artifacts": artifacts,
                "gpt": gpt_by_pass[CAPTURE_PASSES[0]],
                "slot_images_identical": slot_comparisons,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="ascii",
        newline="\n",
    )
    print(
        f"Validated {len(artifacts)} artifacts across "
        f"{len(CAPTURE_PASSES)} identical read passes"
    )
    print(f"SHA-256 manifest: {checksum_manifest}")
    print(f"Capture manifest: {capture_manifest}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare the fixed read-only OUKITEL RT7 recovery capture"
    )
    parser.add_argument("--preloader", default=DEFAULT_PRELOADER)
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT)
    parser.add_argument("--mtk-root", default="/opt/mtkclient")
    parser.add_argument(
        "--execute",
        action="store_true",
        help="connect to the tablet and execute the read-only plan",
    )
    args = parser.parse_args()

    mtk_root = safe_path(args.mtk_root, "mtkclient root")
    preloader = safe_path(args.preloader, "preloader path")
    output = safe_path(args.output_dir, "output directory")
    private_root = Path("/rt7-work/recovery").resolve()

    if private_root not in output.parents:
        raise SystemExit(f"Output must be a child of {private_root}")
    if not preloader.is_file():
        raise SystemExit(f"Reference preloader not found: {preloader}")
    if sha256(preloader) != PRELOADER_SHA256:
        raise SystemExit("Reference preloader SHA-256 does not match sources.lock")

    validate_tool(mtk_root)
    plan = build_plan(output)
    validate_read_only_plan(plan, output)
    print("Fixed read-only command plan:")
    for command in plan:
        print(f"  {command}")

    if not args.execute:
        print("Dry run only; pass --execute after attaching the tablet with usbipd-win.")
        return 0

    output.mkdir(parents=True, exist_ok=False)
    for pass_name in CAPTURE_PASSES:
        (output / pass_name).mkdir()
    plan_file = output / "read-only-plan.txt"
    plan_file.write_text("\n".join(plan) + "\n", encoding="ascii", newline="\n")

    command = build_mtk_command(mtk_root, preloader, plan_file)
    result = subprocess.run(command, cwd=output, check=False)
    if result.returncode != 0:
        raise SystemExit(f"mtkclient exited with status {result.returncode}")

    validate_capture(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

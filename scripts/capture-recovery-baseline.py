#!/usr/bin/env python3
"""Create or execute the fixed read-only RT7 recovery capture plan."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import subprocess
import sys


MTKCLIENT_COMMIT = "4d29037104b1f378abedcace89ccd48e8a8aa314"
PRELOADER_SHA256 = "e76b3bc6f70f263026088c19665d25b900956832efcc448804be921cc765fa26"
DEFAULT_PRELOADER = (
    "/rt7-work/firmware/extracted/V1.4.8/"
    "TP758_OQ_P07_NFC_6853_T0_EEA_V1.4.8_S251017/"
    "preloader_tp758_oq_p07_nfc_6853_t0_eea.bin"
)
DEFAULT_OUTPUT = "/rt7-work/recovery/rt7-installed-v04-20231205"

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


def build_plan(output: Path) -> list[str]:
    # Use one command per partition. Upstream v2.1.4 retains the first detected
    # size inside a comma-separated `r` invocation, which is unsafe when the
    # requested partitions have different sizes.
    plan = [f"gpt {output}"]
    plan.extend(f"r {name} {output / f'{name}.bin'}" for name in PARTITIONS)
    plan.extend([
        f"ro 0x0 0x80000 {output / 'preloader_lu0.bin'} --parttype lu0",
        f"ro 0x0 0x80000 {output / 'preloader_lu1.bin'} --parttype lu1",
    ])
    return plan


def validate_read_only_plan(plan: list[str], output: Path) -> None:
    expected = [["gpt", str(output)]]
    expected.extend(
        ["r", name, str(output / f"{name}.bin")] for name in PARTITIONS
    )
    expected.extend(
        [
            [
                "ro",
                "0x0",
                "0x80000",
                str(output / "preloader_lu0.bin"),
                "--parttype",
                "lu0",
            ],
            [
                "ro",
                "0x0",
                "0x80000",
                str(output / "preloader_lu1.bin"),
                "--parttype",
                "lu1",
            ],
        ]
    )
    actual = [command.split(" ") for command in plan]
    if actual != expected:
        raise SystemExit("Internal safety error: recovery plan is not the fixed allowlist")


def validate_capture(output: Path) -> None:
    expected = dict(PARTITIONS)
    expected["preloader_lu0"] = 0x80000
    expected["preloader_lu1"] = 0x80000

    failures: list[str] = []
    for name, size in expected.items():
        path = output / f"{name}.bin"
        if not path.is_file():
            failures.append(f"missing {path.name}")
        elif path.stat().st_size != size:
            failures.append(
                f"wrong size for {path.name}: {path.stat().st_size}, expected {size}"
            )

    for name in ("gpt.bin", "gpt_backup.bin"):
        path = output / name
        if not path.is_file() or path.stat().st_size == 0:
            failures.append(f"missing or empty {name}")

    if failures:
        raise SystemExit("Capture validation failed:\n- " + "\n- ".join(failures))

    artifacts = sorted(output.glob("*.bin"))
    manifest = output / "SHA256SUMS.txt"
    manifest.write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in artifacts),
        encoding="ascii",
        newline="\n",
    )
    print(f"Validated {len(artifacts)} private recovery artifacts")
    print(f"SHA-256 manifest: {manifest}")


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
    plan_file = output / "read-only-plan.txt"
    plan_file.write_text("\n".join(plan) + "\n", encoding="ascii", newline="\n")

    command = [
        sys.executable,
        str(mtk_root / "mtk.py"),
        "--preloader",
        str(preloader),
        "script",
        str(plan_file),
    ]
    result = subprocess.run(command, cwd=output, check=False)
    if result.returncode != 0:
        raise SystemExit(f"mtkclient exited with status {result.returncode}")

    validate_capture(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

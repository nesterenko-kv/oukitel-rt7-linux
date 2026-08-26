#!/usr/bin/env python3

"""Build an unsigned, non-flashable RT7 boot-image test artifact.

The script first proves that pinned AOSP tools reproduce the signed stock
image payload byte-for-byte. It then changes only the kernel component and
verifies all other unpacked components and header arguments are unchanged.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


CHUNK_SIZE = 1024 * 1024


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK_SIZE):
            digest.update(chunk)
    return digest.hexdigest()


def files_equal(left: Path, right: Path, limit: int | None = None) -> bool:
    remaining = limit
    with left.open("rb") as left_stream, right.open("rb") as right_stream:
        while remaining is None or remaining > 0:
            read_size = CHUNK_SIZE if remaining is None else min(CHUNK_SIZE, remaining)
            left_chunk = left_stream.read(read_size)
            right_chunk = right_stream.read(read_size)
            if left_chunk != right_chunk:
                return False
            if not left_chunk:
                return True
            if remaining is not None:
                remaining -= len(left_chunk)
        return True


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def unpack_args(python: str, unpack_tool: Path, image: Path, output: Path) -> list[str]:
    result = run(
        [
            python,
            str(unpack_tool),
            "--boot_img",
            str(image),
            "--out",
            str(output),
            "--format=mkbootimg",
            "-0",
        ],
        capture=True,
    )
    items = result.stdout.split(b"\0")
    if items and items[-1] == b"":
        items.pop()
    return [item.decode() for item in items]


def replace_argument(arguments: list[str], name: str, value: Path) -> list[str]:
    updated = arguments.copy()
    try:
        index = updated.index(name)
    except ValueError as error:
        raise RuntimeError(f"missing {name} in unpacked mkbootimg arguments") from error
    updated[index + 1] = str(value)
    return updated


def normalized_arguments(arguments: list[str]) -> list[str]:
    normalized = arguments.copy()
    for name in ("--kernel", "--ramdisk", "--second", "--dtb"):
        if name in normalized:
            index = normalized.index(name)
            normalized[index + 1] = f"<{name[2:]}>"
    return normalized


def original_payload_size(python: str, avbtool: Path, image: Path) -> tuple[int, str]:
    result = run(
        [python, str(avbtool), "info_image", "--image", str(image)],
        capture=True,
    )
    output = result.stdout.decode()
    match = re.search(r"^Original image size:\s+(\d+) bytes$", output, re.MULTILINE)
    if not match:
        raise RuntimeError("stock image does not expose an AVB original image size")
    return int(match.group(1)), output


def write_idempotent(path: Path, content: bytes) -> None:
    if path.exists():
        if path.read_bytes() != content:
            raise RuntimeError(f"refusing to overwrite different existing file: {path}")
        return
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_bytes(content)
    os.replace(temporary, path)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boot-img", required=True, type=Path)
    parser.add_argument("--expected-boot-sha256", required=True)
    parser.add_argument("--kernel", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--tools-dir",
        type=Path,
        default=Path("/rt7-work/tools/android-13.0.0_r1"),
    )
    return parser.parse_args()


def main() -> int:
    options = parse_arguments()
    python = sys.executable
    boot_image = options.boot_img.resolve()
    kernel = options.kernel.resolve()
    output = options.output.resolve()
    tools_dir = options.tools_dir.resolve()
    unpack_tool = tools_dir / "mkbootimg" / "unpack_bootimg.py"
    mkbootimg_tool = tools_dir / "mkbootimg" / "mkbootimg.py"
    avbtool = tools_dir / "avb" / "avbtool.py"

    for path in (boot_image, kernel, unpack_tool, mkbootimg_tool, avbtool):
        if not path.is_file():
            raise RuntimeError(f"required input is not a file: {path}")
    if Path("/project") in output.parents:
        raise RuntimeError("boot artifacts must stay outside the public repository")
    if "unsigned" not in output.name or "do-not-flash" not in output.name:
        raise RuntimeError("output name must contain 'unsigned' and 'do-not-flash'")

    actual_boot_hash = sha256(boot_image)
    if actual_boot_hash.lower() != options.expected_boot_sha256.lower():
        raise RuntimeError(
            "stock boot hash mismatch: "
            f"expected {options.expected_boot_sha256}, got {actual_boot_hash}"
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    payload_size, avb_info = original_payload_size(python, avbtool, boot_image)

    with tempfile.TemporaryDirectory(prefix="rt7-boot-", dir=output.parent) as temp_name:
        temporary = Path(temp_name)
        stock_parts = temporary / "stock"
        custom_parts = temporary / "custom"
        stock_parts.mkdir()
        custom_parts.mkdir()

        stock_arguments = unpack_args(python, unpack_tool, boot_image, stock_parts)
        stock_roundtrip = temporary / "stock-roundtrip.img"
        run([python, str(mkbootimg_tool), "--output", str(stock_roundtrip), *stock_arguments])

        if stock_roundtrip.stat().st_size != payload_size:
            raise RuntimeError("stock round-trip payload size changed")
        if not files_equal(boot_image, stock_roundtrip, payload_size):
            raise RuntimeError("stock round-trip payload is not byte-identical")

        custom_temporary = temporary / "custom-unsigned-do-not-flash.img"
        custom_arguments = replace_argument(stock_arguments, "--kernel", kernel)
        run([python, str(mkbootimg_tool), "--output", str(custom_temporary), *custom_arguments])

        unpacked_custom_arguments = unpack_args(
            python, unpack_tool, custom_temporary, custom_parts
        )
        if normalized_arguments(stock_arguments) != normalized_arguments(
            unpacked_custom_arguments
        ):
            raise RuntimeError("custom image changed boot header arguments")
        if not files_equal(kernel, custom_parts / "kernel"):
            raise RuntimeError("custom image kernel did not round-trip")
        for component in ("ramdisk", "dtb"):
            if not files_equal(stock_parts / component, custom_parts / component):
                raise RuntimeError(f"custom image changed stock {component}")
        if custom_temporary.stat().st_size > payload_size:
            raise RuntimeError("custom boot payload exceeds the signed stock payload size")

        custom_bytes = custom_temporary.read_bytes()
        write_idempotent(output, custom_bytes)

    manifest = {
        "format": 1,
        "warning": "UNSIGNED RESEARCH ARTIFACT - DO NOT FLASH",
        "source_boot": {
            "filename": boot_image.name,
            "sha256": actual_boot_hash,
            "partition_size": boot_image.stat().st_size,
            "avb_original_image_size": payload_size,
        },
        "kernel": {
            "filename": kernel.name,
            "sha256": sha256(kernel),
            "size": kernel.stat().st_size,
        },
        "output": {
            "filename": output.name,
            "sha256": sha256(output),
            "size": output.stat().st_size,
            "avb_signed": False,
            "flashable": False,
        },
        "mkbootimg_arguments": normalized_arguments(stock_arguments),
        "avb_info": avb_info.rstrip().splitlines(),
    }
    manifest_path = output.with_suffix(output.suffix + ".json")
    content = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    write_idempotent(manifest_path, content)

    print("stock boot payload round-trip: PASS")
    print("custom kernel-only substitution: PASS")
    print(f"output: {output}")
    print(f"sha256: {manifest['output']['sha256']}")
    print(f"size: {manifest['output']['size']} bytes")
    print("warning: UNSIGNED RESEARCH ARTIFACT - DO NOT FLASH")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)

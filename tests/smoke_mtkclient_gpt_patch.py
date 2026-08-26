#!/usr/bin/env python3
"""Exercise the pinned mtkclient GPT patch with a fake read-only daloader."""

from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from types import SimpleNamespace

sys.path.insert(0, "/opt/mtkclient")

from mtkclient.Library.DA.mtk_da_handler import DaHandler


SECTOR_SIZE = 512
DISK_SECTORS = 4096
FIRST_USABLE_LBA = 34
BACKUP_LBA = DISK_SECTORS - 1
BACKUP_SECTORS = FIRST_USABLE_LBA - 1
BACKUP_START_LBA = BACKUP_LBA - BACKUP_SECTORS + 1


class FakeDaloader:
    def __init__(self) -> None:
        self.daconfig = SimpleNamespace(
            storage=SimpleNamespace(flashsize=DISK_SECTORS * SECTOR_SIZE)
        )
        header = SimpleNamespace(
            signature=b"EFI PART",
            first_usable_lba=FIRST_USABLE_LBA,
            last_usable_lba=BACKUP_START_LBA - 1,
            backup_lba=BACKUP_LBA,
        )
        self.guid_gpt = SimpleNamespace(header=header, sectorsize=SECTOR_SIZE)
        self.reads: list[tuple[int, int, str]] = []

    def get_gpt(self) -> tuple[bytes, SimpleNamespace]:
        return b"upstream-placeholder", self.guid_gpt

    def readflash(
        self,
        *,
        addr: int,
        length: int,
        filename: str,
        parttype: str,
        display: bool,
    ) -> bytes:
        assert filename == ""
        assert parttype == "user"
        assert display is False
        self.reads.append((addr, length, parttype))
        return bytes([(addr // SECTOR_SIZE) & 0xFF]) * length


def main() -> None:
    fake = FakeDaloader()
    handler = object.__new__(DaHandler)
    handler.mtk = SimpleNamespace(daloader=fake)

    with TemporaryDirectory() as temporary:
        handler.da_gpt(temporary, display=False)
        primary = Path(temporary, "gpt.bin").read_bytes()
        backup = Path(temporary, "gpt_backup.bin").read_bytes()

    assert fake.reads == [
        (0, FIRST_USABLE_LBA * SECTOR_SIZE, "user"),
        (BACKUP_START_LBA * SECTOR_SIZE, BACKUP_SECTORS * SECTOR_SIZE, "user"),
    ]
    assert len(primary) == FIRST_USABLE_LBA * SECTOR_SIZE
    assert len(backup) == BACKUP_SECTORS * SECTOR_SIZE
    assert primary == bytes(len(primary))
    assert backup == bytes([BACKUP_START_LBA & 0xFF]) * len(backup)
    print("Patched mtkclient primary/backup GPT reads: PASS")


if __name__ == "__main__":
    main()

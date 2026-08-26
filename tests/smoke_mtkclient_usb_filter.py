#!/usr/bin/env python3
"""Verify that mtkclient's exact VID/PID mode builds a strict USB mapping."""

import logging
import sys

sys.path.insert(0, "/opt/mtkclient")

from mtkclient.Library.mtk_class import Mtk
from mtkclient.config.mtk_config import MtkConfig


def main() -> None:
    config = MtkConfig(loglevel=logging.CRITICAL)
    config.vid = 0x0E8D
    config.pid = 0x0003
    device = Mtk(config=config)
    assert device.port.cdc.portconfig == {0x0E8D: {0x0003: -1}}
    assert 0x200E not in device.port.cdc.portconfig[0x0E8D]
    print("Patched mtkclient exact BootROM USB filter: PASS")


if __name__ == "__main__":
    main()

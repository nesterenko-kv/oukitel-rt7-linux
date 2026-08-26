#!/usr/bin/env python3
"""Probe the initial MediaTek BootROM/Preloader USB handshake.

This diagnostic never issues storage, memory-write, download-agent, or reboot
commands. It only enumerates the MediaTek USB transport and performs the
four-byte synchronization exchange used before any MediaTek command.
"""

from __future__ import annotations

import argparse
from ctypes import c_int, c_void_p
import sys
import time
from dataclasses import dataclass
from typing import Iterable

import usb.core
import usb.backend.libusb1
import usb.util


VID_MEDIATEK = 0x0E8D
TRANSPORT_PIDS = {0x0003, 0x2000, 0x2001, 0x20FF, 0x3000, 0x6000}
START_COMMAND = bytes((0xA0, 0x0A, 0x50, 0x05))


@dataclass(frozen=True)
class EndpointPair:
    interface_number: int
    endpoint_in: object
    endpoint_out: object


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--timeout",
        type=float,
        default=180.0,
        help="seconds to wait for a MediaTek transport (default: 180)",
    )
    parser.add_argument(
        "--poll-interval",
        type=float,
        default=0.005,
        help="seconds between USB enumeration attempts (default: 0.005)",
    )
    return parser.parse_args()


def load_backend() -> object:
    backend = usb.backend.libusb1.get_backend()
    if backend is None:
        raise RuntimeError("libusb-1.0 backend is unavailable")
    if sys.platform == "win32":
        try:
            backend.lib.libusb_set_option.argtypes = [c_void_p, c_int]
            result = backend.lib.libusb_set_option(backend.ctx, 1)
        except (AttributeError, OSError) as error:
            raise RuntimeError(f"cannot enable the UsbDk backend: {error}") from error
        if result != 0:
            raise RuntimeError(f"enabling the UsbDk backend returned {result}")
        print("backend=libusb-1.0/usbdk", flush=True)
    else:
        print("backend=libusb-1.0", flush=True)
    return backend


def matching_devices(backend: object) -> Iterable[object]:
    devices = usb.core.find(find_all=True, idVendor=VID_MEDIATEK, backend=backend)
    return (device for device in devices if device.idProduct in TRANSPORT_PIDS)


def wait_for_transport(backend: object, timeout: float, poll_interval: float) -> object:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for device in matching_devices(backend):
            return device
        time.sleep(poll_interval)
    raise TimeoutError(f"no MediaTek transport appeared within {timeout:g} seconds")


def prepare_configuration(device: object) -> object:
    try:
        return device.get_active_configuration()
    except usb.core.USBError as error:
        if "Configuration not set" not in str(error):
            raise
    device.set_configuration()
    return device.get_active_configuration()


def endpoint_summary(configuration: object) -> list[str]:
    result: list[str] = []
    for interface in configuration:
        endpoints = ",".join(
            f"0x{endpoint.bEndpointAddress:02x}/attr=0x{endpoint.bmAttributes:02x}"
            for endpoint in interface
        )
        result.append(
            "interface="
            f"{interface.bInterfaceNumber} class=0x{interface.bInterfaceClass:02x} "
            f"subclass=0x{interface.bInterfaceSubClass:02x} "
            f"protocol=0x{interface.bInterfaceProtocol:02x} endpoints=[{endpoints}]"
        )
    return result


def find_endpoint_pair(configuration: object) -> EndpointPair:
    candidates: list[EndpointPair] = []
    for interface in configuration:
        endpoint_in = usb.util.find_descriptor(
            interface,
            custom_match=lambda endpoint: usb.util.endpoint_direction(
                endpoint.bEndpointAddress
            )
            == usb.util.ENDPOINT_IN,
        )
        endpoint_out = usb.util.find_descriptor(
            interface,
            custom_match=lambda endpoint: usb.util.endpoint_direction(
                endpoint.bEndpointAddress
            )
            == usb.util.ENDPOINT_OUT,
        )
        if endpoint_in is not None and endpoint_out is not None:
            pair = EndpointPair(interface.bInterfaceNumber, endpoint_in, endpoint_out)
            if interface.bInterfaceClass == 0x0A:
                return pair
            candidates.append(pair)
    if candidates:
        return candidates[0]
    raise RuntimeError("transport has no interface with both IN and OUT endpoints")


def claim_interface(device: object, interface_number: int) -> None:
    try:
        if device.is_kernel_driver_active(interface_number):
            device.detach_kernel_driver(interface_number)
    except (NotImplementedError, usb.core.USBError):
        pass
    usb.util.claim_interface(device, interface_number)


def configure_cdc(device: object) -> None:
    line_coding = bytes((0x00, 0x10, 0x0E, 0x00, 0x00, 0x00, 0x08))
    for label, request, value, payload in (
        ("SET_LINE_CODING", 0x20, 0, line_coding),
        ("SET_CONTROL_LINE_STATE", 0x01, 2, b""),
    ):
        try:
            sent = device.ctrl_transfer(0x21, request, value, 0, payload, timeout=100)
            print(f"{label}: sent={sent}", flush=True)
        except usb.core.USBError as error:
            print(f"{label}: ignored USB error: {error}", flush=True)


def run_handshake(pair: EndpointPair) -> bool:
    for index, value in enumerate(START_COMMAND, start=1):
        try:
            written = pair.endpoint_out.write(bytes((value,)), timeout=250)
            echo = bytes(pair.endpoint_in.read(1, timeout=250))
        except usb.core.USBError as error:
            print(
                f"sync[{index}] tx=0x{value:02x}: USB error {error}",
                flush=True,
            )
            return False
        expected = value ^ 0xFF
        actual = echo[0] if len(echo) == 1 else None
        print(
            f"sync[{index}] tx=0x{value:02x} written={written} "
            f"rx={echo.hex() or '<empty>'} expected=0x{expected:02x}",
            flush=True,
        )
        if written != 1 or actual != expected:
            return False
    return True


def main() -> int:
    args = parse_args()
    print(
        "READ-ONLY TRANSPORT PROBE: no flash, memory-write, DA, or reboot commands",
        flush=True,
    )
    try:
        backend = load_backend()
        device = wait_for_transport(backend, args.timeout, args.poll_interval)
        print(
            f"detected vid=0x{device.idVendor:04x} pid=0x{device.idProduct:04x} "
            f"device_class=0x{device.bDeviceClass:02x} "
            f"bus={device.bus} address={device.address}",
            flush=True,
        )
        configuration = prepare_configuration(device)
        for line in endpoint_summary(configuration):
            print(line, flush=True)
        pair = find_endpoint_pair(configuration)
        print(f"using interface={pair.interface_number}", flush=True)
        claim_interface(device, pair.interface_number)
        configure_cdc(device)
        if not run_handshake(pair):
            print("RESULT: handshake failed", flush=True)
            return 2
        print("RESULT: handshake succeeded", flush=True)
        return 0
    except (RuntimeError, TimeoutError, usb.core.USBError) as error:
        print(f"RESULT: probe failed: {error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

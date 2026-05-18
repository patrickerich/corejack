#!/usr/bin/env python3
"""Load a binary image into CoreJack SRAM through the UART SRAM loader."""

from __future__ import annotations

import argparse
import os
import select
import termios
import time
from pathlib import Path


ACK = 0x06
NAK = 0x15


BAUD_RATES = {
    9600: termios.B9600,
    19200: termios.B19200,
    38400: termios.B38400,
    57600: termios.B57600,
    115200: termios.B115200,
    230400: termios.B230400,
    460800: termios.B460800,
    921600: termios.B921600,
}


class SerialPort:
    def __init__(self, path: str, baud: int, timeout: float) -> None:
        if baud not in BAUD_RATES:
            supported = ", ".join(str(rate) for rate in sorted(BAUD_RATES))
            raise ValueError(f"unsupported baud {baud}; supported: {supported}")

        self.timeout = timeout
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        self._old_attrs = termios.tcgetattr(self.fd)

        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = BAUD_RATES[baud]
        attrs[5] = BAUD_RATES[baud]
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)

    def close(self) -> None:
        termios.tcsetattr(self.fd, termios.TCSANOW, self._old_attrs)
        os.close(self.fd)

    def write_all(self, data: bytes) -> None:
        view = memoryview(data)
        while view:
            _, writable, _ = select.select([], [self.fd], [], self.timeout)
            if not writable:
                raise TimeoutError("timed out waiting for UART write readiness")
            written = os.write(self.fd, view)
            view = view[written:]

    def read_byte(self) -> int:
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for UART response")
            readable, _, _ = select.select([self.fd], [], [], remaining)
            if not readable:
                continue
            data = os.read(self.fd, 1)
            if data:
                return data[0]

    def read_available_until(self, seconds: float) -> bytes:
        deadline = time.monotonic() + seconds
        chunks: list[bytes] = []
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return b"".join(chunks)
            readable, _, _ = select.select([self.fd], [], [], min(0.1, remaining))
            if not readable:
                continue
            chunks.append(os.read(self.fd, 4096))


def expect_ack(port: SerialPort, context: str) -> None:
    value = port.read_byte()
    if value == ACK:
        return
    if value == NAK:
        raise RuntimeError(f"{context}: loader returned NAK")
    raise RuntimeError(f"{context}: expected ACK 0x06, got 0x{value:02x}")


def write_chunk(port: SerialPort, addr: int, payload: bytes) -> None:
    if not payload:
        return
    if len(payload) > 0xFFFF:
        raise ValueError("payload chunk exceeds protocol limit")
    packet = (
        b"W"
        + addr.to_bytes(4, byteorder="little", signed=False)
        + len(payload).to_bytes(2, byteorder="little", signed=False)
        + payload
    )
    port.write_all(packet)
    expect_ack(port, f"write 0x{addr:08x}+0x{len(payload):x}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uart", required=True, help="UART device, e.g. /dev/ttyUSB1")
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate")
    parser.add_argument("--bin", required=True, type=Path, help="binary image to load")
    parser.add_argument("--addr", type=lambda value: int(value, 0), default=0x80000000)
    parser.add_argument("--chunk-size", type=int, default=4096)
    parser.add_argument("--timeout", type=float, default=2.0)
    parser.add_argument("--no-go", action="store_true", help="load image but do not release the core")
    parser.add_argument("--capture-seconds", type=float, default=0.0)
    parser.add_argument(
        "--expect",
        action="append",
        default=[],
        help="substring that must appear in captured UART output; may be repeated",
    )
    args = parser.parse_args()

    if not args.bin.is_file():
        raise SystemExit(f"binary image not found: {args.bin}")
    image = args.bin.read_bytes()
    if args.chunk_size <= 0 or args.chunk_size > 0xFFFF:
        raise SystemExit("--chunk-size must be in the range 1..65535")

    port = SerialPort(args.uart, args.baud, args.timeout)
    try:
        port.write_all(b"?")
        expect_ack(port, "ping")

        for offset in range(0, len(image), args.chunk_size):
            chunk = image[offset : offset + args.chunk_size]
            write_chunk(port, args.addr + offset, chunk)

        print(f"Loaded {len(image)} bytes at 0x{args.addr:08x}")

        if not args.no_go:
            port.write_all(b"G")
            expect_ack(port, "release")
            print("Released core")

        if args.capture_seconds > 0:
            captured = port.read_available_until(args.capture_seconds)
            text = captured.decode("utf-8", errors="replace")
            if text:
                print(text, end="" if text.endswith("\n") else "\n")
            for expected in args.expect:
                if expected not in text:
                    raise RuntimeError(f"expected UART text not found: {expected!r}")
    finally:
        port.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

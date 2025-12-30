# Author: 152120221098 Emre AVCI
"""
Air Conditioner Control System - Connection Tester
--------------------------------------------------
This script tests the AirConditionerControlSystemConnection class by:
- Opening UART connection
- Reading values periodically (GET)
- Writing desired temperature (SET) and verifying by reading back
- (Optional) Interactive mode to set values from user input

Usage examples:
  python test_air_conditioner.py --port COM8 --baud 9600 --mode poll
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from typing import List

# Import your class (adjust import path if needed)
from air_conditioner import AirConditionerControlSystemConnection


@dataclass
class TestConfig:
    """Holds test configuration parameters (OOP-friendly)."""
    port: str
    baud: int
    mode: str
    interval: float
    duration: float
    set_values: List[float]


class AirConditionerTester:
    """
    Object-oriented tester for AirConditionerControlSystemConnection.
    Encapsulates setup, polling, set-test, and interactive operations.
    """

    def __init__(self, cfg: TestConfig) -> None:
        self.cfg = cfg
        self.conn = AirConditionerControlSystemConnection(com_port=cfg.port, baud_rate=cfg.baud)

    def run(self) -> int:
        """Entry point for running the selected test mode."""
        try:
            if not self._open_connection():
                return 2

            if self.cfg.mode == "poll":
                self._poll_loop(duration=self.cfg.duration, interval=self.cfg.interval)
            elif self.cfg.mode == "set":
                self._set_sequence(self.cfg.set_values)
            elif self.cfg.mode == "interactive":
                self._interactive_loop()
            else:
                print(f"Unknown mode: {self.cfg.mode}")
                return 3

            return 0

        except KeyboardInterrupt:
            print("\n[INFO] Interrupted by user (Ctrl+C).")
            return 130

        except Exception as exc:
            print(f"[ERROR] Unexpected error: {exc}")
            return 1

        finally:
            self._close_connection()

    # -------------------- Connection Helpers --------------------

    def _open_connection(self) -> bool:
        """
        Opens the UART connection using the base connection API.
        NOTE: Your HomeAutomationSystemConnection might name this method differently.
        The tester tries common method names safely.
        """
        for method_name in ("open", "connect", "open_connection"):
            if hasattr(self.conn, method_name):
                try:
                    getattr(self.conn, method_name)()  # type: ignore[misc]
                    break
                except Exception as exc:
                    print(f"[ERROR] Failed to open using {method_name}(): {exc}")
                    return False

        if not self.conn.is_open():
            print("[ERROR] Connection is not open. Check COM port/baud and PICSimLab.")
            return False

        print(f"[OK] Connected to {self.cfg.port} @ {self.cfg.baud} baud.")
        return True

    def _close_connection(self) -> None:
        """Closes the UART connection gracefully."""
        for method_name in ("close", "disconnect", "close_connection"):
            if hasattr(self.conn, method_name):
                try:
                    getattr(self.conn, method_name)()  # type: ignore[misc]
                except Exception:
                    pass
                break

    # -------------------- Read/Print Helpers --------------------

    def _read_all_blocking(self) -> dict:
        """
        Reads all values using blocking GET calls.
        Returns a dictionary for structured output.
        """
        desired = self.conn.getDesiredTemp()
        ambient = self.conn.getAmbientTemp()
        fan = self.conn.getFanSpeed()

        return {
            "desired_temp": desired,
            "ambient_temp": ambient,
            "fan_speed": fan,
        }

    def _print_status(self, data: dict) -> None:
        """Pretty prints the status dictionary."""
        print(
            f"Desired: {data['desired_temp']:.1f} °C | "
            f"Ambient: {data['ambient_temp']:.1f} °C | "
            f"Fan: {data['fan_speed']} rps"
        )

    # -------------------- Modes --------------------

    def _poll_loop(self, duration: float, interval: float) -> None:
        """
        Polls values for the specified duration.
        Good for verifying that GET works continuously.
        """
        print(f"[MODE] Polling for {duration:.1f}s (interval={interval:.2f}s)...")
        t0 = time.time()
        while (time.time() - t0) < duration:
            data = self._read_all_blocking()
            self._print_status(data)
            time.sleep(interval)

    def _set_sequence(self, values: List[float]) -> None:
        """
        Sends a sequence of SET commands and verifies by reading back.
        Good for checking SET logic and firmware update behavior.
        """
        print("[MODE] SET sequence test...")

        for v in values:
            v = float(v)
            print(f"\n[TEST] Setting desired temperature to: {v:.1f} °C")

            # Try to set
            ok = self.conn.setDesiredTemp(v)
            if not ok:
                print("[FAIL] setDesiredTemp() failed (write error).")
                data = self._read_all_blocking()
                self._print_status(data)
                continue

            # Small delay to let firmware apply
            time.sleep(0.05)

            # Read back to verify (PIC value should match)
            data = self._read_all_blocking()
            self._print_status(data)

            got = float(data["desired_temp"])

            # Typical tolerance: 0.1°C since fraction is 1 decimal digit
            if abs(got - v) <= 0.11:
                print("[OK] Verified: PIC desired temperature matches requested value.")
            else:
                print("[WARN] Mismatch after SET (firmware may be overriding / not updating).")

            time.sleep(0.4)

    def _interactive_loop(self) -> None:
        """
        Interactive terminal loop:
        - Enter number to set desired temperature
        - 'r' to read status
        - 'q' to quit
        """
        print("[MODE] Interactive")
        print("Commands:")
        print("  <number>  -> set desired temperature (float allowed)")
        print("  r         -> read and print all values")
        print("  q         -> quit\n")

        while True:
            cmd = input(">>> ").strip().lower()

            if cmd == "q":
                print("[INFO] Quitting interactive mode.")
                return

            if cmd == "r":
                data = self._read_all_blocking()
                self._print_status(data)
                continue

            try:
                v = float(cmd)
            except ValueError:
                print("[INFO] Invalid input. Use number / r / q.")
                continue

            ok = self.conn.setDesiredTemp(v)
            if not ok:
                print("[FAIL] SET failed.")
                continue

            time.sleep(0.05)
            data = self._read_all_blocking()
            self._print_status(data)
            print("[OK] SET done (checked by reading back).")


def build_config_from_args() -> TestConfig:
    """Builds TestConfig from CLI args (keeps main clean)."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM1", help="Serial port, e.g., COM10")
    parser.add_argument("--baud", type=int, default=9600, help="Baud rate, e.g., 9600")
    parser.add_argument(
        "--mode",
        choices=["poll", "set", "interactive"],
        default="poll",
        help="Test mode",
    )
    parser.add_argument("--interval", type=float, default=0.5, help="Polling interval in seconds")
    parser.add_argument("--duration", type=float, default=10.0, help="Polling duration in seconds")
    parser.add_argument(
        "--set-values",
        default="18.0,20.5,22.0,24.5,26.0",
        help="Comma-separated values for set mode",
    )
    args = parser.parse_args()

    set_values: List[float] = []
    for part in str(args.set_values).split(","):
        part = part.strip()
        if not part:
            continue
        try:
            set_values.append(float(part))
        except ValueError:
            pass

    return TestConfig(
        port=args.port,
        baud=args.baud,
        mode=args.mode,
        interval=max(0.05, float(args.interval)),
        duration=max(0.2, float(args.duration)),
        set_values=set_values if set_values else [18.0, 22.0, 26.0],
    )


def main() -> int:
    """Main function (kept minimal)."""
    cfg = build_config_from_args()
    tester = AirConditionerTester(cfg)
    return tester.run()


if __name__ == "__main__":
    sys.exit(main())

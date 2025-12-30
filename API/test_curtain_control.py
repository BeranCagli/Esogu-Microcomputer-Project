# Author: 152120221098 Emre AVCI
"""
Curtain Control System - Connection Tester
------------------------------------------
This script tests the CurtainControlSystemConnection class by:
- Opening UART connection
- Reading values periodically (GET)
- Writing desired curtain status (SET) and verifying by reading back
- (Optional) Interactive mode to set values from user input

Usage example:
  python test_curtain_control.py --port COM8 --baud 9600 --mode poll
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from typing import Optional, List

# Import your class (adjust import path if needed)
# If this tester is in the same folder as curtain_control.py:
from curtain_control import CurtainControlSystemConnection


@dataclass
class TestConfig:
    """Holds test configuration parameters (OOP-friendly)."""
    port: str
    baud: int
    mode: str
    interval: float
    duration: float
    set_values: List[float]


class CurtainControlTester:
    """
    Object-oriented tester for CurtainControlSystemConnection.
    Encapsulates setup, polling, set-test, and interactive operations.
    """

    def __init__(self, cfg: TestConfig) -> None:
        self.cfg = cfg
        self.conn = CurtainControlSystemConnection(com_port=cfg.port, baud_rate=cfg.baud)

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
        Adjust if your base class uses connect()/open() etc.
        """
        # Try common open/connect method names safely
        for method_name in ("open", "connect", "open_connection"):
            if hasattr(self.conn, method_name):
                method = getattr(self.conn, method_name)
                try:
                    method()  # type: ignore[misc]
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
        curtain = self.conn.getCurtainStatus()
        temp = self.conn.getOutdoorTemp()
        press = self.conn.getOutdoorPress()
        light = self.conn.getLightIntensity()

        return {
            "curtain_status": curtain,
            "outdoor_temp": temp,
            "outdoor_press": press,
            "light_intensity": light,
        }

    def _print_status(self, data: dict) -> None:
        """Pretty prints the status dictionary."""
        print(
            f"Curtain: {data['curtain_status']:.1f}% | "
            f"Temp: {data['outdoor_temp']:.1f}°C | "
            f"Press: {data['outdoor_press']:.1f} | "
            f"Light: {data['light_intensity']:.1f} lux"
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
        Good for checking that SET logic and firmware update works.
        """
        print("[MODE] SET sequence test...")
        for v in values:
            print(f"\n[TEST] Setting curtain status to: {v:.1f}%")
            ok = self.conn.setCurtainStatus(v, retries=3)
            if not ok:
                print("[FAIL] setCurtainStatus() failed (no ACK / mismatch).")
                # Read anyway to see what PIC currently holds
                data = self._read_all_blocking()
                self._print_status(data)
                continue

            # Read back after SET to verify
            data = self._read_all_blocking()
            got = data["curtain_status"]
            self._print_status(data)

            # Tolerance consistent with your class verification
            if abs(got - float(v)) <= 0.2:
                print("[OK] Verified: PIC value matches requested value.")
            else:
                print("[WARN] Mismatch after SET (PIC may be overwriting value).")

            time.sleep(0.4)

    def _interactive_loop(self) -> None:
        """
        Interactive terminal loop:
        - Enter number to set curtain status
        - 'r' to read status
        - 'q' to quit
        """
        print("[MODE] Interactive")
        print("Commands:")
        print("  <number>  -> set curtain status (0..100, float allowed)")
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

            # Try parse float
            try:
                v = float(cmd)
            except ValueError:
                print("[INFO] Invalid input. Use number / r / q.")
                continue

            ok = self.conn.setCurtainStatus(v, retries=3)
            if not ok:
                print("[FAIL] SET failed.")
            else:
                # Read back once
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
        default="0,25.3,50,73.7,100",
        help="Comma-separated values for set mode",
    )

    args = parser.parse_args()

    set_values = []
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
        set_values=set_values if set_values else [0.0, 50.0, 100.0],
    )


def main() -> int:
    """Main function (kept minimal)."""
    cfg = build_config_from_args()
    tester = CurtainControlTester(cfg)
    return tester.run()


if __name__ == "__main__":
    sys.exit(main())

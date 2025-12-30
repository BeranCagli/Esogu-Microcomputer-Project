# Author: 152120221098 Emre AVCI
import time
from typing import Optional

import serial


class HomeAutomationSystemConnection:
    # -------------------- MEMBER VARIABLES --------------------
    # Connection parameters and runtime state used by all subsystem connections.
    _comPort: str
    _baudRate: int
    _isOpen: bool
    _uart: serial.Serial | None

    # -------------------- LIFECYCLE --------------------
    def __init__(self, com_port: str = "COM1", baud_rate: int = 9600):
        # Store user-selected COM and baudrate; UART is created on open()
        self._comPort = com_port
        self._baudRate = baud_rate
        self._isOpen = False
        self._uart = None

    def is_open(self) -> bool:
        """Return True if a serial port is open and the UART object exists."""
        return bool(self._isOpen) and (self._uart is not None)

    def open(self) -> bool:
        """
        Open UART in non-blocking mode to avoid freezing a GUI.
        timeout=0 makes read() return immediately if no byte is available.
        """
        try:
            self._uart = serial.Serial(
                port=self._comPort,
                baudrate=self._baudRate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0,            # non-blocking reads
                write_timeout=0.2,    # short write timeout to avoid stalling
                xonxoff=False,
                rtscts=False,
                dsrdtr=False,
            )

            # Allow virtual COM drivers / PICSimLab bridge to settle
            time.sleep(0.05)

            # Clear any garbage bytes that might exist immediately after opening
            try:
                self._uart.reset_input_buffer()
                self._uart.reset_output_buffer()
            except Exception:
                pass

            self._isOpen = True
            return True

        except Exception as e:
            # Reset state so callers do not use a half-open object
            self._isOpen = False
            self._uart = None
            print(f"UART open error ({self._comPort}): {e}")
            raise

    def close(self) -> bool:
        """Close UART connection and reset internal state."""
        if self._isOpen and self._uart is not None:
            try:
                self._uart.close()
            finally:
                self._uart = None
                self._isOpen = False
            return True
        return False

    # -------------------- UART HELPERS --------------------
    def _uart_flush_input(self) -> None:
        """
        Drop unread RX bytes.
        This prevents stale bytes from being interpreted as responses to a new command.
        """
        if self.is_open():
            try:
                self._uart.reset_input_buffer()
            except Exception:
                pass

    def _uart_write_byte(self, b: int) -> bool:
        """
        Write exactly one byte to UART.

        Notes:
        - flush() forces the byte out of the OS buffer immediately.
        - the small sleep can help simple firmware ISR implementations keep up,
          especially on virtual COM pairs.
        """
        if not self.is_open():
            return False
        try:
            self._uart.write(bytes([b & 0xFF]))
            self._uart.flush()
            time.sleep(0.015)
            return True
        except Exception:
            return False

    def _uart_read_byte_now(self) -> Optional[int]:
        """
        Non-blocking read of one byte.
        Returns the byte value if available, otherwise None.
        """
        if not self.is_open():
            return None
        try:
            data = self._uart.read(1)
            if data:
                return data[0]
        except Exception:
            return None
        return None

    def _uart_read_byte_deadline(self, timeout_ms: int = 80) -> Optional[int]:
        """
        Deadline-based read to avoid long blocking calls.
        Waits up to timeout_ms for a single byte, otherwise returns None.
        """
        if not self.is_open():
            return None

        deadline = time.monotonic() + (timeout_ms / 1000.0)
        while time.monotonic() < deadline:
            b = self._uart_read_byte_now()
            if b is not None:
                return b
            time.sleep(0.001)  # yield CPU briefly

        return None

    # -------------------- OVERRIDES / EXTENSION POINTS --------------------
    def update(self) -> None:
        """
        Blocking refresh hook (legacy pattern).
        Subclasses typically implement their own GET calls here.
        """
        raise NotImplementedError("update() must be implemented by subclasses")

    def handle_rx(self, cmd: int, value: int) -> None:
        """
        Async receive hook.
        Subclasses may override this to update caches when polling reads a response byte.
        """
        return

    # -------------------- CONFIGURATION --------------------
    def setComPort(self, port: str) -> None:
        """
        Set COM port string.
        Must be called before open(); changes are ignored while connected.
        """
        if not self._isOpen:
            self._comPort = port

    def setBaudRate(self, rate: int) -> None:
        """
        Set baudrate.
        Must be called before open(); changes are ignored while connected.
        """
        if not self._isOpen:
            self._baudRate = rate

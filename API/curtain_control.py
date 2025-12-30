# Author: 152120221098 Emre AVCI
import time
from base_connections import HomeAutomationSystemConnection
from protocol import (
    GET_DESIRED_CURTAIN_HIGH,
    GET_DESIRED_CURTAIN_LOW,
    GET_OUTDOOR_TEMPERATURE_HIGH,
    GET_OUTDOOR_TEMPERATURE_LOW,
    GET_OUTDOOR_PRESSURE_HIGH,
    GET_OUTDOOR_PRESSURE_LOW,
    GET_LIGHT_INTENSITY_HIGH,
    GET_LIGHT_INTENSITY_LOW,
    SET_DESIRED_VALUE_HIGH_MASK,
    SET_DESIRED_VALUE_LOW_MASK,
    DATA_6BIT_MASK,
    encode_fraction,
    decode_fraction,
    combine_int_frac,
)


class CurtainControlSystemConnection(HomeAutomationSystemConnection):
    def __init__(self, com_port: str = "COM8", baud_rate: int = 9600):
        super().__init__(com_port, baud_rate)

        # Cached decoded values exposed to the UI (floats, already combined)
        self.__curtainStatus: float = 0.0
        self.__outdoorTemperature: float = 0.0
        self.__outdoorPressure: float = 0.0
        self.__lightIntensity: float = 0.0

        # Latest raw bytes received per GET command (used by async polling)
        # We keep them separately so we can combine only when both HIGH+LOW exist.
        self._cur_h: int | None = None
        self._cur_l: int | None = None
        self._temp_h: int | None = None
        self._temp_l: int | None = None
        self._press_h: int | None = None
        self._press_l: int | None = None
        self._light_h: int | None = None
        self._light_l: int | None = None

    # -------------------- PEEK (NO UART) --------------------
    # These functions return cached values only (no serial I/O).
    # This is important for the GUI because it keeps UI updates instant and non-blocking.
    def peekCurtainStatus(self) -> float:
        return self.__curtainStatus

    def peekOutdoorTemp(self) -> float:
        return self.__outdoorTemperature

    def peekOutdoorPress(self) -> float:
        return self.__outdoorPressure

    def peekLightIntensity(self) -> float:
        return self.__lightIntensity

    # -------------------- ASYNC RX HANDLER --------------------
    # handle_rx() is called by the GUI polling loop when ONE response byte arrives.
    # cmd tells us which field this byte belongs to.
    def handle_rx(self, cmd: int, value: int) -> None:
        # Store the raw response byte into the corresponding cache slot
        if cmd == GET_DESIRED_CURTAIN_HIGH:
            self._cur_h = value
        elif cmd == GET_DESIRED_CURTAIN_LOW:
            self._cur_l = value
        elif cmd == GET_OUTDOOR_TEMPERATURE_HIGH:
            self._temp_h = value
        elif cmd == GET_OUTDOOR_TEMPERATURE_LOW:
            self._temp_l = value
        elif cmd == GET_OUTDOOR_PRESSURE_HIGH:
            self._press_h = value
        elif cmd == GET_OUTDOOR_PRESSURE_LOW:
            self._press_l = value
        elif cmd == GET_LIGHT_INTENSITY_HIGH:
            self._light_h = value
        elif cmd == GET_LIGHT_INTENSITY_LOW:
            self._light_l = value

        # Curtain status is represented as HIGH=int part, LOW=fraction part
        # Only update the float when both bytes are available.
        if (self._cur_h is not None) and (self._cur_l is not None):
            self.__curtainStatus = combine_int_frac(self._cur_h, self._cur_l)

        # Temperature uses a signed integer for the HIGH byte (negative temps possible).
        # LOW contains the fractional digit/part.
        if (self._temp_h is not None) and (self._temp_l is not None):
            signed_h = self._temp_h - 256 if self._temp_h >= 128 else self._temp_h
            self.__outdoorTemperature = combine_int_frac(signed_h, self._temp_l)

        # Light intensity is also combined from HIGH+LOW like other fixed-point values.
        if (self._light_h is not None) and (self._light_l is not None):
            self.__lightIntensity = combine_int_frac(self._light_h, self._light_l)

        # Pressure handling depends on firmware representation:
        # - Some firmware versions send "H + (L/10)" like fixed-point with 1 decimal.
        # - Others send a raw 16-bit value (H<<8 | L).
        # This heuristic keeps compatibility with both.
        if (self._press_h is not None) and (self._press_l is not None):
            if self._press_l <= 9 and self._press_h <= 200:
                self.__outdoorPressure = float(self._press_h) + (self._press_l / 10.0)
            else:
                self.__outdoorPressure = float((self._press_h << 8) | self._press_l)

    # -------------------- UPDATE (LEGACY) --------------------
    # Legacy blocking update method. The GUI now prefers async polling, but this remains usable.
    def update(self) -> None:
        if not self.is_open():
            return
        self.getCurtainStatus()
        self.getOutdoorTemp()
        self.getOutdoorPress()
        self.getLightIntensity()

    # -------------------- SET (BLOCKING WITH VERIFY) --------------------
    # Sends a desired curtain value using protocol frames and then verifies by reading it back.
    # Verification is important because serial collisions or firmware timing can drop bytes.
    def setCurtainStatus(self, std: float, retries: int = 3) -> bool:
        if not self.is_open():
            return False

        # Clamp input to valid range for curtain percentage
        val = max(0.0, min(100.0, float(std)))
        integral = int(val)

        # Fraction is encoded as a small digit that fits into 6-bit payload
        frac_digit = encode_fraction(val) & 0x3F

        # Protocol frames:
        #   HIGH frame: 11dddddd (mask selects "high/int" payload)
        #   LOW  frame: 10dddddd (mask selects "low/frac" payload)
        frac_byte = SET_DESIRED_VALUE_LOW_MASK | (frac_digit & DATA_6BIT_MASK)
        int_byte = SET_DESIRED_VALUE_HIGH_MASK | (integral & DATA_6BIT_MASK)

        for _ in range(retries):
            try:
                # Flush RX before sending to avoid mixing old responses with new ones
                self._uart_flush_input()

                # Send order matters: we send integral first, then fractional.
                # This should match the firmware's expected parsing order.
                if not self._uart_write_byte(int_byte):
                    continue
                time.sleep(0.01)  # small gap helps some firmware UART handlers

                if not self._uart_write_byte(frac_byte):
                    continue
                time.sleep(0.01)

                # Read back the stored value to confirm the firmware accepted it
                h = self._get_byte(GET_DESIRED_CURTAIN_HIGH, timeout_ms=150)
                l = self._get_byte(GET_DESIRED_CURTAIN_LOW, timeout_ms=150)
                if (h is None) or (l is None):
                    continue

                got = combine_int_frac(h, l)

                # Accept small tolerance due to decimal encoding/rounding
                if abs(got - val) <= 0.11:
                    # Update internal caches so UI reflects the new state immediately
                    self._cur_h, self._cur_l = h, l
                    self.__curtainStatus = got
                    return True

            except Exception:
                # Retry on any UART/parsing exception
                pass

        return False

    # -------------------- GET (BLOCKING, SINGLE BYTE) --------------------
    # _get_byte issues one GET command and waits for a single response byte.
    # It is used by blocking getters and by SET verification.
    def _get_byte(self, cmd: int, timeout_ms: int = 80) -> int | None:
        if not self.is_open():
            return None

        # Flush to ensure the next byte is for THIS command
        self._uart_flush_input()

        if not self._uart_write_byte(cmd):
            return None

        # Deadline-based read prevents UI freeze in case the firmware does not respond
        return self._uart_read_byte_deadline(timeout_ms=timeout_ms)

    # -------------------- GETTERS (BLOCKING, DECODED) --------------------
    # These methods actively query the PIC and update caches if successful.
    # If a read fails, they return the last cached value.
    def getCurtainStatus(self) -> float:
        h = self._get_byte(GET_DESIRED_CURTAIN_HIGH)
        if h is None:
            return self.__curtainStatus

        l = self._get_byte(GET_DESIRED_CURTAIN_LOW)
        if l is None:
            return self.__curtainStatus

        self._cur_h, self._cur_l = h, l
        self.__curtainStatus = combine_int_frac(h, l)
        return self.__curtainStatus

    def getOutdoorTemp(self) -> float:
        # Temperature read order here is LOW then HIGH (kept as-is to match your firmware behavior)
        l = self._get_byte(GET_OUTDOOR_TEMPERATURE_LOW)
        if l is None:
            return self.__outdoorTemperature

        h = self._get_byte(GET_OUTDOOR_TEMPERATURE_HIGH)
        if h is None:
            return self.__outdoorTemperature

        self._temp_h, self._temp_l = h, l
        signed_h = h - 256 if h >= 128 else h
        self.__outdoorTemperature = combine_int_frac(signed_h, l)
        return self.__outdoorTemperature

    def getOutdoorPress(self) -> float:
        h = self._get_byte(GET_OUTDOOR_PRESSURE_HIGH)
        if h is None:
            return self.__outdoorPressure

        l = self._get_byte(GET_OUTDOOR_PRESSURE_LOW)
        if l is None:
            return self.__outdoorPressure

        self._press_h, self._press_l = h, l

        # Same dual-format heuristic as in handle_rx()
        if l <= 9 and h <= 200:
            self.__outdoorPressure = float(h) + (l / 10.0)
        else:
            self.__outdoorPressure = float((h << 8) | l)

        return self.__outdoorPressure

    def getLightIntensity(self) -> float:
        h = self._get_byte(GET_LIGHT_INTENSITY_HIGH)
        if h is None:
            return self.__lightIntensity

        l = self._get_byte(GET_LIGHT_INTENSITY_LOW)
        if l is None:
            return self.__lightIntensity

        self._light_h, self._light_l = h, l
        self.__lightIntensity = combine_int_frac(h, l)
        return self.__lightIntensity

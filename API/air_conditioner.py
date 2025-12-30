# Author: 152120221098 Emre AVCI
from base_connections import HomeAutomationSystemConnection
from protocol import (
    GET_DESIRED_TEMPERATURE_HIGH,
    GET_DESIRED_TEMPERATURE_LOW,
    GET_AMBIENT_TEMPERATURE_HIGH,
    GET_AMBIENT_TEMPERATURE_LOW,
    GET_FAN_SPEED,
    SET_DESIRED_VALUE_HIGH_MASK,
    SET_DESIRED_VALUE_LOW_MASK,
    DATA_6BIT_MASK,
    encode_fraction,
    combine_int_frac,
)


class AirConditionerControlSystemConnection(HomeAutomationSystemConnection):
    def __init__(self, com_port: str = "COM8", baud_rate: int = 9600):
        super().__init__(com_port, baud_rate)

        # Cached decoded values exposed to the UI (floats already combined)
        self.__desiredTemperature: float = 0.0
        self.__ambientTemperature: float = 0.0
        self.__fanSpeed: int = 0

        # Latest raw bytes received per GET command (used by async polling)
        # We only update the float when both HIGH+LOW bytes are available.
        self._desired_h: int | None = None
        self._desired_l: int | None = None
        self._ambient_h: int | None = None
        self._ambient_l: int | None = None

    # -------------------- PEEK (NO UART) --------------------
    # These methods return cached values only (no serial I/O).
    # This keeps GUI updates fast and prevents UI blocking.
    def peekDesiredTemp(self) -> float:
        return self.__desiredTemperature

    def peekAmbientTemp(self) -> float:
        return self.__ambientTemperature

    def peekFanSpeed(self) -> int:
        return self.__fanSpeed

    # -------------------- ASYNC RX HANDLER --------------------
    # handle_rx() is called by the GUI polling loop when ONE response byte arrives.
    # cmd indicates which GET request produced this response byte.
    def handle_rx(self, cmd: int, value: int) -> None:
        # Store raw bytes into their per-field slots
        if cmd == GET_DESIRED_TEMPERATURE_HIGH:
            self._desired_h = value
        elif cmd == GET_DESIRED_TEMPERATURE_LOW:
            self._desired_l = value
        elif cmd == GET_AMBIENT_TEMPERATURE_HIGH:
            self._ambient_h = value
        elif cmd == GET_AMBIENT_TEMPERATURE_LOW:
            self._ambient_l = value
        elif cmd == GET_FAN_SPEED:
            # Fan speed is a single byte value (no HIGH/LOW pair)
            self.__fanSpeed = value

        # Combine desired temp when both bytes are available
        if (self._desired_h is not None) and (self._desired_l is not None):
            self.__desiredTemperature = combine_int_frac(self._desired_h, self._desired_l)

        # Combine ambient temp when both bytes are available
        if (self._ambient_h is not None) and (self._ambient_l is not None):
            self.__ambientTemperature = combine_int_frac(self._ambient_h, self._ambient_l)

    # -------------------- UPDATE (LEGACY) --------------------
    # Blocking refresh path kept for compatibility (async polling is preferred for UI).
    def update(self) -> None:
        """Legacy blocking refresh with small deadlines (kept for compatibility)."""
        if not self.is_open():
            return
        self.getDesiredTemp()
        self.getAmbientTemp()
        self.getFanSpeed()

    # -------------------- SET (BLOCKING, NO VERIFY) --------------------
    # Sends desired temperature as two protocol frames (HIGH=int, LOW=fraction).
    # This method updates the cache optimistically (assumes PIC accepted the write).
    def setDesiredTemp(self, temp: float) -> bool:
        if not self.is_open():
            return False

        # Protocol payload uses 6-bit data; values are masked accordingly
        integral = int(temp) & DATA_6BIT_MASK
        fractional = encode_fraction(temp) & DATA_6BIT_MASK

        # Send HIGH first, then LOW (matches most firmware parsers)
        if not self._uart_write_byte(SET_DESIRED_VALUE_HIGH_MASK | integral):
            return False
        if not self._uart_write_byte(SET_DESIRED_VALUE_LOW_MASK | fractional):
            return False

        # Optimistic cache update so UI reflects the new target immediately
        self.__desiredTemperature = float(integral) + (fractional / 10.0)
        return True

    # -------------------- GET (BLOCKING, SINGLE BYTE) --------------------
    # _get_byte sends one GET command and waits for one response byte.
    # Flushing RX first prevents stale bytes from being interpreted as new responses.
    def _get_byte(self, cmd: int, timeout_ms: int = 80) -> int | None:
        if not self.is_open():
            return None

        self._uart_flush_input()

        if not self._uart_write_byte(cmd):
            return None

        # Deadline-based read prevents permanent blocking if PIC does not respond
        return self._uart_read_byte_deadline(timeout_ms=timeout_ms)

    # -------------------- GETTERS (BLOCKING, DECODED) --------------------
    # These actively query the PIC and update caches if successful.
    # If any step fails, they return the last cached value.
    def getFanSpeed(self) -> int:
        b = self._get_byte(GET_FAN_SPEED)
        if b is None:
            return self.__fanSpeed
        self.__fanSpeed = b
        return self.__fanSpeed

    def getDesiredTemp(self) -> float:
        h = self._get_byte(GET_DESIRED_TEMPERATURE_HIGH)
        if h is None:
            return self.__desiredTemperature

        l = self._get_byte(GET_DESIRED_TEMPERATURE_LOW)
        if l is None:
            return self.__desiredTemperature

        self._desired_h, self._desired_l = h, l
        self.__desiredTemperature = combine_int_frac(h, l)
        return self.__desiredTemperature

    def getAmbientTemp(self) -> float:
        # Read order is LOW then HIGH here (kept as-is to match firmware behavior)
        l = self._get_byte(GET_AMBIENT_TEMPERATURE_LOW)
        if l is None:
            return self.__ambientTemperature

        h = self._get_byte(GET_AMBIENT_TEMPERATURE_HIGH)
        if h is None:
            return self.__ambientTemperature

        self._ambient_h, self._ambient_l = h, l
        self.__ambientTemperature = combine_int_frac(h, l)
        return self.__ambientTemperature

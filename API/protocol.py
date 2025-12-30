# Author: 152120221098 Emre AVCI
# ==============================================================
# UART BIT-LEVEL PROTOCOL DEFINITIONS
# ==============================================================

# All messages are 8-bit (1 byte).

# BIT NOTATION: B7 B6 B5 B4 B3 B2 B1 B0
# - GET commands:      0xxxxxxx
# - SET commands:      10xxxxxx (fractional part)
# - SET commands:      11xxxxxx (integral part)


# In current UART.asm, fractional bytes are clamped to 0..9 (1 decimal digit),


# ==============================================================

# GET COMMANDS – AIR CONDITIONER BOARD (R2.1.x)
GET_DESIRED_TEMPERATURE_LOW   = 0b00000001
GET_DESIRED_TEMPERATURE_HIGH  = 0b00000010

GET_AMBIENT_TEMPERATURE_LOW   = 0b00000011
GET_AMBIENT_TEMPERATURE_HIGH  = 0b00000100

GET_FAN_SPEED                 = 0b00000101

# GET COMMANDS – CURTAIN BOARD (R2.2.x)
GET_DESIRED_CURTAIN_LOW       = 0b00000001
GET_DESIRED_CURTAIN_HIGH      = 0b00000010

GET_OUTDOOR_TEMPERATURE_LOW   = 0b00000011
GET_OUTDOOR_TEMPERATURE_HIGH  = 0b00000100

GET_OUTDOOR_PRESSURE_LOW      = 0b00000101
GET_OUTDOOR_PRESSURE_HIGH     = 0b00000110

GET_LIGHT_INTENSITY_LOW       = 0b00000111
GET_LIGHT_INTENSITY_HIGH      = 0b00001000

# SET COMMANDS (COMMON)
SET_DESIRED_VALUE_LOW_MASK    = 0b10000000
SET_DESIRED_VALUE_HIGH_MASK   = 0b11000000

# HELPERS
DATA_6BIT_MASK                = 0b00111111
FRACTION_DIVISOR_6BIT         = 64.0
FRACTION_DIVISOR_1DIGIT       = 10.0


def decode_fraction(low: int) -> float:
    """Decode fractional byte to float fraction."""
    if low <= 9:
        return low / FRACTION_DIVISOR_1DIGIT
    return low / FRACTION_DIVISOR_6BIT


def encode_fraction(value: float) -> int:
    """Encode float fraction. Prefer 1-digitencoding (0..9)."""
    frac = value - int(value)
    if frac < 0:
        frac = -frac
    d = int(round(frac * FRACTION_DIVISOR_1DIGIT))
    if d >= 10:
        d = 0
    if d < 0:
        d = 0
    return d & DATA_6BIT_MASK


def combine_int_frac(high: int, low: int) -> float:
    return float(high) + decode_fraction(int(low))

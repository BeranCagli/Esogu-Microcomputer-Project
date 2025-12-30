;==============================================================================
; # Author: 152120231074 Beran Ça?l?
;
; LCD Module - 16x2 Character Display (HD44780)
; 8-bit mode (full PORTD)
; PORTD (RD0-RD7) = data bus (D0-D7)
; PORTE = control signals (RE2=RS, RE1=EN)
;==============================================================================

; LCD Control Pins
#include <xc.inc>

#ifndef _STATUS_POSITIONS_DEFINED
#define _STATUS_POSITIONS_DEFINED
STATUS_C_POSITION       EQU 0
STATUS_Z_POSITION       EQU 2
STATUS_RP0_POSITION     EQU 5
STATUS_RP1_POSITION     EQU 6
#endif
#define LCD_RS  PORTE, 2    ; Register Select
#define LCD_EN  PORTE, 1    ; Enable Signal

; ---------------- RAM VARIABLES ----------------
LCD_Data              EQU 0x70
LCD_Temp              EQU 0x71
LCD_Digit_1000        EQU 0x72
LCD_Digit_100         EQU 0x73
LCD_Digit_10          EQU 0x74
LCD_Digit_1           EQU 0x75
Math_Temp1            EQU 0x76
Math_Temp2            EQU 0x77

; Initialize LCD in 8-bit mode
LCD_INIT:
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    BCF     STATUS, STATUS_RP1_POSITION
    
    CALL    LCD_DELAY_20MS      ; Power-on delay
    
    BCF     LCD_RS              ; Command mode
    BCF     LCD_EN              ; Disable LCD
    
    ; Function Set: 8-bit, 2-line, 5x7 font
    MOVLW   0x38
    CALL    LCD_SEND_CMD
    CALL    LCD_DELAY_5MS
    
    ; Repeat Function Set (datasheet spec)
    MOVLW   0x38
    CALL    LCD_SEND_CMD
    CALL    LCD_DELAY_5MS
    
    MOVLW   0x38
    CALL    LCD_SEND_CMD
    CALL    LCD_DELAY_5MS
    
    ; Display Control: Display ON, Cursor OFF, Blink OFF
    MOVLW   0x0C
    CALL    LCD_SEND_CMD
    
    ; Clear Display
    MOVLW   0x01
    CALL    LCD_SEND_CMD
    CALL    LCD_DELAY_2MS
    
    ; Entry Mode: Increment cursor, No shift
    MOVLW   0x06
    CALL    LCD_SEND_CMD
    
    RETURN

; Send command to LCD (W has the command)
LCD_SEND_CMD:
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    BCF     STATUS, STATUS_RP1_POSITION
    
    BCF     LCD_RS              ; RS=0 for command
    MOVWF   PORTD               ; Send command to data bus
    
    ; Pulse Enable pin
    BSF     LCD_EN
    NOP
    NOP
    BCF     LCD_EN
    
    CALL    LCD_DELAY_2MS       ; Wait for execution
    RETURN

; Send data (character) to LCD
LCD_SEND_DATA:
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    BCF     STATUS, STATUS_RP1_POSITION
    
    BSF     LCD_RS              ; RS=1 for data
    MOVWF   PORTD               ; Send data to bus
    
    ; Pulse Enable pin
    BSF     LCD_EN
    NOP
    NOP
    BCF     LCD_EN
    
    CALL    LCD_DELAY_50US      ; Short delay for data write
    RETURN

; Clear the LCD screen
LCD_CLEAR:
    MOVLW   0x01                ; Clear display command
    CALL    LCD_SEND_CMD
    CALL    LCD_DELAY_2MS
    RETURN

; Update LCD with all current values
; Line 1: "signxtxt.xt C xpxpxpxphPa"
; Line 2: "xlxlxl.xlLux xcxc.xc%"
UPDATE_DISPLAY:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    ; ========== LINE 1: Temperature and Pressure ==========
    MOVLW   0x80                ; Set cursor to Line 1 start
    CALL    LCD_SEND_CMD
    
    ; 1. Temperature Sign
    BTFSC   Outdoor_Temp, 7     ; Check sign bit
    GOTO    DISP_TEMP_NEG
    MOVLW   '+'
    CALL    LCD_SEND_DATA
    GOTO    DISP_TEMP_CONT
DISP_TEMP_NEG:
    MOVLW   '-'
    CALL    LCD_SEND_DATA
    
DISP_TEMP_CONT:
    ; 2-3. Temperature digits (Integer)
    BTFSC   Outdoor_Temp, 7     ; Handle 2's complement if neg
    GOTO    DISP_TEMP_ABS
    MOVF    Outdoor_Temp, W
    GOTO    DISP_TEMP_CONV
DISP_TEMP_ABS:
    COMF    Outdoor_Temp, W
    ADDLW   1
DISP_TEMP_CONV:
    CALL    BIN_TO_ASCII        ; Convert binary to ASCII
    
    MOVF    LCD_Digit_10, W     ; Tens digit
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_1, W      ; Ones digit
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    ; 4. Decimal point
    MOVLW   '.'
    CALL    LCD_SEND_DATA
    
    ; 5. Temperature fraction
    MOVF    Outdoor_Temp_Frac, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    ; 6-7. Degree and Unit
    MOVLW   0xDF                ; Degree symbol
    CALL    LCD_SEND_DATA
    MOVLW   'C'
    CALL    LCD_SEND_DATA
    
    ; 8-9. Spacing
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    
    ; 10-13. Pressure (4 digits)
    CALL    PRESSURE_TO_ASCII
    
    MOVF    LCD_Digit_1000, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_100, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_10, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_1, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    ; 14-16. Pressure Unit "hPa "
    MOVLW   'h'
    CALL    LCD_SEND_DATA
    MOVLW   'P'
    CALL    LCD_SEND_DATA
    MOVLW   'a'
    CALL    LCD_SEND_DATA
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    
    ; ========== LINE 2: Light and Curtain ==========
    MOVLW   0xC0                ; Set cursor to Line 2 start
    CALL    LCD_SEND_CMD
    
    ; 1-3. Light intensity (0-255 scaled)
    MOVF    Light_Intensity, W
    CALL    BIN_TO_ASCII_3
    
    MOVF    LCD_Digit_100, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_10, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_1, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    ; 4. Decimal point
    MOVLW   '.'
    CALL    LCD_SEND_DATA
    
    ; 5. Light fraction
    MOVF    Light_Intensity_Frac, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    ; 6-8. Unit "Lux"
    MOVLW   'L'
    CALL    LCD_SEND_DATA
    MOVLW   'u'
    CALL    LCD_SEND_DATA
    MOVLW   'x'
    CALL    LCD_SEND_DATA
    
    ; 9. Space
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    
    ; 10-11. Curtain Position Logic
    MOVF    Current_Curtain, W
    SUBLW   100
    BTFSS   STATUS, STATUS_Z_POSITION
    GOTO    CURTAIN_NORMAL

    ; Case: 100% (Hardcoded to fix 3-digit display)
    MOVLW   '1'
    CALL    LCD_SEND_DATA
    MOVLW   '0'
    CALL    LCD_SEND_DATA
    MOVLW   '0'
    CALL    LCD_SEND_DATA
    GOTO    CURTAIN_DECIMAL

CURTAIN_NORMAL:
    ; Case: 0-99%
    MOVF    Current_Curtain, W
    CALL    BIN_TO_ASCII
    
    MOVF    LCD_Digit_10, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    MOVF    LCD_Digit_1, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA

CURTAIN_DECIMAL:
    ; 12. Decimal point
    MOVLW   '.'
    CALL    LCD_SEND_DATA
    
    ; 13. Curtain fraction
    MOVF    Current_Curtain_Frac, W
    ADDLW   '0'
    CALL    LCD_SEND_DATA
    
    ; 14. Unit '%'
    MOVLW   '%'
    CALL    LCD_SEND_DATA
    
    ; 15-16. Padding
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    MOVLW   ' '
    CALL    LCD_SEND_DATA
    
    RETURN

; Convert binary to 2 ASCII digits (0-99)
BIN_TO_ASCII:
    MOVWF   Math_Temp1
    CLRF    LCD_Digit_10
    
    ; Subtract 10 repeatedly to find tens digit
BIN_ASCII_TENS:
    MOVF    Math_Temp1, W
    SUBLW   9
    BTFSC   STATUS, STATUS_C_POSITION   ; If remainder <= 9, done
    GOTO    BIN_ASCII_ONES
    
    MOVLW   10
    SUBWF   Math_Temp1, F
    INCF    LCD_Digit_10, F
    GOTO    BIN_ASCII_TENS
    
BIN_ASCII_ONES:
    MOVF    Math_Temp1, W
    MOVWF   LCD_Digit_1         ; Remainder is ones digit
    RETURN

; Convert binary to 3 ASCII digits (0-255)
BIN_TO_ASCII_3:
    MOVWF   Math_Temp1
    CLRF    LCD_Digit_100
    CLRF    LCD_Digit_10
    
    ; Extract hundreds
BIN_ASCII_HUNDREDS:
    MOVF    Math_Temp1, W
    SUBLW   99
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    BIN_ASCII_3_TENS
    
    MOVLW   100
    SUBWF   Math_Temp1, F
    INCF    LCD_Digit_100, F
    GOTO    BIN_ASCII_HUNDREDS
    
    ; Extract tens
BIN_ASCII_3_TENS:
    MOVF    Math_Temp1, W
    SUBLW   9
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    BIN_ASCII_3_ONES
    
    MOVLW   10
    SUBWF   Math_Temp1, F
    INCF    LCD_Digit_10, F
    GOTO    BIN_ASCII_3_TENS
    
BIN_ASCII_3_ONES:
    MOVF    Math_Temp1, W
    MOVWF   LCD_Digit_1
    RETURN

; Convert 16-bit pressure to 4 ASCII digits
; Input: Outdoor_Press_H:L
PRESSURE_TO_ASCII:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    ; Load 16-bit value
    MOVF    Outdoor_Press_L, W
    MOVWF   Math_Temp1          ; Low byte
    MOVF    Outdoor_Press_H, W
    MOVWF   Math_Temp2          ; High byte
    
    CLRF    LCD_Digit_1000
    CLRF    LCD_Digit_100
    CLRF    LCD_Digit_10
    CLRF    LCD_Digit_1
    
    ; Extract thousands (Subtract 1000 = 0x03E8)
PRESS_THOUSANDS:
    MOVF    Math_Temp2, W
    SUBLW   0x03                ; Check High byte
    BTFSS   STATUS, STATUS_C_POSITION
    GOTO    PRESS_SUB_1000      ; High > 3, subtract
    BTFSS   STATUS, STATUS_Z_POSITION
    GOTO    PRESS_HUNDREDS      ; High < 3, done with thousands
    ; High byte == 3, check Low byte vs 0xE7
    MOVF    Math_Temp1, W
    SUBLW   0xE7
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    PRESS_HUNDREDS      ; Value < 1000
    
PRESS_SUB_1000:
    MOVLW   0xE8
    SUBWF   Math_Temp1, F       ; Subtract Low
    BTFSS   STATUS, STATUS_C_POSITION
    DECF    Math_Temp2, F       ; Borrow from High
    MOVLW   0x03
    SUBWF   Math_Temp2, F       ; Subtract High
    INCF    LCD_Digit_1000, F
    GOTO    PRESS_THOUSANDS
    
    ; Extract hundreds
PRESS_HUNDREDS:
    MOVF    Math_Temp2, F
    BTFSS   STATUS, STATUS_Z_POSITION ; If High byte > 0
    GOTO    PRESS_SUB_100
    MOVF    Math_Temp1, W
    SUBLW   99
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    PRESS_TENS

PRESS_SUB_100:
    MOVLW   100
    SUBWF   Math_Temp1, F
    BTFSS   STATUS, STATUS_C_POSITION
    DECF    Math_Temp2, F       ; Borrow
    INCF    LCD_Digit_100, F
    GOTO    PRESS_HUNDREDS
    
    ; Extract tens
PRESS_TENS:
    MOVF    Math_Temp1, W
    SUBLW   9
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    PRESS_ONES
    
    MOVLW   10
    SUBWF   Math_Temp1, F
    INCF    LCD_Digit_10, F
    GOTO    PRESS_TENS
    
PRESS_ONES:
    MOVF    Math_Temp1, W
    MOVWF   LCD_Digit_1
    RETURN

;==============================================================================
; DELAY FUNCTIONS
;==============================================================================
LCD_DELAY_20MS:
    MOVLW   20
    MOVWF   Math_Temp1
DELAY_20MS_LOOP:
    CALL    LCD_DELAY_1MS
    DECFSZ  Math_Temp1, F
    GOTO    DELAY_20MS_LOOP
    RETURN

LCD_DELAY_5MS:
    MOVLW   5
    MOVWF   Math_Temp1
DELAY_5MS_LOOP:
    CALL    LCD_DELAY_1MS
    DECFSZ  Math_Temp1, F
    GOTO    DELAY_5MS_LOOP
    RETURN

LCD_DELAY_2MS:
    MOVLW   2
    MOVWF   Math_Temp1
DELAY_2MS_LOOP:
    CALL    LCD_DELAY_1MS
    DECFSZ  Math_Temp1, F
    GOTO    DELAY_2MS_LOOP
    RETURN

LCD_DELAY_1MS:
    ; 1ms at 20MHz = ~5000 cycles
    MOVLW   200
    MOVWF   Math_Temp2
DELAY_1MS_LOOP:
    NOP
    NOP
    NOP
    NOP
    NOP
    DECFSZ  Math_Temp2, F
    GOTO    DELAY_1MS_LOOP
    RETURN

LCD_DELAY_50US:
    ; 50us at 20MHz = ~250 cycles
    MOVLW   82
    MOVWF   Math_Temp2
DELAY_50US_LOOP:
    DECFSZ  Math_Temp2, F
    GOTO    DELAY_50US_LOOP
    RETURN
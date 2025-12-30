;==============================================================================
; # Author: 152120231074 Beran Ça?l?
;
; Board #2 - Curtain Control System (PIC16F877A)
; Main program
;
;==============================================================================

#include <xc.inc>

#define _STATUS_POSITIONS_DEFINED
#define _ADC_POSITIONS_DEFINED

; ================= BIT POSITION CONSTANTS =================
; STATUS register bits (PIC16F877A)
STATUS_C_POSITION       EQU 0
STATUS_Z_POSITION       EQU 2
STATUS_RP0_POSITION     EQU 5
STATUS_RP1_POSITION     EQU 6

; INTCON bits
INTCON_PEIE_POSITION    EQU 6
INTCON_GIE_POSITION     EQU 7

; PIR1 / PIE1 bits
PIR1_SSPIF_POSITION     EQU 3
PIR1_TXIF_POSITION      EQU 4
PIR1_RCIF_POSITION      EQU 5

PIE1_SSPIE_POSITION     EQU 3
PIE1_TXIE_POSITION      EQU 4
PIE1_RCIE_POSITION      EQU 5

; RCSTA bits
RCSTA_OERR_POSITION     EQU 1
RCSTA_FERR_POSITION     EQU 2
RCSTA_CREN_POSITION     EQU 4

; TXSTA bits
TXSTA_TRMT_POSITION     EQU 1

; MSSP / I2C bits (SSPCON2)
SSPCON2_SEN_POSITION        EQU 0
SSPCON2_RSEN_POSITION       EQU 1
SSPCON2_PEN_POSITION        EQU 2
SSPCON2_RCEN_POSITION       EQU 3
SSPCON2_ACKEN_POSITION      EQU 4
SSPCON2_ACKDT_POSITION      EQU 5
SSPCON2_ACKSTAT_POSITION    EQU 6

; MSSP / I2C bits (SSPSTAT)
SSPSTAT_RW_POSITION         EQU 2   ; R/W (1=read,0=write)

; ================= SHARED RAM MAP (Bank0 GPR) =================
; Step motor variables (R2.2.1-1..2)
Current_Curtain          EQU 0x60    ; current curtain (%) integral
Desired_Curtain          EQU 0x61    ; desired curtain (%) integral
Step_Index               EQU 0x62    ; Motor step index (0-3)
Step_Counter             EQU 0x63    ; Step counter for interpolation
Current_Curtain_Frac     EQU 0x64    ; 0..9 (0.0..0.9)

Desired_Curtain_Frac     EQU 0x65    ; desired curtain fractional 0..9

; LDR (R2.2.2-1)
Light_Intensity          EQU 0x66    ; xxx integral (0..999)
Light_Intensity_Frac     EQU 0x67    ; 0..9

; BMP180 (R2.2.3-1..2)
Outdoor_Temp             EQU 0x68    ; temperature integral (00..99)
Outdoor_Temp_Frac        EQU 0x69    ; 0..9

Outdoor_Press_H          EQU 0x6A    ; pressure 16-bit high
Outdoor_Press_L          EQU 0x6B    ; pressure 16-bit low

; Scratch bytes (shared, NOT in ISR at same time)
ISR_Math_Temp1           EQU 0x52
ISR_Math_Temp2           EQU 0x53
ISR_Math_Temp3           EQU 0x54
ISR_Math_Temp4           EQU 0x55
ISR_Math_Temp5           EQU 0x56

; ISR save bytes
ISR_Save_W               EQU 0x57
ISR_Save_STATUS          EQU 0x58

; ---------------- Control arbitration (UART vs Sensors) ----------------
Control_Mode             EQU 0x5A    ; 0 = sensors (LDR/POT), 1 = UART override
Pot_Value                EQU 0x5B    ; latest potentiometer % (0..100)
Pot_Last                 EQU 0x5C    ; last stable pot % used for change detection
; ------------------------------------------------------------------------

; ADCON0 bits
ADCON0_GO_DONE_POSITION  EQU 2

; ================= CONFIG =================
config FOSC  = HS
config WDTE  = OFF
config PWRTE = ON
config BOREN = ON
config LVP   = OFF
config CPD   = OFF
config CP    = OFF
config WRT   = OFF
config DEBUG = OFF

; ================= RESET VECTOR =================
PSECT resetVec, class=CODE, delta=2
ORG 0x0000
    GOTO    START

; ================= INTERRUPT VECTOR =================
PSECT intVec, class=CODE, delta=2
ORG 0x0004
    GOTO    ISR

; ================= MAIN CODE =================
PSECT code, class=CODE, delta=2
ORG 0x0006

START:
    ; Force Bank0
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION

    CALL    PORT_INIT           ; Initialize I/O ports

    ; Module init
    CALL    LCD_INIT
    CALL    UART_INIT
    CALL    I2C_INIT
    CALL    MOTOR_INIT
    CALL    LDR_INIT
    CALL    POT_INIT

    ; Init arbitration state
    CLRF    Control_Mode              ; Start in sensor mode
    CALL    READ_POT_RAW              ; Initial pot read
    MOVF    Pot_Value, W
    MOVWF   Pot_Last
    MOVWF   Desired_Curtain

    ; Clear fractional bytes (start at .0)
    CLRF    Desired_Curtain_Frac
    CLRF    Light_Intensity_Frac
    CLRF    Outdoor_Temp_Frac
    CLRF    Current_Curtain_Frac

MAIN_LOOP:
    ; -----------------------------------------------------------
    ; LOGIC: LDR PRIORITY CONTROL
    ; -----------------------------------------------------------
    
    ; 1) Read LDR (Update light level)
    CALL    READ_LDR

    ; 2) Check Darkness (Threshold = 30)
    ; If LDR < 30 (Night), skip Potentiometer logic.
    ; Motor stays at LDR set position (100% closed).
    
    MOVF    Light_Intensity, W
    SUBLW   30                          ; W = 30 - Light_Intensity
    BTFSC   STATUS, STATUS_C_POSITION   ; Carry set if Light <= 30
    GOTO    SKIP_POT_READ               ; Dark -> Skip pot

    ; 3) Bright: Check Potentiometer
    CALL    READ_POT_RAW                ; Read raw ADC, update Pot_Value

    ; Calculate Absolute Difference |Pot_Value - Pot_Last|
    MOVF    Pot_Value, W
    SUBWF   Pot_Last, W                 ; W = Pot_Last - Pot_Value
    BTFSC   STATUS, STATUS_C_POSITION   ; Check polarity
    GOTO    _POT_ABS_OK
    MOVF    Pot_Last, W
    SUBWF   Pot_Value, W                ; W = Pot_Value - Pot_Last
_POT_ABS_OK:
    MOVWF   ISR_Math_Temp1              ; Store Difference

    ; Check Control Mode
    MOVF    Control_Mode, W
    BTFSC   STATUS, STATUS_Z_POSITION   ; If Mode = 0 (Sensors)
    GOTO    _SENSOR_MODE

    ; If Mode = 1 (UART Override):
    ; Only revert to Pot if change > 2% (Deadband)
    MOVLW   2
    SUBWF   ISR_Math_Temp1, W           ; Diff - 2
    BTFSS   STATUS, STATUS_C_POSITION   ; If Diff < 2
    GOTO    SKIP_POT_READ               ; Keep UART value

    ; Pot moved significantly -> Revert to Sensor Mode
    CLRF    Control_Mode

_SENSOR_MODE:
    MOVF    Pot_Value, W
    MOVWF   Desired_Curtain             ; Update Target
    MOVWF   Pot_Last                    ; Update Last Position

SKIP_POT_READ:
    ; 4) Update Display
    CALL    UPDATE_DISPLAY

    ; 5) Motor Control (Non-blocking step)
    CALL    CONTROL_MOTOR

    ; 6) BMP180 Sensor Reads (Temp & Pressure)
    CALL    READ_BMP180_TEMP
    CALL    READ_BMP180_PRESS

    ; System Pacing Delay
    CALL    delay10ms

    GOTO    MAIN_LOOP

; ================= INTERRUPT SERVICE ROUTINE =================
ISR:
    ; Save Context
    MOVWF   ISR_Save_W
    SWAPF   STATUS, W
    MOVWF   ISR_Save_STATUS

    ; Select Bank0
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION

    ; Check UART RX Interrupt
    BTFSS   PIR1, PIR1_RCIF_POSITION
    GOTO    ISR_RESTORE

    CALL    UART_ISR            ; Handle UART Data

ISR_RESTORE:
    ; Restore Context
    SWAPF   ISR_Save_STATUS, W
    MOVWF   STATUS
    SWAPF   ISR_Save_W, F
    SWAPF   ISR_Save_W, W
    RETFIE

; ================= PORT + ADC INIT =================
PORT_INIT:
    ; Bank1 for TRIS/ADCON1
    BSF     STATUS, STATUS_RP0_POSITION

    ; TRISA: RA0(AN0), RA2(AN2) Inputs
    MOVLW   00000111B
    MOVWF   TRISA

    ; TRISB: RB0-3 Out (Motor), RB4 In (LDR Dig)
    MOVLW   00010000B
    MOVWF   TRISB

    ; TRISC: UART/I2C Pins
    MOVLW   10011000B
    MOVWF   TRISC

    ; TRISD: LCD Data Out
    CLRF    TRISD

    ; TRISE: LCD Control Out
    CLRF    TRISE

    ; ADCON1: Left Justified (ADFM=0), AN0-AN4 Analog
    MOVLW   00000010B   ; 0x02
    MOVWF   ADCON1
    
    ; Bank0
    BCF     STATUS, STATUS_RP0_POSITION

    ; Clear outputs
    CLRF    PORTA
    CLRF    PORTB
    CLRF    PORTC
    CLRF    PORTD
    CLRF    PORTE

    RETURN

; ================= SIMPLE DELAYS =================
delay10ms:
    MOVLW   2
    MOVWF   ISR_Math_Temp5
d10_loop:
    CALL    delay5ms
    DECFSZ  ISR_Math_Temp5, F
    GOTO    d10_loop
    RETURN

delay5ms:
    ; Approx 5ms @ 20MHz
    MOVLW   250
    MOVWF   ISR_Math_Temp4
d5_outer:
    MOVLW   100
    MOVWF   ISR_Math_Temp3
d5_inner:
    NOP
    NOP
    DECFSZ  ISR_Math_Temp3, F
    GOTO    d5_inner
    DECFSZ  ISR_Math_Temp4, F
    GOTO    d5_outer
    RETURN

; ================= MODULE INCLUDES =================
#include "StepMotor.asm"
#include "UART.asm"
#include "LCD.asm"
#include "BMP180.asm"
#include "LDR.asm"
#include "RotaryPotentiometer.asm"

END
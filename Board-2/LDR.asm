;==============================================================================
; # Author: 152120221098 Emre AVCI
;
; LDR Light Sensor Module
; This module reads light intensity from LDR sensor connected to RA0/AN0
; LDR is connected in voltage divider configuration with 10K resistor
; Controls curtain automatically based on light threshold
;==============================================================================

; LDR Configuration Constants
#include <xc.inc>

#ifndef _STATUS_POSITIONS_DEFINED
#define _STATUS_POSITIONS_DEFINED
STATUS_C_POSITION       EQU 0
STATUS_Z_POSITION       EQU 2
STATUS_RP0_POSITION     EQU 5
STATUS_RP1_POSITION     EQU 6
#endif

#ifndef _ADC_POSITIONS_DEFINED
#define _ADC_POSITIONS_DEFINED
ADCON0_GO_DONE_POSITION    EQU 2
#endif

LDR_THRESHOLD       EQU 30       ; Threshold percentage (30%)

;==============================================================================
; LDR Initialization
;==============================================================================
LDR_INIT:
    BSF     STATUS, STATUS_RP0_POSITION   ; Select Bank 1
    BSF     TRISA, 0            ; Set RA0 as input (Analog LDR)
    
    BSF     TRISB, 4            ; Set RB4 as input (Comparator Digital)
    BCF     STATUS, STATUS_RP0_POSITION   ; Select Bank 0
    
    MOVLW   10000001B           ; ADCON0: Fosc/32, CH0, ADON=1
    MOVWF   ADCON0
    
    MOVLW   50                  ; Set initial light value to 50%
    MOVWF   Light_Intensity
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Read LDR Light Intensity
; Algorithm: (ADC / 4) + (ADC / 8) + (ADC / 64) -> Approx %
;==============================================================================
READ_LDR:
    MOVLW   0x00                ; Select Channel 0
    CALL    ADC_READ_LDR_CHANNEL
    
    BANKSEL ADRESH
    MOVF    ADRESH, W           ; Get 8-bit MSB (0-255)
    
    MOVWF   ISR_Math_Temp1      ; Store original value (X)
    
    ; --- Calculate X / 4 ---
    MOVWF   ISR_Math_Temp2
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp2, F   ; Shift right 1 (X/2)
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp2, F   ; Shift right 1 (X/4)
    
    ; --- Calculate X / 8 ---
    MOVF    ISR_Math_Temp2, W   ; Load X/4
    MOVWF   ISR_Math_Temp3
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp3, F   ; Shift right 1 (X/8)
    
    ; --- Calculate X / 64 ---
    MOVF    ISR_Math_Temp1, W   ; Load original X
    MOVWF   ISR_Math_Temp4
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp4, F   ; /2
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp4, F   ; /4
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp4, F   ; /8
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp4, F   ; /16
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp4, F   ; /32
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp4, F   ; /64
    
    ; --- Sum Results ---
    MOVF    ISR_Math_Temp2, W   ; W = X/4
    ADDWF   ISR_Math_Temp3, W   ; W = X/4 + X/8
    ADDWF   ISR_Math_Temp4, W   ; W = Total Sum
    
    MOVWF   ISR_Math_Temp5      ; Store calculated percentage
    
    ; Clamp result to 100% max
    SUBLW   100
    BTFSS   STATUS, STATUS_C_POSITION   ; Check if W > 100
    GOTO    LDR_SET_MAX         ; Force 100 if overflow
    
    MOVF    ISR_Math_Temp5, W   ; Reload valid result
    GOTO    LDR_STORE_VALUE
    
LDR_SET_MAX:
    MOVLW   100                 ; Set max value
    
LDR_STORE_VALUE:
    MOVWF   Light_Intensity     ; Update global variable
    
    CALL    CHECK_LIGHT_THRESHOLD ; Check Night/Day logic
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Check Threshold
; If Light < 30, Force Curtain Closed (100%)
;==============================================================================
CHECK_LIGHT_THRESHOLD:
    MOVF    Light_Intensity, W
    SUBLW   LDR_THRESHOLD       ; W = 30 - Current
    
    BTFSC   STATUS, STATUS_C_POSITION   ; Check if Result >= 0 (Light <= 30)
    GOTO    LIGHT_BELOW_THRESHOLD       ; Go to Night Mode
    
    ; Day Mode: Manual control enabled (do nothing here)
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN
    
LIGHT_BELOW_THRESHOLD:
    MOVLW   100                 ; Force close
    MOVWF   Desired_Curtain     ; Override target position
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Read Digital Comparator (Fast Check)
;==============================================================================
READ_LDR_DIGITAL:
    BCF     STATUS, STATUS_C_POSITION
    BTFSC   PORTB, 4            ; Read Comparator Pin
    BSF     STATUS, STATUS_C_POSITION ; Set flag if High
    
    MOVLW   0x00                ; Default 0 (Dark)
    BTFSC   STATUS, STATUS_C_POSITION
    MOVLW   0x01                ; Set 1 (Bright)
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; ADC Read Routine
;==============================================================================
ADC_READ_LDR_CHANNEL:
    MOVWF   ISR_Math_Temp1      ; Save channel ID
    
    MOVF    ADCON0, W
    ANDLW   11000111B           ; Mask existing channel bits
    MOVWF   ADCON0
    
    MOVF    ISR_Math_Temp1, W   ; Shift channel bits to pos 5-3
    MOVWF   ISR_Math_Temp2
    BCF     STATUS, STATUS_C_POSITION
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    
    MOVF    ISR_Math_Temp2, W
    IORWF   ADCON0, F           ; Apply new channel
    
    CALL    DELAY_LDR_SETTLE    ; Wait acquisition time
    
    BANKSEL ADCON0
    BSF     ADCON0, ADCON0_GO_DONE_POSITION ; Start Conversion
    
LDR_ADC_WAIT:
    BANKSEL ADCON0
    BTFSC   ADCON0, ADCON0_GO_DONE_POSITION ; Wait for done bit
    GOTO    LDR_ADC_WAIT
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; ADC Settling Delay (~20us)
;==============================================================================
DELAY_LDR_SETTLE:
    MOVLW   33                  ; Loop count
    MOVWF   ISR_Math_Temp5
    
DELAY_LDR_LOOP:
    DECFSZ  ISR_Math_Temp5, F
    GOTO    DELAY_LDR_LOOP      ; Busy wait
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Simple Read (Backup method, unused)
;==============================================================================
READ_LDR_SIMPLE:
    MOVLW   0x00
    CALL    ADC_READ_LDR_CHANNEL
    
    BANKSEL ADRESH
    MOVF    ADRESH, W
    
    ; Simple scaling: X/2 + X/8 ~ X/2.5
    MOVWF   ISR_Math_Temp1
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp1, F   ; X/2
    
    MOVF    ISR_Math_Temp1, W
    MOVWF   ISR_Math_Temp2
    BCF     STATUS, STATUS_C_POSITION
    RRF     ISR_Math_Temp2, F   ; X/4
    RRF     ISR_Math_Temp2, F   ; X/8
    
    MOVF    ISR_Math_Temp1, W
    ADDWF   ISR_Math_Temp2, W   ; Sum
    
    ; Clamp and Store
    MOVWF   ISR_Math_Temp3
    SUBLW   100
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    LDR_SIMPLE_STORE
    
    MOVLW   100
    MOVWF   ISR_Math_Temp3
    
LDR_SIMPLE_STORE:
    MOVF    ISR_Math_Temp3, W
    SUBWF   Light_Intensity, W  ; Check difference
    BTFSS   STATUS, STATUS_Z_POSITION
    GOTO    LDR_CONT_2
    RETURN
LDR_CONT_2:
    MOVF    ISR_Math_Temp3, W
    MOVWF   Light_Intensity
    CALL    CHECK_LIGHT_THRESHOLD
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; END OF LDR SENSOR MODULE
;==============================================================================
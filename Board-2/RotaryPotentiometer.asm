;==============================================================================
; # Author: 152120221098 Emre Avc?
;
; Potentiometer Module - Rotary Switch for Curtain Control
; This module reads analog value from potentiometer (POT1) connected to RA2/AN2
; Converts 0-5V input to 0-100% curtain position
;==============================================================================

; Configuration Constants
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

;==============================================================================
; POT Initialization
;==============================================================================
POT_INIT:
    BSF     STATUS, STATUS_RP0_POSITION   ; Select Bank 1
    BSF     TRISA, 2            ; Set RA2 as input (Analog POT)
    
    BCF     STATUS, STATUS_RP0_POSITION   ; Select Bank 0
    
    MOVLW   10000001B           ; ADCON0: Fosc/32, CH2, ADON=1
    MOVWF   ADCON0
    
    CALL    DELAY_ADC_SETTLE    ; Wait for acquisition
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Read Potentiometer (Main Routine)
; Converts 0-255 ADC value to 0-100% using shift operations
; Updates Desired_Curtain
;==============================================================================
READ_POT:
    MOVLW   0x02                ; Select Channel 2
    CALL    ADC_READ_CHANNEL
    
    BANKSEL ADRESH
    MOVF    ADRESH, W           ; Get 8-bit MSB
    
    ; Check saturation (> 252 is 100%)
    SUBLW   252
    BTFSS   STATUS, STATUS_C_POSITION
    GOTO    POT_SET_MAX
    
    ; --- Calculate Percentage ---
    ; Algorithm: (X / 4) + (X / 8) + (X / 64) approx X * 100 / 256
    
    BANKSEL ADRESH
    MOVF    ADRESH, W
    MOVWF   ISR_Math_Temp1      ; Store X
    
    ; Calculate X / 16
    MOVWF   ISR_Math_Temp2
    BCF     STATUS, STATUS_C_POSITION
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    
    ; Calculate X / 8
    MOVF    ISR_Math_Temp1, W
    MOVWF   ISR_Math_Temp3
    BCF     STATUS, STATUS_C_POSITION
    RLF     ISR_Math_Temp3, F
    RLF     ISR_Math_Temp3, F
    RLF     ISR_Math_Temp3, F
    
    ; Sum components
    MOVF    ISR_Math_Temp2, W
    ADDWF   ISR_Math_Temp3, W
    ADDWF   ISR_Math_Temp1, W
    
    ; Final scaling / 64
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
    
    MOVF    ISR_Math_Temp4, W   ; Load result
    
    ; Clamp to 100
    SUBLW   100
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    POT_STORE_VALUE
    
POT_SET_MAX:
    MOVLW   100                 ; Force 100%
    
POT_STORE_VALUE:
    MOVF    ISR_Math_Temp4, W
    SUBLW   100
    BTFSS   STATUS, STATUS_C_POSITION
    GOTO    POT_FORCE_MAX
    
    MOVF    ISR_Math_Temp4, W
    GOTO    POT_UPDATE_DESIRED
    
POT_FORCE_MAX:
    MOVLW   100
    
POT_UPDATE_DESIRED:
    MOVWF   Desired_Curtain     ; Update global variable
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; ADC Read Routine
;==============================================================================
ADC_READ_CHANNEL:
    MOVWF   ISR_Math_Temp1      ; Save channel ID
    
    MOVF    ADCON0, W
    ANDLW   11000111B           ; Clear current channel
    MOVWF   ADCON0
    
    MOVF    ISR_Math_Temp1, W   ; Prepare new channel bits
    MOVWF   ISR_Math_Temp2
    BCF     STATUS, STATUS_C_POSITION
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    RLF     ISR_Math_Temp2, F
    
    MOVF    ISR_Math_Temp2, W
    IORWF   ADCON0, F           ; Apply new channel
    
    CALL    DELAY_ADC_SETTLE    ; Wait acquisition
    
    BANKSEL ADCON0
    BSF     ADCON0, ADCON0_GO_DONE_POSITION ; Start conversion
    
ADC_WAIT:
    BANKSEL ADCON0
    BTFSC   ADCON0, ADCON0_GO_DONE_POSITION ; Wait for done bit
    GOTO    ADC_WAIT
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; ADC Settling Delay (~20us)
;==============================================================================
DELAY_ADC_SETTLE:
    MOVLW   33                  ; Load loop count
    MOVWF   ISR_Math_Temp5
    
DELAY_ADC_LOOP:
    DECFSZ  ISR_Math_Temp5, F
    GOTO    DELAY_ADC_LOOP      ; Busy wait
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Simple Read (Approximation Method)
; Used for quick checks or alternate scaling
;==============================================================================
READ_POT_SIMPLE:
    MOVLW   0x02
    CALL    ADC_READ_CHANNEL
    
    BANKSEL ADRESH
    MOVF    ADRESH, W
    
    ; Approx: X/2 + X/8
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
    
    ; Clamp result
    MOVWF   ISR_Math_Temp3
    SUBLW   100
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    SIMPLE_STORE
    
    MOVLW   100
    MOVWF   ISR_Math_Temp3
    
SIMPLE_STORE:
    MOVF    ISR_Math_Temp3, W
    MOVWF   Desired_Curtain     ; Update variable
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; Raw Pot Read (No Global Update)
; Reads ADC and returns value in Pot_Value variable
; Used for change detection logic
;==============================================================================
READ_POT_RAW:
    MOVLW   0x02
    CALL    ADC_READ_CHANNEL

    BANKSEL ADRESH
    MOVF    ADRESH, W

    ; Approx: X/2 + X/8
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
    MOVWF   ISR_Math_Temp3

    ; Clamp to 100
    MOVF    ISR_Math_Temp3, W
    SUBLW   100
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    RAW_STORE

    MOVLW   100
    MOVWF   ISR_Math_Temp3

RAW_STORE:
    MOVF    ISR_Math_Temp3, W
    MOVWF   Pot_Value           ; Store to local variable

    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    RETURN

;==============================================================================
; END OF POTENTIOMETER MODULE
;==============================================================================
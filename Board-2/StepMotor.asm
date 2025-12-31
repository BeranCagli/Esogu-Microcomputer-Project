;==============================================================================
; # Author: 151220212116, Beyzanur TOPÇU
;
; Motor Module
;
;==============================================================================

; RAM Variables (Defined in Main.asm, referenced here via EQU)
; Current_Curtain       EQU 0x60
; Desired_Curtain       EQU 0x61
; Step_Index            EQU 0x62
; Step_Counter          EQU 0x63
; Current_Curtain_Frac  EQU 0x64

ORG 0x0100
STEP_TABLE:
    ADDWF   PCL, F
    RETLW   00000001B           ; Step 0
    RETLW   00000010B           ; Step 1
    RETLW   00000100B           ; Step 2
    RETLW   00001000B           ; Step 3

MOTOR_INIT:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    CLRF    Current_Curtain
    CLRF    Step_Index
    CLRF    Step_Counter
    CLRF    Current_Curtain_Frac
    
    ; Initial target: 100% (Closed)
    MOVLW   100
    MOVWF   Desired_Curtain
    
    CLRF    PORTB
    RETURN

;==============================================================================
; CONTROL_MOTOR
; Compares current vs desired position and decides direction
;==============================================================================
CONTROL_MOTOR:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    ; Check if target reached
    MOVF    Current_Curtain, W
    SUBWF   Desired_Curtain, W  ; W = Desired - Current
    
    ; Exactly equal?
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    TARGET_REACHED      ; Yes
    
    ; Check polarity
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    CHECK_UP_SMALL      ; Desired > Current (UP)
    
    GOTO    CHECK_DOWN_SMALL    ; Desired < Current (DOWN)

;------------------------------------------------------------------------------
; Hysteresis Check (1% tolerance to prevent jitter)
;------------------------------------------------------------------------------
CHECK_UP_SMALL:
    ; W = Desired - Current (positive)
    SUBLW   0                   
    BTFSC   STATUS, STATUS_C_POSITION   ; Diff <= 1?
    GOTO    TARGET_REACHED      ; Yes, ignore small diff
    GOTO    MOTOR_STEP_UP

CHECK_DOWN_SMALL:
    ; Calculate absolute difference
    MOVF    Desired_Curtain, W
    SUBWF   Current_Curtain, W  ; W = Current - Desired
    SUBLW   0                   
    BTFSC   STATUS, STATUS_C_POSITION   ; Diff <= 1?
    GOTO    TARGET_REACHED      ; Yes
    GOTO    MOTOR_STEP_DOWN

TARGET_REACHED:
    CALL    STOP_MOTOR
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    CLRF    Step_Counter
    CLRF    Current_Curtain_Frac
    RETURN

MOTOR_IDLE:
    CALL    STOP_MOTOR
    CLRF    Step_Counter
    RETURN

;==============================================================================
; MOTOR STEP UP (Opening: 0 -> 100)
;==============================================================================
MOTOR_STEP_UP:
    CALL    STEP_CCW
    CALL    delay5ms
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    INCF    Step_Counter, F
    
    ; Check if cycle complete (10 steps)
    MOVF    Step_Counter, W
    SUBLW   10
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    UP_CYCLE_COMPLETE
    
    ; Intermediate step (1-9): Update fraction
    MOVF    Step_Counter, W
    MOVWF   Current_Curtain_Frac
    RETURN

UP_CYCLE_COMPLETE:
    ; Cycle done
    CLRF    Step_Counter
    CLRF    Current_Curtain_Frac
    INCF    Current_Curtain, F
    
    ; Cap at 100%
    MOVF    Current_Curtain, W
    SUBLW   100
    BTFSC   STATUS, STATUS_C_POSITION
    RETURN
    
    MOVLW   100
    MOVWF   Current_Curtain
    RETURN

;==============================================================================
; MOTOR STEP DOWN (Closing: 100 -> 0)
;==============================================================================
MOTOR_STEP_DOWN:
    CALL    STEP_CW
    CALL    delay5ms
    
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    INCF    Step_Counter, F
    
    ; --- FIX START ---
    
    ; Is this the FIRST step? (Step_Counter == 1)
    MOVF    Step_Counter, W
    XORLW   1
    BTFSS   STATUS, STATUS_Z_POSITION
    GOTO    DOWN_UPDATE_FRAC ; No, continue
    
    ; Yes, 1st step (X.0 -> (X-1).9 transition)
    ; Decrement Integer IMMEDIATELY.
    MOVF    Current_Curtain, F
    BTFSC   STATUS, STATUS_Z_POSITION   ; Check if 0
    RETURN
    
    DECF    Current_Curtain, F  ; e.g. 93 -> 92
    
DOWN_UPDATE_FRAC:
    ; Calculate fraction: 10 - Step_Counter
    ; Step 1 -> 9 (.9)
    ; Step 9 -> 1 (.1)
    MOVF    Step_Counter, W
    SUBLW   10
    MOVWF   Current_Curtain_Frac
    
    ; Cycle complete? (Step 10)
    MOVF    Step_Counter, W
    XORLW   10
    BTFSS   STATUS, STATUS_Z_POSITION
    RETURN  ; Not yet
    
    ; Cycle Done
    CLRF    Step_Counter
    CLRF    Current_Curtain_Frac ; Set .0 (becomes 92.0)
    RETURN
    ; --- FIX END ---

;==============================================================================
; Low Level Step Functions
;==============================================================================
STEP_CW:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    INCF    Step_Index, F
    MOVLW   0x03
    ANDWF   Step_Index, F
    MOVLW   HIGH STEP_TABLE
    MOVWF   PCLATH
    MOVF    Step_Index, W
    CALL    STEP_TABLE
    MOVWF   PORTB
    CLRF    PCLATH
    RETURN

STEP_CCW:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    MOVF    Step_Index, F
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    WRAP_CCW_FIRST
    DECF    Step_Index, F
    GOTO    OUTPUT_STEP_CCW
WRAP_CCW_FIRST:
    MOVLW   3
    MOVWF   Step_Index
OUTPUT_STEP_CCW:
    MOVLW   HIGH STEP_TABLE
    MOVWF   PCLATH
    MOVF    Step_Index, W
    CALL    STEP_TABLE
    MOVWF   PORTB
    CLRF    PCLATH
    RETURN

STOP_MOTOR:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    CLRF    PORTB
    RETURN

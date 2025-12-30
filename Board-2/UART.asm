;==============================================================================
; # Author: 152120221098 Emre Avc?
;
; UART Module - Serial Communication with PC
; Handles receiving commands and sending status updates.
;==============================================================================

; ---------------- RAM VARIABLES ----------------
UART_RX_Data          EQU 0x50
UART_TX_Data          EQU 0x51
UART_Temp             EQU 0x59    ; Temporary storage

;==============================================================================
; UART Initialization
;==============================================================================
UART_INIT:
    BSF     STATUS, STATUS_RP0_POSITION   ; Select Bank 1
    
    ; Baud Rate Configuration
    MOVLW   25                  ; 9600 baud @ 4MHz, BRGH=1
    MOVWF   SPBRG
    
    ; TXSTA Configuration
    MOVLW   00100100B           ; TXEN=1, BRGH=1 (High Speed)
    MOVWF   TXSTA
    
    ; Interrupt Enable
    BSF     PIE1, PIE1_RCIE_POSITION      ; Enable RX Interrupt
    
    BCF     STATUS, STATUS_RP0_POSITION   ; Select Bank 0
    
    ; RCSTA Configuration
    MOVLW   10010000B           ; SPEN=1, CREN=1
    MOVWF   RCSTA
    
    ; Global Interrupts
    BSF     INTCON, INTCON_PEIE_POSITION
    BSF     INTCON, INTCON_GIE_POSITION
    
    RETURN

;==============================================================================
; UART Interrupt Service Routine
;==============================================================================
UART_ISR:
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    BCF     STATUS, STATUS_RP1_POSITION
    
    ; Check Errors
    BTFSC   RCSTA, RCSTA_OERR_POSITION    ; Overrun Error?
    GOTO    UART_CLEAR_OERR
    
    BTFSC   RCSTA, RCSTA_FERR_POSITION    ; Framing Error?
    GOTO    UART_CLEAR_FERR
    
    ; Read Data
    MOVF    RCREG, W            ; Read received byte
    MOVWF   UART_RX_Data
    
    ; Process Command
    CALL    UART_DECODE_CMD     ; Handle the byte

    RETURN                      ; Return to main ISR

UART_CLEAR_OERR:
    BCF     RCSTA, RCSTA_CREN_POSITION    ; Reset CREN
    MOVF    RCREG, W            ; Flush buffer
    MOVF    RCREG, W
    BSF     RCSTA, RCSTA_CREN_POSITION    ; Re-enable CREN
    RETURN

UART_CLEAR_FERR:
    MOVF    RCREG, W            ; Read to clear error
    RETURN

;==============================================================================
; Command Decoder
;==============================================================================
UART_DECODE_CMD:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION
    
    ; Check SET Commands (Upper bits)
    MOVF    UART_RX_Data, W
    ANDLW   0xC0
    XORLW   0xC0
    BTFSC   STATUS, STATUS_Z_POSITION     ; 11xxxxxx -> Set Integral
    GOTO    CMD_SET_CURTAIN_INT
    
    MOVF    UART_RX_Data, W
    ANDLW   0xC0
    XORLW   0x80
    BTFSC   STATUS, STATUS_Z_POSITION     ; 10xxxxxx -> Set Fractional
    GOTO    CMD_SET_CURTAIN_FRAC
    
    ; Check GET Commands (0x01-0x08)
    MOVF    UART_RX_Data, W
    
    XORLW   0x01
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_DESIRED_CURT_FRAC
    
    MOVF    UART_RX_Data, W
    XORLW   0x02
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_DESIRED_CURT_INT
    
    MOVF    UART_RX_Data, W
    XORLW   0x03
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_TEMP_FRAC
    
    MOVF    UART_RX_Data, W
    XORLW   0x04
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_TEMP_INT
    
    MOVF    UART_RX_Data, W
    XORLW   0x05
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_PRESS_FRAC
    
    MOVF    UART_RX_Data, W
    XORLW   0x06
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_PRESS_INT
    
    MOVF    UART_RX_Data, W
    XORLW   0x07
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_LIGHT_FRAC
    
    MOVF    UART_RX_Data, W
    XORLW   0x08
    BTFSC   STATUS, STATUS_Z_POSITION
    GOTO    CMD_GET_LIGHT_INT
    
    RETURN

;==============================================================================
; GET Command Handlers
;==============================================================================

CMD_GET_DESIRED_CURT_FRAC:
    MOVF    Desired_Curtain_Frac, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_DESIRED_CURT_INT:
    MOVF    Desired_Curtain, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_TEMP_FRAC:
    MOVF    Outdoor_Temp_Frac, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_TEMP_INT:
    MOVF    Outdoor_Temp, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_PRESS_FRAC:
    MOVF    Outdoor_Press_L, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_PRESS_INT:
    MOVF    Outdoor_Press_H, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_LIGHT_FRAC:
    MOVF    Light_Intensity_Frac, W
    CALL    UART_SEND_BYTE
    RETURN

CMD_GET_LIGHT_INT:
    MOVF    Light_Intensity, W
    CALL    UART_SEND_BYTE
    RETURN

;==============================================================================
; SET Command Handlers
;==============================================================================

; Set Fractional Part
CMD_SET_CURTAIN_FRAC:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION

    MOVF    UART_RX_Data, W
    ANDLW   0x3F                ; Mask command bits
    MOVWF   UART_Temp

    ; Restore bit 6 logic (if used elsewhere)
    BTFSC   UART_Temp, 4
    BSF     Desired_Curtain, 6
    BTFSS   UART_Temp, 4
    BCF     Desired_Curtain, 6

    ; Extract 4-bit fraction
    MOVF    UART_Temp, W
    ANDLW   0x0F
    MOVWF   UART_Temp

    ; Limit to 9
    MOVLW   9
    SUBWF   UART_Temp, W
    BTFSS   STATUS, STATUS_C_POSITION
    GOTO    _FRAC_OK
    MOVLW   9
    MOVWF   UART_Temp

_FRAC_OK:
    MOVF    UART_Temp, W
    MOVWF   Desired_Curtain_Frac ; Update variable

    ; Enable UART Override Mode
    MOVLW   1
    MOVWF   Control_Mode

    ; Send ACK (0xAA)
    MOVLW   0xAA
    CALL    UART_SEND_BYTE
    RETURN

; Set Integral Part
CMD_SET_CURTAIN_INT:
    BCF     STATUS, STATUS_RP0_POSITION
    BCF     STATUS, STATUS_RP1_POSITION

    MOVF    UART_RX_Data, W
    ANDLW   0x3F                ; Extract value
    MOVWF   UART_Temp

    MOVF    Desired_Curtain, W
    ANDLW   0x40                ; Preserve bit 6 if needed
    IORWF   UART_Temp, W
    MOVWF   Desired_Curtain     ; Update variable

    ; Enable UART Override Mode
    MOVLW   1
    MOVWF   Control_Mode

    ; Send ACK
    MOVLW   0xAA
    CALL    UART_SEND_BYTE
    RETURN

;==============================================================================
; Send Byte Routine
;==============================================================================
UART_SEND_BYTE:
    MOVWF   UART_TX_Data
    
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    
WAIT_TX_LOOP:
    BTFSS   TXSTA, TXSTA_TRMT_POSITION    ; Check if buffer empty
    GOTO    WAIT_TX_LOOP
    
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    
    MOVF    UART_TX_Data, W
    MOVWF   TXREG               ; Write to register
    
    RETURN
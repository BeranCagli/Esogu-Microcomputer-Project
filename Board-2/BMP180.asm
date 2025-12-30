;==============================================================================
; # Author: 152120221098 Emre AVCI
;
; I2C Module - BMP180 Sensor Communication
; This module provides I2C Master mode communication for BMP180 sensor
; BMP180 I2C Address: 0x77 (Write: 0xEE, Read: 0xEF)
;==============================================================================

; BMP180 Constants
BMP180_ADDR_W   EQU 0xEE        ; Write address
BMP180_ADDR_R   EQU 0xEF        ; Read address
BMP180_CTRL_REG EQU 0xF4        ; Control register
BMP180_DATA_REG EQU 0xF6        ; Data register (MSB)
BMP180_CMD_TEMP EQU 0x2E        ; Temp command
BMP180_CMD_PRES EQU 0x34        ; Pressure command

;==============================================================================
; I2C Initialization
;==============================================================================
I2C_INIT:
    BSF     STATUS, STATUS_RP0_POSITION   ; Select Bank 1
    BSF     TRISC, 3            ; Set RC3 (SCL) as input
    BSF     TRISC, 4            ; Set RC4 (SDA) as input
    
    MOVLW   49                  ; Set Baud rate: 100kHz @ 20MHz
    MOVWF   SSPADD
    
    MOVLW   10000000B           ; Slew rate disabled (SMP=1)
    MOVWF   SSPSTAT
    
    BCF     STATUS, STATUS_RP0_POSITION   ; Select Bank 0
    
    MOVLW   00101000B           ; Enable MSSP, Master mode
    MOVWF   SSPCON
    
    BCF     PIR1, PIR1_SSPIF_POSITION ; Clear interrupt flag
    RETURN

;==============================================================================
; I2C Control Functions
;==============================================================================
I2C_START_CMD:
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BSF     SSPCON2, SSPCON2_SEN_POSITION ; Initiate Start condition
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE                 ; Wait for completion
    RETURN

I2C_STOP_CMD:
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BSF     SSPCON2, SSPCON2_PEN_POSITION ; Initiate Stop condition
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE                 ; Wait for completion
    RETURN

I2C_RESTART:
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BSF     SSPCON2, SSPCON2_RSEN_POSITION; Initiate Repeated Start
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE                 ; Wait for completion
    RETURN

I2C_WRITE:
    MOVWF   SSPBUF              ; Load data to buffer to send
    CALL    I2C_WAIT_IDLE       ; Wait for transmission
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BCF     STATUS, STATUS_C_POSITION     ; Clear Carry
    BTFSC   SSPCON2, SSPCON2_ACKSTAT_POSITION ; Check for ACK
    BSF     STATUS, STATUS_C_POSITION     ; Set Carry if NACK
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    RETURN

I2C_READ_ACK:
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BSF     SSPCON2, SSPCON2_RCEN_POSITION; Enable Receive mode
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE       ; Wait for byte
    MOVF    SSPBUF, W           ; Read received byte
    MOVWF   LCD_Temp            ; Store temporarily
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BCF     SSPCON2, SSPCON2_ACKDT_POSITION ; Set ACK bit (0)
    BSF     SSPCON2, SSPCON2_ACKEN_POSITION ; Send ACK sequence
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE       ; Wait for ACK to finish
    MOVF    LCD_Temp, W         ; Restore data to W
    RETURN

I2C_READ_NACK:
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BSF     SSPCON2, SSPCON2_RCEN_POSITION; Enable Receive mode
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE       ; Wait for byte
    MOVF    SSPBUF, W           ; Read received byte
    MOVWF   LCD_Temp            ; Store temporarily
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    BSF     SSPCON2, SSPCON2_ACKDT_POSITION ; Set NACK bit (1)
    BSF     SSPCON2, SSPCON2_ACKEN_POSITION ; Send NACK sequence
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    CALL    I2C_WAIT_IDLE       ; Wait for NACK to finish
    MOVF    LCD_Temp, W         ; Restore data to W
    RETURN

;==============================================================================
; I2C Wait Idle - CRITICAL FIX APPLIED
; Uses ISR_Math_Temp5 instead of ISR_Math_Temp1
;==============================================================================
I2C_WAIT_IDLE:
    BSF     STATUS, STATUS_RP0_POSITION   ; Bank 1
    
    MOVLW   255
    MOVWF   ISR_Math_Temp5       ; Load timeout counter (Temp5)
    
I2C_WAIT_LOOP:
    DECFSZ  ISR_Math_Temp5, F    ; Decrement timeout counter
    GOTO    I2C_CHECK_FLAGS      ; Check bus status
    
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    BSF     STATUS, STATUS_C_POSITION     ; Set error flag (Timeout)
    RETURN
    
I2C_CHECK_FLAGS:
    MOVF    SSPCON2, W           ; Read control register
    ANDLW   00011111B            ; Check ACKEN, RCEN, PEN, RSEN, SEN
    BTFSS   STATUS, STATUS_Z_POSITION
    GOTO    I2C_WAIT_LOOP        ; If busy, loop
    
    BCF     STATUS, STATUS_RP0_POSITION   ; Bank 0
    BCF     STATUS, STATUS_C_POSITION     ; Clear error flag (Idle)
    RETURN

;==============================================================================
; Read Temperature
;==============================================================================
READ_BMP180_TEMP:
    ; Step 1: Start Temperature Measurement
    CALL    I2C_START_CMD
    MOVLW   BMP180_ADDR_W
    CALL    I2C_WRITE           ; Send Write Address
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    BMP180_TEMP_ERROR   ; Exit if NACK
    
    MOVLW   BMP180_CTRL_REG
    CALL    I2C_WRITE           ; Select Control Register
    MOVLW   BMP180_CMD_TEMP
    CALL    I2C_WRITE           ; Send Temp Command
    CALL    I2C_STOP_CMD
    
    ; Step 2: Wait for conversion
    CALL    BMP180_DELAY_5MS
    
    ; Step 3: Read Data
    CALL    I2C_START_CMD
    MOVLW   BMP180_ADDR_W
    CALL    I2C_WRITE
    MOVLW   BMP180_DATA_REG
    CALL    I2C_WRITE           ; Select Data Register
    
    CALL    I2C_RESTART         ; Repeated Start
    MOVLW   BMP180_ADDR_R
    CALL    I2C_WRITE           ; Send Read Address
    
    CALL    I2C_READ_ACK        ; Read MSB
    MOVWF   ISR_Math_Temp1      ; Save MSB
    
    CALL    I2C_READ_NACK       ; Read LSB (Last byte)
    MOVWF   ISR_Math_Temp2      ; Save LSB
    
    CALL    I2C_STOP_CMD
    
    ; Step 4: Check if value changed
    MOVF    ISR_Math_Temp1, W
    SUBWF   Outdoor_Temp, W
    BTFSC   STATUS, STATUS_Z_POSITION
    RETURN                      ; No change, return
    
    ; Step 5: Update memory
    MOVF    ISR_Math_Temp1, W
    MOVWF   Outdoor_Temp        ; Store integer part
    
    ; Process fractional part (simplified)
    BTFSC   ISR_Math_Temp2, 7   ; Check bit 7 of LSB
    GOTO    TEMP_FRAC_FIVE
    
    CLRF    Outdoor_Temp_Frac   ; Fraction = 0
    RETURN
    
TEMP_FRAC_FIVE:
    MOVLW   5
    MOVWF   Outdoor_Temp_Frac   ; Fraction = 5
    RETURN
    
BMP180_TEMP_ERROR:
    CALL    I2C_STOP_CMD        ; Reset bus on error
    RETURN

;==============================================================================
; Read Pressure
;==============================================================================
READ_BMP180_PRESS:
    ; Step 1: Start Pressure Measurement
    CALL    I2C_START_CMD
    MOVLW   BMP180_ADDR_W
    CALL    I2C_WRITE
    BTFSC   STATUS, STATUS_C_POSITION
    GOTO    BMP180_PRESS_ERROR
    
    MOVLW   BMP180_CTRL_REG
    CALL    I2C_WRITE
    MOVLW   BMP180_CMD_PRES
    CALL    I2C_WRITE           ; Send Pressure Command
    CALL    I2C_STOP_CMD
    
    ; Step 2: Wait for conversion
    CALL    BMP180_DELAY_5MS
    
    ; Step 3: Read Data
    CALL    I2C_START_CMD
    MOVLW   BMP180_ADDR_W
    CALL    I2C_WRITE
    MOVLW   BMP180_DATA_REG
    CALL    I2C_WRITE
    
    CALL    I2C_RESTART
    MOVLW   BMP180_ADDR_R
    CALL    I2C_WRITE
    
    CALL    I2C_READ_ACK        ; Read MSB
    MOVWF   ISR_Math_Temp1
    CALL    I2C_READ_ACK        ; Read LSB
    MOVWF   ISR_Math_Temp2
    CALL    I2C_READ_NACK       ; Read XLSB (discarded)
    
    CALL    I2C_STOP_CMD
    
    ; Step 4: Update memory
    MOVF    ISR_Math_Temp1, W
    MOVWF   Outdoor_Press_H     ; Store High Byte
    MOVF    ISR_Math_Temp2, W
    MOVWF   Outdoor_Press_L     ; Store Low Byte
    RETURN
    
BMP180_PRESS_ERROR:
    CALL    I2C_STOP_CMD
    RETURN

;==============================================================================
; Delay 5ms
;==============================================================================
BMP180_DELAY_5MS:
    MOVLW   5
    MOVWF   ISR_Math_Temp3      ; Outer loop counter
BMP180_DELAY_5MS_OUTER:
    MOVLW   200
    MOVWF   ISR_Math_Temp4      ; Inner loop counter
BMP180_DELAY_5MS_INNER:
    NOP
    DECFSZ  ISR_Math_Temp4, F
    GOTO    BMP180_DELAY_5MS_INNER
    DECFSZ  ISR_Math_Temp3, F
    GOTO    BMP180_DELAY_5MS_OUTER
    RETURN
; V11d11r21 - Jolly Wrencher 113x56 graphics added to proven r15 report.
; V11d11r12 - magnetic-stripe reader removed; astronomy/GPS/printer retained.
; No PIO card interrupts, card decoder, card menu path, or card buffers.

; TRANZ 330 standalone astronomy ROM base
PIO_A_DATA EQU $00
PIO_A_CTRL EQU $01
PIO_B_DATA EQU $02
PIO_B_CTRL EQU $03
CTC0 EQU $10
CTC1 EQU $11
CTC2 EQU $12
CTC3 EQU $13
DART_A_DATA EQU $20
DART_A_CTRL EQU $21
DART_B_DATA EQU $22
DART_B_CTRL EQU $23
RTC_SEC_1 EQU $30
RTC_SEC_10 EQU $31
RTC_MIN_1 EQU $32
RTC_MIN_10 EQU $33
RTC_HOUR_1 EQU $34
RTC_HOUR_10 EQU $35
RTC_DAY_1 EQU $36
RTC_DAY_10 EQU $37
RTC_MONTH_1 EQU $38
RTC_MONTH_10 EQU $39
RTC_YEAR_1 EQU $3A
RTC_YEAR_10 EQU $3B
RTC_WEEK EQU $3C
RTC_CTRL_D EQU $3D
RTC_CTRL_E EQU $3E
RTC_CTRL_F EQU $3F
KEY_CLEAR EQU $04
KEY_BACKSPACE EQU $08
KEY_ALPHA EQU $0C
KEY_UTC_NEG EQU $0D             ; * key = negative/west UTC offset
KEY_UTC_POS EQU $0F             ; # key = positive/east UTC offset
KEY_ENTER EQU $10

ORG $0000
RESET:
    DI
    JP MAIN

    DEFS $0100-$,$FF
ORG $0100
MAIN:
    DI
    LD SP,$FFFE

    ; Initialize PIO A for VFD/keypad, with no card interrupts.
    LD A,$CF
    OUT (PIO_A_CTRL),A
    LD A,$80
    OUT (PIO_A_CTRL),A
    LD A,$07
    OUT (PIO_A_CTRL),A
    LD A,$CF
    OUT (PIO_B_CTRL),A
    LD A,$8F
    OUT (PIO_B_CTRL),A
    XOR A
    OUT (PIO_B_DATA),A
    CALL DISPLAY_INIT

    ; V11d10 splash screen.  Show the program title immediately after the
    ; display and keypad PIO have been initialized.  Continue when ENTER is
    ; pressed, or automatically after approximately 10 seconds.
    CALL SPLASH_WAIT_ENTER

    ; Continue with the previously proven V11d8b startup sequence after
    ; ENTER is pressed or the splash timeout expires.
    CALL DEBUG_DART_INIT
    CALL GPS_STARTUP_WAIT
    JP G_ASTRO_MAIN

; ---------------------------------------------------------------------------
; SPLASH_WAIT_ENTER
; Displays "Z PLANET TRACKER" and plays a short two-note TA-DA on the
; TRANZ 330 piezo speaker using CTC channel 2.
;
; Real-hardware calibration of V11d11f showed that the old count of 5000
; lasted about 25 seconds.  The splash countdown is therefore 2000 ticks,
; which should be close to 10 seconds on this actual TRANZ 330.  The TA-DA
; time is INCLUDED in that 2000-tick total; it does not add extra splash time.
;
; TA = C5, about 120 ms, followed by about 70 ms silence.
; DA = G5, about 350 ms.
; CTC2 constants 214 and 143 assume the TRANZ speaker flip-flop is clocked by
; CTC2 with the timer prescaler set to 16 and a CPU clock near 3.58 MHz.
;
; ENTER is checked during the notes, the silence, and the remainder of the
; splash.  Pressing ENTER stops the tone immediately, consumes the keypress,
; and continues to normal GPS acquisition.
; ---------------------------------------------------------------------------
SPLASH_WAIT_ENTER:
    LD HL,MSG_PLANET_TRACKER
    CALL DISPLAY_SHOW

    LD HL,2000                 ; empirically ~10 seconds on the real hardware

    ; First note: C5 (TA), about 120 ms = 24 calibrated splash ticks.
    LD C,214
    CALL SPLASH_TONE_ON
    LD B,24
    CALL SPLASH_WAIT_TICKS
    CP 1
    JR Z,SPLASH_ENTER
    CP 2
    JR Z,SPLASH_TIMEOUT
    CALL SPLASH_TONE_OFF

    ; Short silence between TA and DA, about 70 ms = 14 ticks.
    LD B,14
    CALL SPLASH_WAIT_TICKS
    CP 1
    JR Z,SPLASH_ENTER
    CP 2
    JR Z,SPLASH_TIMEOUT

    ; Second note: G5 (DAAA), about 350 ms = 70 ticks.
    LD C,143
    CALL SPLASH_TONE_ON
    LD B,70
    CALL SPLASH_WAIT_TICKS
    CP 1
    JR Z,SPLASH_ENTER
    CP 2
    JR Z,SPLASH_TIMEOUT
    CALL SPLASH_TONE_OFF

    ; The tune has already consumed part of HL, so this loop waits only for
    ; the remainder of the same ~10-second total splash interval.
SPLASH_KEY_LOOP:
    CALL KEY_SCAN              ; A=0 if no key, otherwise keypad code
    CP KEY_ENTER
    JR Z,SPLASH_ENTER

    CALL DELAY_2MS             ; empirically about 5 ms on this TRANZ 330

    DEC HL                     ; one timeout tick completed
    LD A,H
    OR L
    JR NZ,SPLASH_KEY_LOOP

SPLASH_TIMEOUT:
    CALL SPLASH_TONE_OFF       ; safety: guarantee silence before GPS startup
    RET

SPLASH_ENTER:
    CALL SPLASH_TONE_OFF       ; ENTER also aborts a note already in progress
    CALL KEY_WAIT_RELEASE      ; consume the ENTER press cleanly
    RET

; Wait B splash ticks while preserving the master timeout in HL.
; Return A=0 when this phase completes normally, A=1 if ENTER is pressed,
; or A=2 if the master HL timeout reaches zero.
SPLASH_WAIT_TICKS:
SWT_LOOP:
    PUSH BC                    ; KEY_SCAN uses B/C/D/E internally
    CALL KEY_SCAN
    POP BC
    CP KEY_ENTER
    JR Z,SWT_ENTER

    CALL DELAY_2MS
    DEC HL
    LD A,H
    OR L
    JR Z,SWT_TIMEOUT

    DJNZ SWT_LOOP
    XOR A                      ; A=0: requested phase completed
    RET

SWT_ENTER:
    LD A,1
    RET

SWT_TIMEOUT:
    LD A,2
    RET

; CTC2 drives the TRANZ speaker flip-flop.  C = 8-bit timer time constant.
SPLASH_TONE_ON:
    ; Reinitialize CTC2 from a known reset state every time a tone starts.
    ; This matters after DEBUG_DART_INIT has touched the CTC channels.
    LD A,$03                   ; reset/stop channel 2 first
    OUT (CTC2),A
    LD A,$07                   ; timer, /16 prescale, auto trigger, const follows
    OUT (CTC2),A
    LD A,C
    OUT (CTC2),A
    RET

SPLASH_TONE_OFF:
    LD A,$03                   ; stop/disable CTC2 speaker timer
    OUT (CTC2),A
    RET

; ---------------------------------------------------------------------------
; CALC_DONE_TUNE
; Short calculation-complete chime: C5 - E5 - G5.
;
; This deliberately uses the same proven CTC2 speaker method as the startup
; TA-DA.  The real TRANZ measured DELAY_2MS at roughly 5 ms, so the timing is
; approximately:
;       C5   90 ms
;       gap  40 ms
;       E5   90 ms
;       gap  40 ms
;       G5  250 ms
; Total: about 0.51 second.
;
; Unlike the splash tune, this chime is intentionally allowed to finish: it is
; the audible indication that the requested calculation has completed.
; ---------------------------------------------------------------------------
CALC_DONE_TUNE:
    LD C,214                    ; C5, same constant proven by startup TA
    CALL SPLASH_TONE_ON
    LD B,18
    CALL CALC_DONE_DELAY
    CALL SPLASH_TONE_OFF

    LD B,8                      ; short separation between notes
    CALL CALC_DONE_DELAY

    LD C,170                    ; E5
    CALL SPLASH_TONE_ON
    LD B,18
    CALL CALC_DONE_DELAY
    CALL SPLASH_TONE_OFF

    LD B,8
    CALL CALC_DONE_DELAY

    LD C,143                    ; G5, same constant proven by startup DAAA
    CALL SPLASH_TONE_ON
    LD B,50
    CALL CALC_DONE_DELAY
    CALL SPLASH_TONE_OFF
    RET

CALC_DONE_DELAY:
    CALL DELAY_2MS              ; empirically about 5 ms on this TRANZ 330
    DJNZ CALC_DONE_DELAY
    RET

KEY_SCAN:
    LD A,$10
    OUT (PIO_A_DATA),A
    NOP
    NOP
    IN A,(PIO_B_DATA)
    AND $0F
    CP $0F
    JR NZ,KEY_SCAN_COLUMNS
    XOR A
    RET
KEY_SCAN_COLUMNS:
    LD C,0
    LD D,$0E
KEY_COL_LOOP:
    LD A,D
    OR $10
    OUT (PIO_A_DATA),A
    NOP
    NOP
    IN A,(PIO_B_DATA)
    AND $0F
    CP $0F
    JR NZ,KEY_FOUND_ROW
    INC C
    LD A,C
    CP 4
    JR Z,KEY_NONE_AFTER_SCAN
    LD A,D
    SLA A
    OR 1
    AND $0F
    LD D,A
    JR KEY_COL_LOOP
KEY_NONE_AFTER_SCAN:
    LD A,$10
    OUT (PIO_A_DATA),A
    XOR A
    RET
KEY_FOUND_ROW:
    LD B,0
    BIT 0,A
    JR Z,KEY_HAVE_ROW
    INC B
    BIT 1,A
    JR Z,KEY_HAVE_ROW
    INC B
    BIT 2,A
    JR Z,KEY_HAVE_ROW
    INC B
KEY_HAVE_ROW:
    LD A,B
    ADD A,A
    ADD A,A
    ADD A,C
    INC A
    LD E,A
    LD A,$10
    OUT (PIO_A_DATA),A
    LD A,E
    RET
KEY_GET:
KG_LOOP:
    CALL KEY_SCAN
    OR A
    JR Z,KG_LOOP
    LD E,A
    CALL KEY_WAIT_RELEASE
    LD A,E
    RET
KEY_WAIT_RELEASE:
    PUSH AF
KWR_LOOP:
    LD A,$10
    OUT (PIO_A_DATA),A
    IN A,(PIO_B_DATA)
    AND $0F
    CP $0F
    JR NZ,KWR_LOOP
    POP AF
    RET
KEYCODE_TO_DIGIT:
    CP 1
    JR Z,KD1
    CP 2
    JR Z,KD2
    CP 3
    JR Z,KD3
    CP 5
    JR Z,KD4
    CP 6
    JR Z,KD5
    CP 7
    JR Z,KD6
    CP 9
    JR Z,KD7
    CP 10
    JR Z,KD8
    CP 11
    JR Z,KD9
    CP 14
    JR Z,KD0
    SCF
    RET
KD0: XOR A
     OR A
     RET
KD1: LD A,1
     OR A
     RET
KD2: LD A,2
     OR A
     RET
KD3: LD A,3
     OR A
     RET
KD4: LD A,4
     OR A
     RET
KD5: LD A,5
     OR A
     RET
KD6: LD A,6
     OR A
     RET
KD7: LD A,7
     OR A
     RET
KD8: LD A,8
     OR A
     RET
KD9: LD A,9
     OR A
     RET

; ============================================================================
; DEBUG CHANNEL - DART A, 1200 baud, 8-N-1
; In OshonSoft/Server.vb, writes to port $20 are captured in the debug terminal.
; On real TRANZ hardware these are the same DART-A bytes that feed the 73K212.
; ============================================================================
DEBUG_DART_INIT:
    ; CTC0 corrected for ~1200 baud with 1.7897725 MHz trigger and DART x32.
    LD A,$47
    OUT (CTC0),A
    LD A,$2F
    OUT (CTC0),A
    LD A,$10
    OUT (CTC0),A
    LD A,$47
    OUT (CTC1),A
    LD A,$06
    OUT (CTC1),A
    LD A,$03
    OUT (CTC2),A
    LD A,$87
    OUT (CTC3),A
    LD A,$E0
    OUT (CTC3),A

    ; DART A reset, x32 async, 1 stop, no parity, 8-bit RX/TX, polling.
    LD A,$18
    OUT (DART_A_CTRL),A
    LD A,$04
    OUT (DART_A_CTRL),A
    LD A,$84
    OUT (DART_A_CTRL),A
    LD A,$03
    OUT (DART_A_CTRL),A
    LD A,$C1
    OUT (DART_A_CTRL),A
    LD A,$05
    OUT (DART_A_CTRL),A
    LD A,$EA                    ; DTR + RTS + TX enabled, 8 bits
    OUT (DART_A_CTRL),A
    LD A,$01
    OUT (DART_A_CTRL),A
    XOR A
    OUT (DART_A_CTRL),A

    ; DART B: hardware-proven GPS/PC path, x32 async, 8-N-1, polling.
    LD A,$18
    OUT (DART_B_CTRL),A
    LD A,$04
    OUT (DART_B_CTRL),A
    LD A,$84
    OUT (DART_B_CTRL),A
    LD A,$03
    OUT (DART_B_CTRL),A
    LD A,$C1
    OUT (DART_B_CTRL),A
    LD A,$05
    OUT (DART_B_CTRL),A
    LD A,$EA
    OUT (DART_B_CTRL),A
    LD A,$01
    OUT (DART_B_CTRL),A
    XOR A
    OUT (DART_B_CTRL),A
    RET

DEBUG_TX_CHAR:
    PUSH BC
    LD B,A
DBG_TX_WAIT:
    IN A,(DART_A_CTRL)
    AND $04
    JR Z,DBG_TX_WAIT
    LD A,B
    OUT (DART_A_DATA),A
    POP BC
    RET

; HL -> zero-terminated ASCII string.
DEBUG_PRINT_Z:
    PUSH AF
    PUSH HL
DBG_PZ_LOOP:
    LD A,(HL)
    OR A
    JR Z,DBG_PZ_DONE
    CALL DEBUG_TX_CHAR
    INC HL
    JR DBG_PZ_LOOP
DBG_PZ_DONE:
    POP HL
    POP AF
    RET

DEBUG_CRLF:
    PUSH AF
    LD A,13
    CALL DEBUG_TX_CHAR
    LD A,10
    CALL DEBUG_TX_CHAR
    POP AF
    RET

; Print unsigned HL as exactly five decimal digits.  No RAM scratch is used.
DEBUG_U16:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    LD DE,10000
    CALL DEBUG_DIGIT
    LD DE,1000
    CALL DEBUG_DIGIT
    LD DE,100
    CALL DEBUG_DIGIT
    LD DE,10
    CALL DEBUG_DIGIT
    LD A,L
    ADD A,'0'
    CALL DEBUG_TX_CHAR
    POP HL
    POP DE
    POP BC
    POP AF
    RET

; Print signed HL as sign followed by five decimal digits.
DEBUG_S16:
    PUSH AF
    PUSH HL
    BIT 7,H
    JR Z,DBG_S16_POS
    LD A,'-'
    CALL DEBUG_TX_CHAR
    POP HL
    CALL ASTRO_NEG_HL
    CALL DEBUG_U16
    POP AF
    RET
DBG_S16_POS:
    LD A,'+'
    CALL DEBUG_TX_CHAR
    POP HL
    CALL DEBUG_U16
    POP AF
    RET

; One decimal digit from unsigned HL using divisor DE; remainder stays in HL.
DEBUG_DIGIT:
    LD B,'0'
DBG_DIGIT_LOOP:
    OR A
    SBC HL,DE
    JR C,DBG_DIGIT_DONE
    INC B
    JR DBG_DIGIT_LOOP
DBG_DIGIT_DONE:
    ADD HL,DE
    LD A,B
    JP DEBUG_TX_CHAR

; HL=label, DE=value.  Print LABEL + unsigned value + CR/LF.
DEBUG_LINE_U:
    PUSH HL
    PUSH DE
    CALL DEBUG_PRINT_Z
    POP DE
    EX DE,HL
    CALL DEBUG_U16
    CALL DEBUG_CRLF
    POP HL
    RET

; HL=label, DE=value.  Print LABEL + signed value + CR/LF.
DEBUG_LINE_S:
    PUSH HL
    PUSH DE
    CALL DEBUG_PRINT_Z
    POP DE
    EX DE,HL
    CALL DEBUG_S16
    CALL DEBUG_CRLF
    POP HL
    RET

DEBUG_HEADER:
    LD HL,DBG_MSG_HEADER
    CALL DEBUG_PRINT_Z
    CALL DEBUG_CRLF
    LD HL,DBG_FIXED_INPUTS
    CALL DEBUG_PRINT_Z
    CALL DEBUG_CRLF
    RET

DEBUG_DATE_STAGE:
    LD HL,DBG_MSG_DATE
    CALL DEBUG_PRINT_Z
    LD A,(AST_MONTH)
    LD L,A
    LD H,0
    CALL DEBUG_U16
    LD A,'/'
    CALL DEBUG_TX_CHAR
    LD A,(AST_DAY)
    LD L,A
    LD H,0
    CALL DEBUG_U16
    LD A,'/'
    CALL DEBUG_TX_CHAR
    LD A,(AST_YEAR)
    LD L,A
    LD H,0
    CALL DEBUG_U16
    CALL DEBUG_CRLF
    LD HL,DBG_MSG_TIME
    CALL DEBUG_PRINT_Z
    LD A,(AST_HOUR)
    LD L,A
    LD H,0
    CALL DEBUG_U16
    LD A,':'
    CALL DEBUG_TX_CHAR
    LD A,(AST_MINUTE)
    LD L,A
    LD H,0
    CALL DEBUG_U16
    LD A,':'
    CALL DEBUG_TX_CHAR
    LD A,(AST_SECOND)
    LD L,A
    LD H,0
    CALL DEBUG_U16
    CALL DEBUG_CRLF
    LD HL,DBG_L_DAYS
    LD DE,(AST_DAYS)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SM
    LD DE,(AST_SM)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SW
    LD DE,(AST_SW)
    JP DEBUG_LINE_U

DEBUG_PLANET_STAGE:
    LD HL,DBG_MSG_ELEMS
    CALL DEBUG_PRINT_Z
    CALL DEBUG_CRLF
    LD HL,DBG_L_N
    LD DE,(G_N)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_I
    LD DE,(G_I)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_W
    LD DE,(G_W)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_M
    LD DE,(G_M)
    JP DEBUG_LINE_U

DEBUG_EVENTS_STAGE:
    LD HL,DBG_MSG_EVENTS
    CALL DEBUG_PRINT_Z
    CALL DEBUG_CRLF
    LD HL,DBG_L_RISE
    LD DE,(AST_RISE)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SET
    LD DE,(AST_SET)
    JP DEBUG_LINE_U

DEBUG_CURRENT_STAGE:
    LD HL,DBG_MSG_VECTOR
    CALL DEBUG_PRINT_Z
    CALL DEBUG_CRLF
    LD HL,DBG_L_SMCUR
    LD DE,(G_SUN_M_CUR)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SE
    LD DE,(G_DBG_SUN_E)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SLON
    LD DE,(G_SUN_LON)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_PMCUR
    LD DE,(G_DBG_PLAN_M)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_PE
    LD DE,(G_DBG_PLAN_E)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_PAQ
    LD DE,(G_AQ)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_PAEQ
    LD DE,(G_AEQ)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_HOX
    LD DE,(G_DBG_HEL_X)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_HOY
    LD DE,(G_DBG_HEL_Y)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_HOZ
    LD DE,(G_DBG_HEL_Z)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_GEX
    LD DE,(G_DBG_GEO_X)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_GEY
    LD DE,(G_DBG_GEO_Y)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_GEZ
    LD DE,(G_DBG_GEO_Z)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_SX
    LD DE,(G_SX)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_SY
    LD DE,(G_SY)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_X
    LD DE,(AST_X)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_Y
    LD DE,(AST_Y)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_Z
    LD DE,(AST_Z)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_UTC_MIN
    LD DE,(G_UTC_MIN)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SM_NOW
    LD DE,(AST_SM)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_SW_NOW
    LD DE,(AST_SW)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_LON10
    LD DE,(G_SITE_LON10)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_LST0
    LD DE,(AST_LST0)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_LST
    LD DE,(G_TMPW0)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_EAST
    LD DE,(AST_EAST)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_NORTH
    LD DE,(AST_NORTH)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_UP
    LD DE,(AST_UP)
    CALL DEBUG_LINE_S
    LD HL,DBG_L_AZ
    LD DE,(AST_AZ10)
    CALL DEBUG_LINE_U
    LD HL,DBG_L_EL
    LD DE,(AST_EL10)
    CALL DEBUG_LINE_S
    ; Debug-only RA
    LD HL,(AST_Y)
    LD DE,(AST_X)
    CALL ASTRO_ATAN2_10
    EX DE,HL
    LD HL,DBG_L_RA10
    CALL DEBUG_LINE_U
    ; Debug-only declination
    LD HL,(AST_X)
    CALL ASTRO_SQUARE16
    CALL ASTRO_COPY_ACC_TO_N
    LD HL,(AST_Y)
    CALL ASTRO_SQUARE16
    CALL ASTRO_ADD_ACC_TO_N
    CALL ASTRO_ISQRT32
    EX DE,HL
    LD HL,(AST_Z)
    CALL ASTRO_ATAN2_SIGNED90
    EX DE,HL
    LD HL,DBG_L_DEC10
    CALL DEBUG_LINE_S
    LD HL,DBG_L_OBL10
    LD DE,234
    CALL DEBUG_LINE_U
    LD HL,DBG_MSG_DONE
    CALL DEBUG_PRINT_Z
    JP DEBUG_CRLF

DISPLAY_INIT:
    LD A,$10
    OUT (PIO_A_DATA),A
    XOR A
    OUT (PIO_A_DATA),A
    CALL DELAY_2MS
    LD A,$10
    OUT (PIO_A_DATA),A
    CALL DELAY_2MS
    LD A,$C0
    CALL DISPLAY_SEND_RAW
    LD A,$FF
    CALL DISPLAY_SEND_RAW
    LD A,$AF
    CALL DISPLAY_SEND_RAW
    RET
DISPLAY_CLEAR:
    LD A,$AF
    CALL DISPLAY_SEND_RAW
    LD B,16
DC_LOOP:
    LD A,' '
    CALL DISPLAY_PUT_ASCII
    DJNZ DC_LOOP
    LD A,$AF
    CALL DISPLAY_SEND_RAW
    RET
DISPLAY_SHOW:
    PUSH HL
    CALL DISPLAY_CLEAR
    POP HL
    LD B,16
DSHOW_LOOP:
    LD A,(HL)
    OR A
    JR Z,DSHOW_PAD
    CALL DISPLAY_PUT_ASCII
    INC HL
    DJNZ DSHOW_LOOP
    RET
DSHOW_PAD:
    LD A,' '
    CALL DISPLAY_PUT_ASCII
    DJNZ DSHOW_PAD
    RET
DISPLAY_PRINT_Z:
    LD A,(HL)
    OR A
    RET Z
    CALL DISPLAY_PUT_ASCII
    INC HL
    JR DISPLAY_PRINT_Z
DISPLAY_PUT_ASCII:
    CP '('
    JR Z,DPA_LP
    CP ')'
    JR Z,DPA_RP
    CP 'a'
    JR C,DPA_MAP
    CP 'z'+1
    JR NC,DPA_MAP
    AND $DF
DPA_MAP:
    AND $3F
    JP DISPLAY_SEND_RAW
DPA_LP:
    LD A,$1B
    JP DISPLAY_SEND_RAW
DPA_RP:
    LD A,$1D
    JP DISPLAY_SEND_RAW
DISPLAY_SEND_RAW:
    PUSH BC
    PUSH DE
    LD D,A
    LD B,8
DSR_BIT:
    RLC D
    LD A,$50
    JR NC,DSR_RDY
    OR $20
DSR_RDY:
    OUT (PIO_A_DATA),A
    AND $BF
    OUT (PIO_A_DATA),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    DJNZ DSR_BIT
    POP DE
    POP BC
    RET
DISPLAY_DEC2:
    LD B,0
DD2_LOOP:
    CP 10
    JR C,DD2_DONE
    SUB 10
    INC B
    JR DD2_LOOP
DD2_DONE:
    LD C,A
    LD A,B
    ADD A,'0'
    CALL DISPLAY_PUT_ASCII
    LD A,C
    ADD A,'0'
    JP DISPLAY_PUT_ASCII
DELAY_2MS:
    PUSH BC
    LD B,4
D2_OUTER:
    LD C,$FF
D2_INNER:
    DEC C
    JR NZ,D2_INNER
    DJNZ D2_OUTER
    POP BC
    RET

; ============================================================================
; TRANZ 330 - FIXED-POINT JUPITER ASTRONOMY MODULE V1
; Target: Z80 / VeriFone TRANZ 330 / 16-character MSC1937 VFD
;
; SITE:
;   Latitude  = +30.3950 deg
;   Longitude = -88.1805 deg (west negative)
;   Local time = UTC-5, fixed
;
; DISPLAY ROTATION (ENTER advances, CLEAR is handled globally by V4 firmware):
;   JUPITER VIS
;   JUPITER NOVIS
;   RISE 04:21
;   SET 17:47
;   AZ 255.8 DEG
;   EL +54.7 DEG
;
; "VIS" here means Jupiter is above the standard apparent rise/set horizon
; (-0.5667 deg).  It does NOT attempt to judge daylight, clouds, buildings,
; extinction, or naked-eye detectability.
;
; FIXED-POINT REPRESENTATION
;   Angles:       tenths of a degree, 0..3599
;   Trig:         signed Q15, -32767..+32767
;   Coordinates:  signed 16-bit, 4096 units = 1 AU
;   Times:        local minutes after midnight, 0..1439
;
; MODEL
;   Low-precision orbital elements for Sun/Earth and Jupiter, with the
;   principal Jupiter/Saturn longitude perturbation series.
;   Ecliptic -> equatorial -> local horizontal transformation.
;   Rise/set are found by a one-minute scan of the local civil day.
;
; EXPECTED PRACTICAL ACCURACY
;   Intended for a retrocomputer planet finder, not an observatory almanac.
;   With 0.1-degree trig quantization, expect rise/set to usually be within
;   a few minutes and instantaneous az/el generally within about 1 degree.
;
; EXTERNAL ROUTINES PROVIDED BY TRANZ330_MULTI_V4:
;   DISPLAY_SHOW       HL -> zero-terminated string, clears/pads
;   DISPLAY_CLEAR
;   DISPLAY_PRINT_Z
;   DISPLAY_PUT_ASCII  A=ASCII
;   DISPLAY_DEC2       A=0..99
;   KEY_GET            A=raw key code
;   KEYCODE_TO_DIGIT   A=key code -> A=0..9, C clear; C set if non-digit
;
; External key constants expected:
;   KEY_CLEAR       EQU $04
;   KEY_BACKSPACE   EQU $08
;   KEY_ENTER       EQU $10
;
; INTEGRATION:
;   1) Reserve the ASTRO RAM block below.
;   2) CALL ASTRO_CLOCK_INIT once after DISPLAY_INIT during MAIN startup.
;   3) Replace OPTION9 with:
;
;        OPTION9:
;                DI
;                CALL ASTRO_JUPITER_RUN
;                JP MENU
;
; ============================================================================

; RTC I/O map is defined once at the top of the ROM.

; ----------------------------------------------------------------------------
; Site constants
; ----------------------------------------------------------------------------
UTC_OFFSET_DEFAULT EQU 0             ; GPS is UTC; user selects local whole-hour offset after each fix
LON10           EQU -888           ; -88.7548 deg rounded to -88.8 in 0.1-degree units
LAT_SIN_Q15     EQU 16564          ; sin(+30.3642 deg) * 32767
LAT_COS_Q15     EQU 28272          ; cos(+30.3642 deg) * 32767
H0_SIN_Q15      EQU -324           ; sin(-0.5667 deg) * 32767
OBL_SIN_Q15     EQU 13034          ; sin(23.4393 deg)
OBL_COS_Q15     EQU 30063          ; cos(23.4393 deg)

; Orbit coordinate constants, 4096 units = 1 AU
SUN_A_Q         EQU 4096
SUN_AE_Q        EQU 68             ; a*e*4096
SUN_B_Q         EQU 4095           ; a*sqrt(1-e^2)*4096

JUP_A_Q         EQU 21310          ; 5.20256 AU * 4096
JUP_AE_Q        EQU 1033           ; a*e*4096
JUP_B_Q         EQU 21285          ; a*sqrt(1-e^2)*4096

; ----------------------------------------------------------------------------
; RAM.  Move this block if it collides with other firmware.
; ----------------------------------------------------------------------------
; Preserve original astronomy RAM addresses for compatibility.
ASTRO_RAM       EQU $8900

AST_CLOCK_OK    EQU ASTRO_RAM+0
AST_YEAR        EQU ASTRO_RAM+1    ; 0..99 => 2000..2099
AST_MONTH       EQU ASTRO_RAM+2
AST_DAY         EQU ASTRO_RAM+3
AST_HOUR        EQU ASTRO_RAM+4
AST_MINUTE      EQU ASTRO_RAM+5

AST_DAYS        EQU ASTRO_RAM+6    ; word, days since 1999-12-31

AST_SM          EQU ASTRO_RAM+8    ; Sun mean anomaly, angle10
AST_SMF         EQU ASTRO_RAM+10   ; fractional tenth, scale 10000
AST_SW          EQU ASTRO_RAM+12   ; Sun longitude perihelion
AST_SWF         EQU ASTRO_RAM+14

AST_JN          EQU ASTRO_RAM+16
AST_JNF         EQU ASTRO_RAM+18
AST_JW          EQU ASTRO_RAM+20
AST_JWF         EQU ASTRO_RAM+22
AST_JM          EQU ASTRO_RAM+24
AST_JMF         EQU ASTRO_RAM+26
AST_SATM        EQU ASTRO_RAM+28
AST_SATMF       EQU ASTRO_RAM+30

AST_X           EQU ASTRO_RAM+32   ; equatorial Jupiter vector
AST_Y           EQU ASTRO_RAM+34
AST_Z           EQU ASTRO_RAM+36

AST_RISE        EQU ASTRO_RAM+38   ; local minute, FFFF=none
AST_SET         EQU ASTRO_RAM+40
AST_AZ10        EQU ASTRO_RAM+42   ; 0..3599
AST_EL10        EQU ASTRO_RAM+44   ; signed -900..+900
AST_VISIBLE     EQU ASTRO_RAM+46

AST_LST0        EQU ASTRO_RAM+47   ; local sidereal angle at local midnight
AST_HORIZON_Q   EQU ASTRO_RAM+49   ; signed coordinate threshold
AST_DIST_Q      EQU ASTRO_RAM+51

AST_Q           EQU ASTRO_RAM+53   ; local intermediate
AST_EAST        EQU ASTRO_RAM+55
AST_NORTH       EQU ASTRO_RAM+57
AST_UP          EQU ASTRO_RAM+59
AST_HOR         EQU ASTRO_RAM+61

AST_TMP0        EQU ASTRO_RAM+63
AST_TMP1        EQU ASTRO_RAM+65
AST_TMP2        EQU ASTRO_RAM+67
AST_TMP3        EQU ASTRO_RAM+69
AST_TMP4        EQU ASTRO_RAM+71
AST_TMP5        EQU ASTRO_RAM+73
AST_TMP6        EQU ASTRO_RAM+75
AST_TMP7        EQU ASTRO_RAM+77
AST_INPUT_MODE  EQU ASTRO_RAM+79   ; 0=date, 1=time

AST_INPUT       EQU ASTRO_RAM+80   ; 6 bytes for manual clock entry
AST_INCOUNT     EQU ASTRO_RAM+86
AST_SECOND      EQU ASTRO_RAM+87   ; 0..59, manual/RTC seconds

; 32-bit multiply / compare scratch, little-endian
M32_MC          EQU ASTRO_RAM+88   ; 4 bytes multiplicand
M32_MR          EQU ASTRO_RAM+92   ; 2 bytes multiplier
M32_ACC         EQU ASTRO_RAM+94   ; 4 bytes accumulator
M32_N           EQU ASTRO_RAM+98   ; 4 bytes sqrt target
M32_TEST        EQU ASTRO_RAM+102  ; 4 bytes square/test value
M32_SIGN        EQU ASTRO_RAM+106

AST_SCAN_MIN    EQU ASTRO_RAM+108  ; word
AST_LOOPCTR     EQU ASTRO_RAM+110  ; byte
AST_LOW         EQU ASTRO_RAM+111  ; word
AST_HIGH        EQU ASTRO_RAM+113  ; word
AST_PREV        EQU ASTRO_RAM+115  ; byte
AST_QUAD        EQU ASTRO_RAM+116  ; byte
AST_LOCAL_MIN   EQU ASTRO_RAM+117  ; word
AST_UTC_OFFSET_MIN EQU ASTRO_RAM+119 ; signed minutes, e.g. -300 = UTC-5
AST_UTC_PENDING_HR EQU ASTRO_RAM+121 ; pending whole-hour magnitude 0..12
AST_UTC_PENDING_SIGN EQU ASTRO_RAM+122 ; legacy/manual startup field
AST_UTC_OFFSET_HR EQU ASTRO_RAM+123    ; signed whole-hour runtime offset, -12..+12

; ============================================================================
; PUBLIC ENTRY POINTS
; ============================================================================

; ----------------------------------------------------------------------------
; ASTRO_CLOCK_INIT
; Read local civil date/time from the TRANZ RTC.
; If invalid, ask the user once for MMDDYY and HHMM.
; ----------------------------------------------------------------------------
ASTRO_CLOCK_INIT:
        ; Read the MSM6242-family RTC using the same HOLD/BUSY convention
        ; used by the original VeriFone firmware: write $05 to control D
        ; (HOLD request while preserving IRQ flag semantics), wait for BUSY=0,
        ; read the twelve BCD digit registers, then write $04 to release HOLD.
        CALL RTC_HOLD_WAIT
        JP C,ASTRO_CLOCK_BAD

        IN A,(RTC_SEC_1)
        AND $0F
        LD C,A
        IN A,(RTC_SEC_10)
        AND $0F
        CALL RTC_DIGITS_TO_BIN
        LD (RTC_TMP_SECOND),A

        IN A,(RTC_MIN_1)
        AND $0F
        LD C,A
        IN A,(RTC_MIN_10)
        AND $0F
        CALL RTC_DIGITS_TO_BIN
        LD (RTC_TMP_MINUTE),A

        IN A,(RTC_HOUR_1)
        AND $0F
        LD C,A
        IN A,(RTC_HOUR_10)
        AND $03              ; 24-hour mode: only 0..2 is meaningful
        CALL RTC_DIGITS_TO_BIN
        LD (RTC_TMP_HOUR),A

        IN A,(RTC_DAY_1)
        AND $0F
        LD C,A
        IN A,(RTC_DAY_10)
        AND $0F
        CALL RTC_DIGITS_TO_BIN
        LD (RTC_TMP_DAY),A

        IN A,(RTC_MONTH_1)
        AND $0F
        LD C,A
        IN A,(RTC_MONTH_10)
        AND $0F
        CALL RTC_DIGITS_TO_BIN
        LD (RTC_TMP_MONTH),A

        IN A,(RTC_YEAR_1)
        AND $0F
        LD C,A
        IN A,(RTC_YEAR_10)
        AND $0F
        CALL RTC_DIGITS_TO_BIN
        LD (RTC_TMP_YEAR),A

        CALL RTC_HOLD_RELEASE

        ; Range validation.  Day/month combination is validated later by
        ; astronomy date handling; reject impossible basic RTC fields here.
        LD A,(RTC_TMP_SECOND)
        CP 60
        JR NC,ASTRO_CLOCK_BAD_RELEASED
        LD A,(RTC_TMP_MINUTE)
        CP 60
        JR NC,ASTRO_CLOCK_BAD_RELEASED
        LD A,(RTC_TMP_HOUR)
        CP 24
        JR NC,ASTRO_CLOCK_BAD_RELEASED
        LD A,(RTC_TMP_MONTH)
        OR A
        JR Z,ASTRO_CLOCK_BAD_RELEASED
        CP 13
        JR NC,ASTRO_CLOCK_BAD_RELEASED
        LD A,(RTC_TMP_DAY)
        OR A
        JR Z,ASTRO_CLOCK_BAD_RELEASED
        CP 32
        JR NC,ASTRO_CLOCK_BAD_RELEASED

        ; Snapshot is valid: commit it atomically to the astronomy clock.
        LD A,(RTC_TMP_YEAR)
        LD (AST_YEAR),A
        LD A,(RTC_TMP_MONTH)
        LD (AST_MONTH),A
        LD A,(RTC_TMP_DAY)
        LD (AST_DAY),A
        LD A,(RTC_TMP_HOUR)
        LD (AST_HOUR),A
        LD A,(RTC_TMP_MINUTE)
        LD (AST_MINUTE),A
        LD A,(RTC_TMP_SECOND)
        LD (AST_SECOND),A

        ; Reading the RTC must not alter the user-selected UTC offset.
        LD A,1
        LD (AST_CLOCK_OK),A
        OR A                    ; clear carry
        RET

ASTRO_CLOCK_BAD:
        ; RTC_HOLD_WAIT already releases HOLD on timeout.
ASTRO_CLOCK_BAD_RELEASED:
        XOR A
        LD (AST_CLOCK_OK),A
        SCF
        RET

; A=tens digit, C=ones digit -> A=binary 0..99.
RTC_DIGITS_TO_BIN:
        LD B,A
        ADD A,A                 ; 2*tens
        ADD A,A                 ; 4*tens
        ADD A,B                 ; 5*tens
        ADD A,A                 ; 10*tens
        ADD A,C
        RET

; Assert HOLD and wait for BUSY to clear.  The finite timeout prevents a
; failed/missing RTC from hanging the terminal forever.
RTC_HOLD_WAIT:
        LD A,$05
        OUT (RTC_CTRL_D),A
        LD BC,$FFFF
RTC_HW_LOOP:
        IN A,(RTC_CTRL_D)
        AND $02
        JR Z,RTC_HW_READY
        DEC BC
        LD A,B
        OR C
        JR NZ,RTC_HW_LOOP
        CALL RTC_HOLD_RELEASE
        SCF
        RET
RTC_HW_READY:
        OR A                    ; clear carry
        RET

RTC_HOLD_RELEASE:
        LD A,$04
        OUT (RTC_CTRL_D),A
        RET

; Write AST_* local civil time to RTC digit registers.  Weekday is deliberately
; left untouched; the original VeriFone 12-digit write path likewise handles
; $3B..$30 separately from weekday $3C.
RTC_WRITE_LOCAL:
        CALL RTC_HOLD_WAIT
        RET C

        LD A,(AST_SECOND)
        CALL RTC_BIN_TO_DIGITS
        LD A,C
        OUT (RTC_SEC_1),A
        LD A,B
        OUT (RTC_SEC_10),A

        LD A,(AST_MINUTE)
        CALL RTC_BIN_TO_DIGITS
        LD A,C
        OUT (RTC_MIN_1),A
        LD A,B
        OUT (RTC_MIN_10),A

        LD A,(AST_HOUR)
        CALL RTC_BIN_TO_DIGITS
        LD A,C
        OUT (RTC_HOUR_1),A
        LD A,B
        OUT (RTC_HOUR_10),A

        LD A,(AST_DAY)
        CALL RTC_BIN_TO_DIGITS
        LD A,C
        OUT (RTC_DAY_1),A
        LD A,B
        OUT (RTC_DAY_10),A

        LD A,(AST_MONTH)
        CALL RTC_BIN_TO_DIGITS
        LD A,C
        OUT (RTC_MONTH_1),A
        LD A,B
        OUT (RTC_MONTH_10),A

        LD A,(AST_YEAR)
        CALL RTC_BIN_TO_DIGITS
        LD A,C
        OUT (RTC_YEAR_1),A
        LD A,B
        OUT (RTC_YEAR_10),A

        CALL RTC_HOLD_RELEASE
        OR A
        RET

; A=0..99 -> B=tens, C=ones.
RTC_BIN_TO_DIGITS:
        LD B,0
RTC_BTD_LOOP:
        CP 10
        JR C,RTC_BTD_DONE
        SUB 10
        INC B
        JR RTC_BTD_LOOP
RTC_BTD_DONE:
        LD C,A
        RET

; ----------------------------------------------------------------------------
; ASTRO_STARTUP_INPUT
; Startup civil-time entry used until a GPS module is installed.
; Latitude/longitude remain fixed. UTC defaults to -5 but is runtime-editable.
;
; Sequence:
;   DATE MM/DD/YY  -> six digits -> MM/DD/YY ENTER ?
;       ENTER accepts; BACKSPACE returns to blank DATE entry.
;   TIME HH/MM/SS  -> six digits -> HH/MM/SS ENTER ?
;       ENTER accepts; CLEAR returns to blank TIME entry.
;   UTC OFFSET ?   -> * selects negative, # selects positive, then type 0..12.
;       confirmation shows UTC -N ENTER or UTC +N ENTER; second ENTER accepts.
;       ENTER with no sign/digits keeps the current/default UTC-5.
;       CLEAR returns to UTC OFFSET ?.
; ALPHA at any startup input screen performs the full software reset.
; ----------------------------------------------------------------------------
ASTRO_STARTUP_INPUT:
        ; Establish known defaults first.  They are replaced by accepted input.
        CALL ASTRO_CLOCK_INIT

ASI_DATE_RESTART:
        XOR A
        LD (AST_INPUT_MODE),A
        CALL ASI_READ_SIX
        CALL ASI_PARSE_DATE
        JR C,ASI_DATE_RESTART
        CALL ASI_DRAW_DATE_CONFIRM
ASI_DATE_CONFIRM_WAIT:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_BACKSPACE
        JR Z,ASI_DATE_RESTART
        CP KEY_ENTER
        JR NZ,ASI_DATE_CONFIRM_WAIT

ASI_TIME_RESTART:
        LD A,1
        LD (AST_INPUT_MODE),A
        CALL ASI_READ_SIX
        CALL ASI_PARSE_TIME
        JR C,ASI_TIME_RESTART
        CALL ASI_DRAW_TIME_CONFIRM
ASI_TIME_CONFIRM_WAIT:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JR Z,ASI_TIME_RESTART
        CP KEY_ENTER
        JR NZ,ASI_TIME_CONFIRM_WAIT

ASI_UTC_PROMPT:
        ; Signed UTC offset entry using the physical 4x4 keypad:
        ;   * = negative/west offset
        ;   # = positive/east offset
        ; ENTER here with no sign/digits keeps the current/default offset.
        XOR A
        LD (AST_INCOUNT),A
        LD A,$FF
        LD (AST_UTC_PENDING_SIGN),A
        LD HL,MSG_UTC_OFFSET_Q
        CALL DISPLAY_SHOW

ASI_UTC_PROMPT_WAIT:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JP Z,ASI_UTC_PROMPT
        CP KEY_ENTER
        JR Z,ASI_UTC_ENTER_PRESSED
        CP KEY_UTC_NEG
        JR Z,ASI_UTC_SET_NEG
        CP KEY_UTC_POS
        JR Z,ASI_UTC_SET_POS

        ; Digits are accepted only after * or # has selected the sign.
        PUSH AF
        LD A,(AST_UTC_PENDING_SIGN)
        CP $FF
        JR Z,ASI_UTC_NO_DIGIT_POP
        POP AF
        CALL KEYCODE_TO_DIGIT
        JR C,ASI_UTC_PROMPT_WAIT

        ; Store at most two digits in AST_INPUT[0..1].
        LD C,A
        LD A,(AST_INCOUNT)
        CP 2
        JR NC,ASI_UTC_PROMPT_WAIT
        LD E,A
        LD D,0
        LD HL,AST_INPUT
        ADD HL,DE
        LD (HL),C
        LD A,(AST_INCOUNT)
        INC A
        LD (AST_INCOUNT),A
        CALL ASI_DRAW_UTC_ENTRY
        JR ASI_UTC_PROMPT_WAIT

ASI_UTC_NO_DIGIT_POP:
        POP AF
        JR ASI_UTC_PROMPT_WAIT

ASI_UTC_SET_NEG:
        XOR A                         ; 0 = negative
        LD (AST_UTC_PENDING_SIGN),A
        CALL ASI_DRAW_UTC_ENTRY
        JR ASI_UTC_PROMPT_WAIT

ASI_UTC_SET_POS:
        LD A,1                        ; 1 = positive
        LD (AST_UTC_PENDING_SIGN),A
        CALL ASI_DRAW_UTC_ENTRY
        JR ASI_UTC_PROMPT_WAIT

ASI_UTC_ENTER_PRESSED:
        LD A,(AST_INCOUNT)
        OR A
        JR NZ,ASI_UTC_PARSE

        ; No digits entered.  ENTER is allowed only if no explicit sign has
        ; been chosen; this preserves the current/default runtime offset.
        LD A,(AST_UTC_PENDING_SIGN)
        CP $FF
        JR NZ,ASI_UTC_PROMPT_WAIT

ASI_UTC_USE_CURRENT:
        LD HL,(AST_UTC_OFFSET_MIN)
        BIT 7,H
        JR Z,ASI_UTC_CURRENT_POS
        XOR A                         ; negative
        LD (AST_UTC_PENDING_SIGN),A
        JR ASI_UTC_CURRENT_MAG
ASI_UTC_CURRENT_POS:
        LD A,1                        ; positive (also harmless for UTC 0)
        LD (AST_UTC_PENDING_SIGN),A
ASI_UTC_CURRENT_MAG:
        CALL ASI_UTC_MIN_TO_HOURS
        LD A,L
        LD (AST_UTC_PENDING_HR),A
        JR ASI_UTC_CONFIRM_DRAW

ASI_UTC_PARSE:
        ; Convert one or two entered digits to an unsigned hour magnitude.
        LD A,(AST_INPUT)
        LD B,A
        LD A,(AST_INCOUNT)
        CP 1
        JR NZ,ASI_UTC_TWO_DIGITS
        LD A,B                        ; one digit: restore entered hour value
        JR ASI_UTC_HAVE_HOURS
ASI_UTC_TWO_DIGITS:
        LD A,B
        ADD A,A                      ; *2
        LD C,A
        ADD A,A                      ; *4
        ADD A,A                      ; *8
        ADD A,C                      ; *10
        LD B,A
        LD A,(AST_INPUT+1)
        ADD A,B
ASI_UTC_HAVE_HOURS:
        CP 13                         ; permit UTC-12 through UTC+12
        JP NC,ASI_UTC_PROMPT
        LD (AST_UTC_PENDING_HR),A

ASI_UTC_CONFIRM_DRAW:
        CALL ASI_DRAW_UTC_CONFIRM
ASI_UTC_CONFIRM_WAIT:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JP Z,ASI_UTC_PROMPT
        CP KEY_ENTER
        JR NZ,ASI_UTC_CONFIRM_WAIT

        ; Commit: pending sign + hours -> signed runtime minutes.
        LD A,(AST_UTC_PENDING_HR)
        CALL ASI_UTC_HOURS_TO_MIN
        LD (AST_UTC_OFFSET_MIN),HL
        LD A,1
        LD (AST_CLOCK_OK),A
        CALL DISPLAY_CLEAR
        RET

; Draw typed UTC value as "UTC OFFSET -N" or "UTC OFFSET +N".
; With no digits yet it shows just "UTC OFFSET -" / "UTC OFFSET +".
ASI_DRAW_UTC_ENTRY:
        CALL DISPLAY_CLEAR
        LD HL,MSG_UTC_ENTRY_PREFIX
        CALL DISPLAY_PRINT_Z
        CALL ASI_PRINT_UTC_SIGN
        LD A,(AST_INCOUNT)
        OR A
        RET Z
        CP 1
        JR NZ,ASI_DUE_TWO
        LD A,(AST_INPUT)
        JP ASI_PRINT_U8_0_12
ASI_DUE_TWO:
        LD A,(AST_INPUT)
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_INPUT+1)
        ADD A,'0'
        JP DISPLAY_PUT_ASCII

; Draw confirmation "UTC -N ENTER" or "UTC +N ENTER".
ASI_DRAW_UTC_CONFIRM:
        CALL DISPLAY_CLEAR
        LD HL,MSG_UTC_CONFIRM_PREFIX
        CALL DISPLAY_PRINT_Z
        CALL ASI_PRINT_UTC_SIGN
        LD A,(AST_UTC_PENDING_HR)
        CALL ASI_PRINT_U8_0_12
        LD HL,MSG_ENTER_SUFFIX2
        JP DISPLAY_PRINT_Z

; Output '-' for *=negative or '+' for #=positive.
ASI_PRINT_UTC_SIGN:
        LD A,(AST_UTC_PENDING_SIGN)
        OR A
        LD A,'-'
        JR Z,ASI_PUS_OUT
        LD A,'+'
ASI_PUS_OUT:
        JP DISPLAY_PUT_ASCII

; Convert signed minute offset in HL to positive whole-hour magnitude.
ASI_UTC_MIN_TO_HOURS:
        BIT 7,H
        JR Z,ASI_UMH_POS
        XOR A
        SUB L
        LD L,A
        LD A,0
        SBC A,H
        LD H,A
ASI_UMH_POS:
        LD B,0
ASI_UMH_LOOP:
        LD DE,60
        OR A
        SBC HL,DE
        JR C,ASI_UMH_DONE
        INC B
        JR ASI_UMH_LOOP
ASI_UMH_DONE:
        LD H,0
        LD L,B
        RET

; Convert A=0..12 hours and AST_UTC_PENDING_SIGN to signed minutes in HL.
ASI_UTC_HOURS_TO_MIN:
        LD B,A
        LD HL,0
        OR A
        RET Z
        LD A,(AST_UTC_PENDING_SIGN)
        OR A
        JR Z,ASI_UHTM_NEG
        LD DE,60
        JR ASI_UHTM_LOOP
ASI_UHTM_NEG:
        LD DE,-60
ASI_UHTM_LOOP:
        ADD HL,DE
        DJNZ ASI_UHTM_LOOP
        RET

; Print unsigned A in range 0..12 without leading zero.
ASI_PRINT_U8_0_12:
        CP 10
        JR C,ASI_PU8_ONE
        PUSH AF
        LD A,'1'
        CALL DISPLAY_PUT_ASCII
        POP AF
        SUB 10
ASI_PU8_ONE:
        ADD A,'0'
        JP DISPLAY_PUT_ASCII

; Read exactly six keypad digits.  The display is redrawn after every digit.
; BACKSPACE removes the most recent digit.  CLEAR restarts the current field.
; On entry the mode is AST_INPUT_MODE: 0=date, 1=time.
ASI_READ_SIX:
        XOR A
        LD (AST_INCOUNT),A
ASI_READ_REDRAW:
        CALL DISPLAY_CLEAR
        LD A,(AST_INPUT_MODE)
        OR A
        JR NZ,ASI_READ_TIME
        LD HL,MSG_DATE_PREFIX
        CALL DISPLAY_PRINT_Z
        LD HL,MSG_DATE_MASK
        JR ASI_READ_FORMAT
ASI_READ_TIME:
        LD HL,MSG_TIME_PREFIX
        CALL DISPLAY_PRINT_Z
        LD HL,MSG_START_TIME_MASK
ASI_READ_FORMAT:
        LD DE,AST_INPUT
        LD A,(AST_INCOUNT)
        LD (AST_TMP5),A
        LD B,8
ASI_READ_CHAR:
        LD A,(HL)
        CP '/'
        JR Z,ASI_READ_LITERAL
        ; Placeholder: use entered digit if one remains, else template letter.
        LD A,(AST_TMP5)
        OR A
        JR Z,ASI_READ_MASK
        LD A,(DE)
        ADD A,'0'
        INC DE
        LD C,A
        LD A,(AST_TMP5)
        DEC A
        LD (AST_TMP5),A
        LD A,C
        JR ASI_READ_PUT
ASI_READ_MASK:
        LD A,(HL)
        JR ASI_READ_PUT
ASI_READ_LITERAL:
        LD A,'/'
ASI_READ_PUT:
        PUSH BC
        PUSH DE
        PUSH HL
        CALL DISPLAY_PUT_ASCII
        POP HL
        POP DE
        POP BC
        INC HL
        DJNZ ASI_READ_CHAR

        LD A,(AST_INCOUNT)
        CP 6
        RET Z
ASI_READ_KEY:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JP Z,ASI_READ_SIX
        CP KEY_BACKSPACE
        JR Z,ASI_READ_BACK
        CALL KEYCODE_TO_DIGIT
        JR C,ASI_READ_KEY
        LD C,A
        LD A,(AST_INCOUNT)
        CP 6
        JP NC,ASI_READ_REDRAW          ; V11d11 safety: relative branch was near -128 limit
        LD E,A
        LD D,0
        LD HL,AST_INPUT
        ADD HL,DE
        LD (HL),C
        LD A,E
        INC A
        LD (AST_INCOUNT),A
        JP ASI_READ_REDRAW
ASI_READ_BACK:
        LD A,(AST_INCOUNT)
        OR A
        JR Z,ASI_READ_KEY
        DEC A
        LD (AST_INCOUNT),A
        JP ASI_READ_REDRAW

; Convert AST_INPUT MMDDYY and validate the civil date.
; C set = invalid, C clear = accepted.
ASI_PARSE_DATE:
        LD HL,AST_INPUT
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_MONTH),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_DAY),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_YEAR),A

        LD A,(AST_MONTH)
        OR A
        JR Z,ASI_DATE_BAD
        CP 13
        JR NC,ASI_DATE_BAD
        LD A,(AST_DAY)
        OR A
        JR Z,ASI_DATE_BAD
        CALL ASTRO_DAYS_IN_MONTH
        LD B,A
        LD A,(AST_DAY)
        CP B
        JR Z,ASI_DATE_GOOD
        JR C,ASI_DATE_GOOD
ASI_DATE_BAD:
        SCF
        RET
ASI_DATE_GOOD:
        OR A
        RET

; Convert AST_INPUT HHMMSS and validate time.
ASI_PARSE_TIME:
        LD HL,AST_INPUT
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_HOUR),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_MINUTE),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_SECOND),A
        LD A,(AST_HOUR)
        CP 24
        JR NC,ASI_TIME_BAD
        LD A,(AST_MINUTE)
        CP 60
        JR NC,ASI_TIME_BAD
        LD A,(AST_SECOND)
        CP 60
        JR NC,ASI_TIME_BAD
        OR A
        RET
ASI_TIME_BAD:
        SCF
        RET

ASI_DRAW_DATE_CONFIRM:
        CALL DISPLAY_CLEAR
        LD A,(AST_MONTH)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_DAY)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_YEAR)
        CALL DISPLAY_DEC2
        LD HL,MSG_ENTER_Q_SUFFIX
        JP DISPLAY_PRINT_Z

ASI_DRAW_TIME_CONFIRM:
        CALL DISPLAY_CLEAR
        LD A,(AST_HOUR)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_MINUTE)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_SECOND)
        CALL DISPLAY_DEC2
        LD HL,MSG_ENTER_Q_SUFFIX
        JP DISPLAY_PRINT_Z

; ----------------------------------------------------------------------------
; ASTRO_JUPITER_RUN
; Re-read the RTC if it is valid.  If the RTC is bad, keep the manual
; session time entered at startup.  Then compute today's rise/set and the
; current azimuth/elevation, and enter the five-screen ENTER rotation.
; ----------------------------------------------------------------------------
ASTRO_JUPITER_RUN:
        LD A,(AST_CLOCK_OK)
        OR A
        CALL Z,ASTRO_CLOCK_INIT

        ; V1H manual-clock mode: keep the startup-entered date/time.
AJR_HAVE_TIME:
        CALL ASTRO_DAY_NUMBER
        CALL ASTRO_EVOLVE_ELEMENTS
        CALL ASTRO_RISE_SET
        CALL ASTRO_CURRENT_HORIZONTAL
        JP ASTRO_UI

; ============================================================================
; USER INTERFACE
; ============================================================================

ASTRO_UI:
        XOR A                     ; screen 0
AUI_DRAW:
        LD (AST_TMP7),A
        OR A
        JP Z,AUI_PLANET
        CP 1
        JP Z,AUI_RISE
        CP 2
        JP Z,AUI_SET
        CP 3
        JP Z,AUI_AZ
        JP AUI_EL

AUI_PLANET:
        LD A,(AST_VISIBLE)
        OR A
        JR Z,AUI_NOVIS
        LD HL,MSG_JUP_VIS
        CALL DISPLAY_SHOW
        JP AUI_WAIT
AUI_NOVIS:
        LD HL,MSG_JUP_NOVIS
        CALL DISPLAY_SHOW
        JP AUI_WAIT

AUI_RISE:
        CALL DISPLAY_CLEAR
        LD HL,MSG_RISE
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_RISE)
        LD A,H
        CP $FF
        JR NZ,AUI_RISE_TIME
        LD A,L
        CP $FF
        JR NZ,AUI_RISE_TIME
        LD HL,MSG_NONE
        CALL DISPLAY_PRINT_Z
        JP AUI_WAIT
AUI_RISE_TIME:
        CALL ASTRO_PRINT_HHMM
        LD A,'L'
        CALL DISPLAY_PUT_ASCII
        JP AUI_WAIT

AUI_SET:
        CALL DISPLAY_CLEAR
        LD HL,MSG_SET
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_SET)
        LD A,H
        CP $FF
        JR NZ,AUI_SET_TIME
        LD A,L
        CP $FF
        JR NZ,AUI_SET_TIME
        LD HL,MSG_NONE
        CALL DISPLAY_PRINT_Z
        JP AUI_WAIT
AUI_SET_TIME:
        CALL ASTRO_PRINT_HHMM
        LD A,'L'
        CALL DISPLAY_PUT_ASCII
        JP AUI_WAIT

AUI_AZ:
        CALL DISPLAY_CLEAR
        LD HL,MSG_AZ
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_AZ10)
        CALL ASTRO_PRINT_AZ10
        LD HL,MSG_DEG
        CALL DISPLAY_PRINT_Z
        JP AUI_WAIT

AUI_EL:
        CALL DISPLAY_CLEAR
        LD HL,MSG_EL
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_EL10)
        CALL ASTRO_PRINT_EL10
        LD HL,MSG_DEG
        CALL DISPLAY_PRINT_Z

AUI_WAIT:
        CALL KEY_GET
        CP KEY_ENTER
        JR NZ,AUI_WAIT            ; CLEAR is already a global jump to MENU
        LD A,(AST_TMP7)
        INC A
        CP 5
        JP C,AUI_DRAW
        XOR A
        JP AUI_DRAW

; ============================================================================
; RTC + MANUAL DATE/TIME
; ============================================================================

; Carry clear = valid; carry set = invalid.
ASTRO_RTC_READ:
ARR_RETRY:
        IN A,(RTC_SEC_1)
        AND $0F
        LD (AST_TMP0),A

        ; Read full seconds as well.  AST_TMP0 remains the units digit
        ; used for the second-boundary consistency check below.
        LD B,A
        IN A,(RTC_SEC_10)
        AND $0F
        CALL ASTRO_BCD_PAIR_B
        LD (AST_SECOND),A

        IN A,(RTC_MIN_1)
        AND $0F
        LD B,A
        IN A,(RTC_MIN_10)
        AND $0F
        CALL ASTRO_BCD_PAIR_B
        LD (AST_MINUTE),A

        IN A,(RTC_HOUR_1)
        AND $0F
        LD B,A
        IN A,(RTC_HOUR_10)
        AND $03
        CALL ASTRO_BCD_PAIR_B
        LD (AST_HOUR),A

        IN A,(RTC_DAY_1)
        AND $0F
        LD B,A
        IN A,(RTC_DAY_10)
        AND $0F
        CALL ASTRO_BCD_PAIR_B
        LD (AST_DAY),A

        IN A,(RTC_MONTH_1)
        AND $0F
        LD B,A
        IN A,(RTC_MONTH_10)
        AND $0F
        CALL ASTRO_BCD_PAIR_B
        LD (AST_MONTH),A

        IN A,(RTC_YEAR_1)
        AND $0F
        LD B,A
        IN A,(RTC_YEAR_10)
        AND $0F
        CALL ASTRO_BCD_PAIR_B
        LD (AST_YEAR),A

        ; Ensure we did not cross a second boundary during the read.
        IN A,(RTC_SEC_1)
        AND $0F
        LD B,A
        LD A,(AST_TMP0)
        CP B
        JR NZ,ARR_RETRY

        ; Range validation.
        LD A,(AST_MINUTE)
        CP 60
        JR NC,ARR_BAD
        LD A,(AST_HOUR)
        CP 24
        JR NC,ARR_BAD
        LD A,(AST_MONTH)
        OR A
        JR Z,ARR_BAD
        CP 13
        JR NC,ARR_BAD
        LD A,(AST_DAY)
        OR A
        JR Z,ARR_BAD
        CP 32
        JR NC,ARR_BAD

        ; Treat 01/01/00 as an uninitialized/default RTC value.
        ; This forces manual MMDDYY / HHMM entry at startup instead of
        ; silently calculating astronomy for January 1, 2000.
        LD A,(AST_YEAR)
        OR A
        JR NZ,ARR_CHECK_MONTHLEN
        LD A,(AST_MONTH)
        CP 1
        JR NZ,ARR_CHECK_MONTHLEN
        LD A,(AST_DAY)
        CP 1
        JR Z,ARR_BAD

ARR_CHECK_MONTHLEN:
        ; Check actual month length.
        CALL ASTRO_DAYS_IN_MONTH
        LD B,A
        LD A,(AST_DAY)
        CP B
        JR Z,ARR_GOOD
        JR C,ARR_GOOD
ARR_BAD:
        SCF
        RET
ARR_GOOD:
        OR A
        RET

; Input: B=units digit, A=tens digit. Output A=0..99.
ASTRO_BCD_PAIR_B:
        LD C,A
        ADD A,A
        ADD A,A
        ADD A,C                   ; 5*tens
        ADD A,A                   ; 10*tens
        ADD A,B
        RET

ASTRO_MANUAL_CLOCK:
        XOR A
        LD (AST_INPUT_MODE),A       ; date
        LD HL,MSG_DATE
        LD B,6
        CALL ASTRO_READ_FIXED
        ; MM DD YY
        LD HL,AST_INPUT
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_MONTH),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_DAY),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_YEAR),A

        ; Validate manual month/day before proceeding.
        LD A,(AST_MONTH)
        OR A
        JR Z,ASTRO_MANUAL_CLOCK
        CP 13
        JR NC,ASTRO_MANUAL_CLOCK
        LD A,(AST_DAY)
        OR A
        JR Z,ASTRO_MANUAL_CLOCK
        CALL ASTRO_DAYS_IN_MONTH
        LD B,A
        LD A,(AST_DAY)
        CP B
        JR Z,AMC_TIME
        JR C,AMC_TIME
        JR ASTRO_MANUAL_CLOCK

AMC_TIME:
        LD A,1
        LD (AST_INPUT_MODE),A       ; time
        LD HL,MSG_TIME
        LD B,6
        CALL ASTRO_READ_FIXED
        LD HL,AST_INPUT
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_HOUR),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_MINUTE),A
        INC HL
        LD A,(HL)
        INC HL
        LD B,(HL)
        CALL ASTRO_2DIG_AB
        LD (AST_SECOND),A

        ; Validate; if bad, ask again.
        LD A,(AST_HOUR)
        CP 24
        JR NC,AMC_TIME
        LD A,(AST_MINUTE)
        CP 60
        JR NC,AMC_TIME
        LD A,(AST_SECOND)
        CP 60
        JR NC,AMC_TIME

        LD A,1
        LD (AST_CLOCK_OK),A
        RET

; A=tens digit, B=ones digit -> A=value.
ASTRO_2DIG_AB:
        LD C,A
        ADD A,A
        ADD A,A
        ADD A,C
        ADD A,A
        ADD A,B
        RET

; HL=prompt, B=required digit count. Stores numeric digits in AST_INPUT.
; BACKSPACE works. ENTER accepted only at exact count.
;
; V1F presentation:
;   DATE MM/DD/YY
;   TIME HH:MM:SS
;
; The user types digits only. '/' and ':' are fixed display characters.
; Typed digits replace only M/D/Y or H/M/S positions.
ASTRO_READ_FIXED:
        LD A,B
        LD (AST_TMP6),A
        XOR A
        LD (AST_INCOUNT),A

ARF_REDRAW:
        CALL DISPLAY_CLEAR

        ; Both DATE and TIME contain six numeric digits, so use an explicit
        ; persistent mode byte rather than relying on HL surviving redraws.
        LD A,(AST_INPUT_MODE)
        OR A
        JR NZ,ARF_TIME_FORMAT

        LD HL,MSG_DATE_PREFIX
        CALL DISPLAY_PRINT_Z
        LD HL,MSG_DATE_MASK
        LD B,8                    ; MM/DD/YY = 8 display positions
        JR ARF_FORMAT_READY

ARF_TIME_FORMAT:
        LD HL,MSG_TIME_PREFIX
        CALL DISPLAY_PRINT_Z
        LD HL,MSG_TIME_MASK
        LD B,8                    ; HH:MM:SS = 8 display positions

ARF_FORMAT_READY:
        LD DE,AST_INPUT
        LD A,(AST_INCOUNT)
        LD (AST_TMP5),A           ; number of entered digits still to render

ARF_SHOW_FIELD:
        LD A,(HL)

        ; Separators are literal and do not consume an entered digit.
        CP '/'
        JR Z,ARF_LITERAL
        CP ':'
        JR Z,ARF_LITERAL

        ; Placeholder position. If a digit has been entered, display it;
        ; otherwise leave the template character (M/D/Y/H/M/S).
        LD A,(AST_TMP5)
        OR A
        JR Z,ARF_SHOW_MASK

        LD A,(DE)
        ADD A,'0'
        INC DE
        PUSH BC
        PUSH DE
        PUSH HL
        CALL DISPLAY_PUT_ASCII
        POP HL
        POP DE
        POP BC
        LD A,(AST_TMP5)
        DEC A
        LD (AST_TMP5),A
        JR ARF_NEXT_FIELD

ARF_SHOW_MASK:
        LD A,(HL)
        JR ARF_PUT_LITERAL

ARF_LITERAL:
        LD A,(HL)

ARF_PUT_LITERAL:
        PUSH BC
        PUSH DE
        PUSH HL
        CALL DISPLAY_PUT_ASCII
        POP HL
        POP DE
        POP BC

ARF_NEXT_FIELD:
        INC HL
        DJNZ ARF_SHOW_FIELD

ARF_KEY:
        CALL KEY_GET
        CP KEY_BACKSPACE
        JR Z,ARF_BS
        CP KEY_ENTER
        JR Z,ARF_ENTER
        CALL KEYCODE_TO_DIGIT
        JR C,ARF_KEY

        LD C,A
        LD A,(AST_INCOUNT)
        LD B,A
        LD A,(AST_TMP6)
        CP B
        JR Z,ARF_KEY

        LD E,B
        LD D,0
        PUSH HL
        LD HL,AST_INPUT
        ADD HL,DE
        LD (HL),C
        POP HL
        LD A,B
        INC A
        LD (AST_INCOUNT),A
        JP ARF_REDRAW

ARF_BS:
        LD A,(AST_INCOUNT)
        OR A
        JR Z,ARF_KEY
        DEC A
        LD (AST_INCOUNT),A
        JP ARF_REDRAW

ARF_ENTER:
        LD A,(AST_INCOUNT)
        LD B,A
        LD A,(AST_TMP6)
        CP B
        JR NZ,ARF_KEY
        RET

; ============================================================================
; CALENDAR
; ============================================================================

; AST_DAYS = days since 1999-12-31.
; Valid for 2000..2099.  Leap year is simply YY divisible by 4.
ASTRO_DAY_NUMBER:
        LD HL,0
        LD A,(AST_YEAR)
        LD B,A
        LD C,0
ADN_YEAR_LOOP:
        LD A,C
        CP B
        JR Z,ADN_MONTHS
        LD DE,365
        ADD HL,DE
        LD A,C
        AND 3
        JR NZ,ADN_NOT_LEAP_YEAR
        INC HL
ADN_NOT_LEAP_YEAR:
        INC C
        JR ADN_YEAR_LOOP

ADN_MONTHS:
        LD A,(AST_MONTH)
        DEC A
        LD B,A
        LD C,1
ADN_MONTH_LOOP:
        LD A,B
        OR A
        JR Z,ADN_ADD_DAY
        PUSH HL
        LD A,C
        LD (AST_TMP0),A
        CALL ASTRO_DAYS_IN_MONTH_A
        LD E,A
        LD D,0
        POP HL
        ADD HL,DE
        INC C
        DEC B
        JR ADN_MONTH_LOOP

ADN_ADD_DAY:
        LD A,(AST_DAY)
        LD E,A
        LD D,0
        ADD HL,DE                 ; Jan 1 2000 = day 1
        LD (AST_DAYS),HL
        RET

; Returns days in current AST_MONTH, considering AST_YEAR.
ASTRO_DAYS_IN_MONTH:
        LD A,(AST_MONTH)
ASTRO_DAYS_IN_MONTH_A:
        CP 2
        JR Z,ADIM_FEB
        CP 4
        JR Z,ADIM_30
        CP 6
        JR Z,ADIM_30
        CP 9
        JR Z,ADIM_30
        CP 11
        JR Z,ADIM_30
        LD A,31
        RET
ADIM_30:
        LD A,30
        RET
ADIM_FEB:
        LD A,(AST_YEAR)
        AND 3
        LD A,28
        RET NZ
        INC A
        RET

; ============================================================================
; ORBITAL ELEMENT EVOLUTION
;
; The base epoch is 1999-12-31 00:00 UT ("day 0").
; Fractional tenths are carried at scale 10000.
; This intentionally uses one compact daily loop instead of general
; 32-bit floating-point or polynomial arithmetic.
; ============================================================================

ASTRO_EVOLVE_ELEMENTS:
        LD HL,3560
        LD (AST_SM),HL
        LD HL,4700
        LD (AST_SMF),HL

        LD HL,2829
        LD (AST_SW),HL
        LD HL,4040
        LD (AST_SWF),HL

        LD HL,1004
        LD (AST_JN),HL
        LD HL,5420
        LD (AST_JNF),HL

        LD HL,2738
        LD (AST_JW),HL
        LD HL,7770
        LD (AST_JWF),HL

        LD HL,198
        LD (AST_JM),HL
        LD HL,9500
        LD (AST_JMF),HL

        LD HL,3169
        LD (AST_SATM),HL
        LD HL,6700
        LD (AST_SATMF),HL

        LD BC,(AST_DAYS)
AEE_DAY_LOOP:
        LD A,B
        OR C
        JR Z,AEE_DONE

        ; Sun M += 9.8560 tenth/day
        LD HL,(AST_SM)
        LD DE,9
        ADD HL,DE
        LD (AST_SM),HL
        LD HL,(AST_SMF)
        LD DE,8560
        ADD HL,DE
        CALL ASTRO_FRAC10000_SM

        ; Sun w += 0.0005 tenth/day
        LD HL,(AST_SWF)
        LD DE,5
        ADD HL,DE
        LD (AST_SWF),HL
        CALL ASTRO_FRAC10000_SW

        ; Jupiter N += 0.0003 tenth/day
        LD HL,(AST_JNF)
        LD DE,3
        ADD HL,DE
        LD (AST_JNF),HL
        CALL ASTRO_FRAC10000_JN

        ; Jupiter w += 0.0002 tenth/day
        LD HL,(AST_JWF)
        LD DE,2
        ADD HL,DE
        LD (AST_JWF),HL
        CALL ASTRO_FRAC10000_JW

        ; Jupiter M += 0.8309 tenth/day
        LD HL,(AST_JMF)
        LD DE,8309
        ADD HL,DE
        LD (AST_JMF),HL
        CALL ASTRO_FRAC10000_JM

        ; Saturn M += 0.3344 tenth/day
        LD HL,(AST_SATMF)
        LD DE,3344
        ADD HL,DE
        LD (AST_SATMF),HL
        CALL ASTRO_FRAC10000_SATM

        DEC BC
        JR AEE_DAY_LOOP
AEE_DONE:
        RET

; Each helper: if fraction >=10000, subtract it and increment angle.
; Then normalize angle if >=3600.
ASTRO_FRAC10000_SM:
        LD HL,(AST_SMF)
        CALL ASTRO_FRAC_TEST
        LD (AST_SMF),HL
        RET C
        LD HL,(AST_SM)
        INC HL
        CALL ASTRO_NORM3600
        LD (AST_SM),HL
        RET
ASTRO_FRAC10000_SW:
        LD HL,(AST_SWF)
        CALL ASTRO_FRAC_TEST
        LD (AST_SWF),HL
        RET C
        LD HL,(AST_SW)
        INC HL
        CALL ASTRO_NORM3600
        LD (AST_SW),HL
        RET
ASTRO_FRAC10000_JN:
        LD HL,(AST_JNF)
        CALL ASTRO_FRAC_TEST
        LD (AST_JNF),HL
        RET C
        LD HL,(AST_JN)
        INC HL
        CALL ASTRO_NORM3600
        LD (AST_JN),HL
        RET
ASTRO_FRAC10000_JW:
        LD HL,(AST_JWF)
        CALL ASTRO_FRAC_TEST
        LD (AST_JWF),HL
        RET C
        LD HL,(AST_JW)
        INC HL
        CALL ASTRO_NORM3600
        LD (AST_JW),HL
        RET
ASTRO_FRAC10000_JM:
        LD HL,(AST_JMF)
        CALL ASTRO_FRAC_TEST
        LD (AST_JMF),HL
        RET C
        LD HL,(AST_JM)
        INC HL
        CALL ASTRO_NORM3600
        LD (AST_JM),HL
        RET
ASTRO_FRAC10000_SATM:
        LD HL,(AST_SATMF)
        CALL ASTRO_FRAC_TEST
        LD (AST_SATMF),HL
        RET C
        LD HL,(AST_SATM)
        INC HL
        CALL ASTRO_NORM3600
        LD (AST_SATM),HL
        RET

; HL=fraction.  Carry set = still <10000.
; Carry clear = 10000 removed.
ASTRO_FRAC_TEST:
        LD DE,10000
        OR A
        SBC HL,DE
        JR NC,AFT_OVER
        ADD HL,DE
        SCF
        RET
AFT_OVER:
        OR A
        RET

; Normalize unsigned angle HL into 0..3599.
ASTRO_NORM3600:
AN3_LOOP:
        LD DE,3600
        OR A
        SBC HL,DE
        JR NC,AN3_LOOP
        ADD HL,DE
        RET

; Normalize signed-ish HL by repeated +/-3600.
ASTRO_NORM3600_SIGNED:
        BIT 7,H
        JR Z,ANS_POS
ANS_NEG:
        LD DE,3600
        ADD HL,DE
        BIT 7,H
        JR NZ,ANS_NEG
ANS_POS:
        JP ASTRO_NORM3600

; ============================================================================
; PLANET VECTOR
; ============================================================================

; Input: HL = UTC minutes 0..1439 for this AST_DAYS date.
; Output: AST_X/Y/Z equatorial geocentric vector.
;
; Fractional-day correction is intentionally applied only to mean anomalies;
; all other element rates are negligible over one day at this resolution.
ASTRO_VECTOR:
        LD (AST_TMP7),HL           ; UTC minutes

        ; ----- Sun mean anomaly fractional day -----
        ; correction = round(minutes * 9.856 / 1440), 0..10 tenths.
        ; We use a compact hour lookup: index = minutes/60, 0..23.
        CALL ASTRO_MINUTES_TO_HOUR
        LD E,A
        LD D,0
        LD HL,SUN_HOUR_CORR
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD D,0
        LD HL,(AST_SM)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (AST_TMP0),HL           ; Sun M now

        ; Sun E ~= M + 10*sin(M)
        PUSH HL
        CALL ASTRO_SIN10
        LD A,10
        CALL ASTRO_SCALE_Q15_U8
        EX DE,HL                   ; DE=correction
        POP HL
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (AST_TMP1),HL           ; Sun E

        ; sxv = 4096*cos(E) - 68
        CALL ASTRO_COS10
        LD DE,SUN_A_Q
        EX DE,HL                   ; HL=4096, DE=cos
        CALL ASTRO_MUL_Q15
        LD DE,SUN_AE_Q
        OR A
        SBC HL,DE
        LD (AST_TMP2),HL           ; sxv

        ; syv = 4095*sin(E)
        LD HL,(AST_TMP1)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,SUN_B_Q
        CALL ASTRO_MUL_Q15
        LD (AST_TMP3),HL           ; syv

        ; Rotate by Sun w -> geocentric Sun ecliptic xs,ys
        LD HL,(AST_SW)
        CALL ASTRO_COS10
        LD (AST_TMP4),HL           ; cos w
        LD HL,(AST_SW)
        CALL ASTRO_SIN10
        LD (AST_TMP5),HL           ; sin w

        LD HL,(AST_TMP2)
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP6),HL
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP6)
        OR A
        SBC HL,DE
        LD (AST_X),HL              ; temporarily xs

        LD HL,(AST_TMP2)
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP6),HL
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP6)
        ADD HL,DE
        LD (AST_Y),HL              ; temporarily ys

        ; ----- Jupiter mean anomaly fractional day -----
        LD HL,(AST_TMP7)
        CALL ASTRO_MINUTES_TO_HOUR
        LD E,A
        LD D,0
        LD HL,JUP_HOUR_CORR
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD D,0
        LD HL,(AST_JM)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (AST_TMP0),HL           ; Jupiter M

        ; Save Saturn M with tiny hour correction.
        LD HL,(AST_TMP7)
        CALL ASTRO_MINUTES_TO_HOUR
        LD E,A
        LD D,0
        LD HL,SAT_HOUR_CORR
        ADD HL,DE
        LD A,(HL)
        LD E,A
        LD D,0
        LD HL,(AST_SATM)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (AST_Z),HL              ; temporary Saturn M angle

        ; Jupiter E ~= M + 28*sin(M) + 1*sin(2M)
        LD HL,(AST_TMP0)
        PUSH HL
        CALL ASTRO_SIN10
        LD A,28
        CALL ASTRO_SCALE_Q15_U8
        LD (AST_TMP1),HL
        POP HL
        ADD HL,HL
        CALL ASTRO_NORM3600
        CALL ASTRO_SIN10
        LD A,1
        CALL ASTRO_SCALE_Q15_U8
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE
        EX DE,HL                   ; DE=all corrections
        LD HL,(AST_TMP0)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (AST_TMP1),HL           ; Jupiter E

        ; jxv = 21310*cos(E)-1033
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,JUP_A_Q
        CALL ASTRO_MUL_Q15
        LD DE,JUP_AE_Q
        OR A
        SBC HL,DE
        LD (AST_TMP2),HL           ; jxv

        ; jyv = 21285*sin(E)
        LD HL,(AST_TMP1)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,JUP_B_Q
        CALL ASTRO_MUL_Q15
        LD (AST_TMP3),HL           ; jyv

        ; x1 = jxv*cos(w) - jyv*sin(w)
        LD HL,(AST_JW)
        CALL ASTRO_COS10
        LD (AST_TMP4),HL
        LD HL,(AST_JW)
        CALL ASTRO_SIN10
        LD (AST_TMP5),HL

        LD HL,(AST_TMP2)
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP6),HL
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP6)
        OR A
        SBC HL,DE
        LD (AST_TMP2),HL           ; x1

        ; y1 = jxv*sin(w) + jyv*cos(w)
        LD HL,(AST_TMP3)           ; jyv
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP6),HL
        ; recover jxv: x1 no longer contains it, recompute from E
        LD HL,(AST_TMP1)
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,JUP_A_Q
        CALL ASTRO_MUL_Q15
        LD DE,JUP_AE_Q
        OR A
        SBC HL,DE
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP6)
        ADD HL,DE
        LD (AST_TMP3),HL           ; y1

        ; Node trig.
        LD HL,(AST_JN)
        CALL ASTRO_COS10
        LD (AST_TMP4),HL
        LD HL,(AST_JN)
        CALL ASTRO_SIN10
        LD (AST_TMP5),HL

        ; i is ~1.3 deg -> use table angle 13.
        LD HL,13
        CALL ASTRO_COS10
        LD (AST_TMP6),HL           ; cos i
        LD HL,13
        CALL ASTRO_SIN10
        LD (AST_TMP7),HL           ; sin i

        ; xh = x1*cosN - y1*cosi*sinN
        LD HL,(AST_TMP2)
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP1),HL
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP6)
        CALL ASTRO_MUL_Q15
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        OR A
        SBC HL,DE
        LD (AST_TMP1),HL           ; xh

        ; yh = x1*sinN + y1*cosi*cosN
        LD HL,(AST_TMP2)
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP0),HL
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP6)
        CALL ASTRO_MUL_Q15
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP0)
        ADD HL,DE
        LD (AST_TMP0),HL           ; yh

        ; zh = y1*sin i
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP7)
        CALL ASTRO_MUL_Q15
        LD (AST_Z),HL              ; zh; preserve across perturbation scratch

        ; Apply Jupiter/Saturn longitude perturbation.
        ; Returns HL = signed perturbation in tenths degree.
        CALL ASTRO_JUP_PERTURB
        CALL ASTRO_ROTATE_PERTURB_SAFE

        ; Geocentric ecliptic = Jupiter heliocentric + Sun geocentric.
        LD HL,(AST_X)              ; xs
        LD DE,(AST_TMP1)           ; xh
        ADD HL,DE
        LD (AST_TMP1),HL           ; xg
        LD HL,(AST_Y)              ; ys
        LD DE,(AST_TMP0)           ; yh
        ADD HL,DE
        LD (AST_TMP0),HL           ; yg
        ; zg = zh already preserved in AST_Z

        ; Ecliptic -> equatorial.
        LD HL,(AST_TMP1)
        LD (AST_X),HL

        LD HL,(AST_TMP0)
        LD DE,OBL_COS_Q15
        CALL ASTRO_MUL_Q15
        LD (AST_TMP4),HL
        LD HL,(AST_Z)
        LD DE,OBL_SIN_Q15
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP4)
        OR A
        SBC HL,DE
        LD (AST_Y),HL

        LD HL,(AST_TMP0)
        LD DE,OBL_SIN_Q15
        CALL ASTRO_MUL_Q15
        LD (AST_TMP4),HL
        LD HL,(AST_Z)
        LD DE,OBL_COS_Q15
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP4)
        ADD HL,DE
        LD (AST_Z),HL
        RET

; ----------------------------------------------------------------------------
; Safe perturbation implementation.
;
; NOTE FOR INTEGRATION:
; The vector routine above is intentionally verbose for educational visibility.
; The actual callable perturbation used by the corrected block below stores the
; original xh/yh before rotation.  Replace the marked perturbation block in
; ASTRO_VECTOR with ASTRO_ROTATE_PERTURB_SAFE when merging.
; ----------------------------------------------------------------------------
ASTRO_ROTATE_PERTURB_SAFE:
        ; Input:
        ;   AST_TMP1 = xh
        ;   AST_TMP0 = yh
        ;   HL       = signed p10
        ; Output:
        ;   AST_TMP1 = rotated xh
        ;   AST_TMP0 = rotated yh
        LD (AST_TMP7),HL
        LD HL,(AST_TMP1)
        LD (AST_TMP2),HL          ; old xh
        LD HL,(AST_TMP0)
        LD (AST_TMP3),HL          ; old yh

        LD HL,(AST_TMP7)
        CALL ASTRO_COS10_SIGNED
        LD (AST_TMP4),HL
        LD HL,(AST_TMP7)
        CALL ASTRO_SIN10_SIGNED
        LD (AST_TMP5),HL

        LD HL,(AST_TMP2)
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP6),HL
        LD HL,(AST_TMP3)
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP6)
        OR A
        SBC HL,DE
        LD (AST_TMP1),HL

        LD HL,(AST_TMP3)
        LD DE,(AST_TMP4)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP6),HL
        LD HL,(AST_TMP2)
        LD DE,(AST_TMP5)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP6)
        ADD HL,DE
        LD (AST_TMP0),HL
        RET

; ----------------------------------------------------------------------------
; Jupiter longitude perturbation.
; Returns signed HL in tenths degree.
; Uses the standard Jupiter/Saturn short-period terms, coefficients in
; hundredths of a degree, then divides the sum by 10.
; ----------------------------------------------------------------------------
ASTRO_JUP_PERTURB:
        XOR A
        LD H,A
        LD L,A
        LD (AST_TMP6),HL          ; sum hundredths deg
        LD HL,(AST_JM)
        ADD HL,HL
        LD DE,(AST_SATM)
        CALL ASTRO_SUB_5DE
        LD DE,-676
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_SIN10
        LD A,33
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_NEG_HL
        LD (AST_TMP6),HL

        ; -6 sin(2Mj - 2Ms + 21.0)
        LD HL,(AST_JM)
        ADD HL,HL
        LD DE,(AST_SATM)
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        LD DE,210
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_SIN10
        LD A,6
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_NEG_HL
        CALL ASTRO_ADD_PSUM

        ; +4 sin(3Mj - 5Ms + 21.0)
        LD HL,(AST_JM)
        PUSH HL
        ADD HL,HL
        POP DE
        ADD HL,DE
        LD DE,(AST_SATM)
        CALL ASTRO_SUB_5DE
        LD DE,210
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_SIN10
        LD A,4
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_ADD_PSUM

        ; -4 sin(Mj - 2Ms)
        LD HL,(AST_JM)
        LD DE,(AST_SATM)
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_SIN10
        LD A,4
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_NEG_HL
        CALL ASTRO_ADD_PSUM

        ; +2 cos(Mj - Ms)
        LD HL,(AST_JM)
        LD DE,(AST_SATM)
        OR A
        SBC HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_COS10
        LD A,2
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_ADD_PSUM

        ; +2 sin(2Mj - 3Ms + 52.0)
        LD HL,(AST_JM)
        ADD HL,HL
        LD DE,(AST_SATM)
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        LD DE,520
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_SIN10
        LD A,2
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_ADD_PSUM

        ; -2 sin(Mj - 5Ms - 69.0)
        LD HL,(AST_JM)
        LD DE,(AST_SATM)
        CALL ASTRO_SUB_5DE
        LD DE,-690
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        CALL ASTRO_SIN10
        LD A,2
        CALL ASTRO_SCALE_Q15_U8
        CALL ASTRO_NEG_HL
        CALL ASTRO_ADD_PSUM

        LD HL,(AST_TMP6)
        CALL ASTRO_DIVS10
        RET

; HL -= 5*DE.
ASTRO_SUB_5DE:
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        OR A
        SBC HL,DE
        RET

ASTRO_ADD_PSUM:
        EX DE,HL
        LD HL,(AST_TMP6)
        ADD HL,DE
        LD (AST_TMP6),HL
        RET

; Signed HL / 10, truncating toward zero.
ASTRO_DIVS10:
        BIT 7,H
        JR Z,ADS10_POS
        CALL ASTRO_NEG_HL
        CALL ASTRO_DIVU10
        JP ASTRO_NEG_HL
ADS10_POS:
        JP ASTRO_DIVU10

ASTRO_DIVU10:
        ; PURE Z80 FAST unsigned HL / 10. Exact 16-step binary division.
        ; Quotient returned in HL; remainder discarded.
        LD DE,0                    ; quotient
        LD BC,0                    ; remainder (0..9)
        LD A,16
ADU10_FAST_LOOP:
        ADD HL,HL                  ; next dividend bit -> carry
        RL C                       ; remainder = remainder*2 + bit
        RL B
        SLA E                      ; quotient <<= 1
        RL D
        PUSH HL
        LD H,B
        LD L,C
        PUSH DE
        LD DE,10
        OR A
        SBC HL,DE
        POP DE
        JR C,ADU10_FAST_NOSUB
        LD B,H
        LD C,L
        INC E                      ; set quotient bit 0
ADU10_FAST_NOSUB:
        POP HL
        DEC A
        JR NZ,ADU10_FAST_LOOP
        EX DE,HL
        RET

; ============================================================================
; RISE / SET
; ============================================================================

ASTRO_RISE_SET:
        LD HL,$FFFF
        LD (AST_RISE),HL
        LD (AST_SET),HL

        ; Planet vector at local noon using runtime UTC offset.
        LD HL,720
        CALL G_LOCAL_TO_UTC_MIN
        CALL ASTRO_VECTOR

        ; Distance r = sqrt(x^2+y^2+z^2).
        CALL ASTRO_VECTOR_DISTANCE
        LD (AST_DIST_Q),HL

        ; horizon coordinate threshold = r * sin(-0.5667)
        LD DE,H0_SIN_Q15
        CALL ASTRO_MUL_Q15
        LD (AST_HORIZON_Q),HL

        ; LST at local 00:00 = GMST0 + longitude + runtime UTC-offset advance.
        CALL ASTRO_GMST0
        LD DE,(G_SITE_LON10)
        ADD HL,DE
        PUSH HL                  ; preserve GMST0+longitude across SID_ADV
        LD HL,0
        CALL G_LOCAL_TO_UTC_MIN   ; UTC minute corresponding to local midnight
        CALL ASTRO_SID_ADV10
        POP DE
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (AST_LST0),HL

        ; state at minute 0
        LD HL,0
        CALL ASTRO_UP_AT_LOCAL_MIN
        CALL ASTRO_ABOVE_HORIZON
        LD (AST_PREV),A

        LD HL,1
        LD (AST_SCAN_MIN),HL

ARS_LOOP:
        LD HL,(AST_SCAN_MIN)
        CALL ASTRO_UP_AT_LOCAL_MIN
        CALL ASTRO_ABOVE_HORIZON
        LD D,A                    ; current state
        LD A,(AST_PREV)
        CP D
        JR Z,ARS_NEXT

        OR A
        JR NZ,ARS_WAS_ABOVE
        ; below -> above = rise
        LD HL,(AST_RISE)
        LD A,H
        CP $FF
        JR NZ,ARS_STORE_STATE
        LD A,L
        CP $FF
        JR NZ,ARS_STORE_STATE
        LD HL,(AST_SCAN_MIN)
        LD (AST_RISE),HL
        JR ARS_STORE_STATE

ARS_WAS_ABOVE:
        ; above -> below = set
        LD HL,(AST_SET)
        LD A,H
        CP $FF
        JR NZ,ARS_STORE_STATE
        LD A,L
        CP $FF
        JR NZ,ARS_STORE_STATE
        LD HL,(AST_SCAN_MIN)
        LD (AST_SET),HL

ARS_STORE_STATE:
        LD A,D
        LD (AST_PREV),A

ARS_NEXT:
        LD HL,(AST_SCAN_MIN)
        INC HL
        LD (AST_SCAN_MIN),HL
        LD DE,1440
        OR A
        SBC HL,DE
        JR C,ARS_LOOP
        RET

; HL=local minute.  Returns signed HL=UP coordinate.
ASTRO_UP_AT_LOCAL_MIN:
        PUSH HL
        CALL ASTRO_SID_ADV10
        EX DE,HL
        LD HL,(AST_LST0)
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (AST_TMP0),HL          ; LST

        ; q = x*cosLST + y*sinLST
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_X)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP1),HL

        LD HL,(AST_TMP0)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_Y)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE                 ; q
        LD (AST_Q),HL

        ; up = q*coslat + z*sinlat
        LD DE,(G_SITE_LAT_COS_Q15)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP1),HL
        LD HL,(AST_Z)
        LD DE,(G_SITE_LAT_SIN_Q15)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE
        POP DE                    ; discard saved minute into DE
        RET

; Input HL=signed up. Output A=1 if >= threshold else 0.
ASTRO_ABOVE_HORIZON:
        LD DE,(AST_HORIZON_Q)
        ; signed compare HL >= DE via biasing sign bit
        LD A,H
        XOR $80
        LD B,A
        LD A,D
        XOR $80
        CP B
        JR C,AAH_YES              ; biased DE < biased HL
        JR NZ,AAH_NO
        LD A,E
        CP L
        JR C,AAH_YES
        JR Z,AAH_YES
AAH_NO:
        XOR A
        RET
AAH_YES:
        LD A,1
        RET

; ============================================================================
; CURRENT AZIMUTH / ELEVATION
; ============================================================================

ASTRO_CURRENT_HORIZONTAL:
        ; Local minute
        LD A,(AST_HOUR)
        LD H,0
        LD L,A
        ; *60 = *64 - *4
        PUSH HL
        ADD HL,HL
        ADD HL,HL                 ; *4
        EX DE,HL
        POP HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL                 ; *64
        OR A
        SBC HL,DE                 ; *60
        LD A,(AST_MINUTE)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (AST_LOCAL_MIN),HL     ; preserve across ASTRO_VECTOR

        ; Convert local minute using runtime UTC offset. If >=1440 use next UTC day.
        CALL G_LOCAL_TO_UTC_MIN
        LD DE,1440
        OR A
        SBC HL,DE
        JR C,ACH_SAME_DAY

        ; next UTC date.  Temporarily evolve elements one extra day.
        ADD HL,DE                 ; restore utc total
        OR A
        SBC HL,DE                 ; HL = utc minute -1440
        PUSH HL
        CALL ASTRO_ELEMENTS_PLUS_ONE_DAY
        POP HL
        CALL ASTRO_VECTOR
        CALL ASTRO_ELEMENTS_MINUS_ONE_DAY
        JR ACH_LST

ACH_SAME_DAY:
        ADD HL,DE                 ; restore same-day UTC minute
        CALL ASTRO_VECTOR

ACH_LST:
        ; LST can be obtained directly from local-midnight base.
        CALL ASTRO_GMST0
        LD DE,(G_SITE_LON10)
        ADD HL,DE
        PUSH HL                  ; preserve GMST0+longitude across SID_ADV
        LD HL,0
        CALL G_LOCAL_TO_UTC_MIN   ; UTC minute corresponding to local midnight
        CALL ASTRO_SID_ADV10
        POP DE
        ADD HL,DE
        LD (AST_LST0),HL

        LD HL,(AST_LOCAL_MIN)
        CALL ASTRO_SID_ADV10
        EX DE,HL
        LD HL,(AST_LST0)
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (AST_TMP0),HL          ; current LST

        ; q = x*cosLST + y*sinLST
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_X)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP1),HL

        LD HL,(AST_TMP0)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_Y)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE
        LD (AST_Q),HL

        ; east = -x*sinLST + y*cosLST
        LD HL,(AST_TMP0)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_X)
        CALL ASTRO_MUL_Q15
        CALL ASTRO_NEG_HL
        LD (AST_TMP1),HL
        LD HL,(AST_TMP0)
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_Y)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE
        LD (AST_EAST),HL

        ; north = -q*sinlat + z*coslat
        LD HL,(AST_Q)
        LD DE,(G_SITE_LAT_SIN_Q15)
        CALL ASTRO_MUL_Q15
        CALL ASTRO_NEG_HL
        LD (AST_TMP1),HL
        LD HL,(AST_Z)
        LD DE,(G_SITE_LAT_COS_Q15)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE
        LD (AST_NORTH),HL

        ; up = q*coslat + z*sinlat
        LD HL,(AST_Q)
        LD DE,(G_SITE_LAT_COS_Q15)
        CALL ASTRO_MUL_Q15
        LD (AST_TMP1),HL
        LD HL,(AST_Z)
        LD DE,(G_SITE_LAT_SIN_Q15)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(AST_TMP1)
        ADD HL,DE
        LD (AST_UP),HL

        ; VIS based on same -0.5667-degree apparent horizon.
        CALL ASTRO_VECTOR_DISTANCE
        LD DE,H0_SIN_Q15
        CALL ASTRO_MUL_Q15
        LD (AST_HORIZON_Q),HL
        LD HL,(AST_UP)
        CALL ASTRO_ABOVE_HORIZON
        LD (AST_VISIBLE),A

        ; az = atan2(east,north)
        LD HL,(AST_EAST)
        LD DE,(AST_NORTH)
        CALL ASTRO_ATAN2_10
        LD (AST_AZ10),HL

        ; horizontal magnitude = sqrt(east^2+north^2)
        LD HL,(AST_EAST)
        CALL ASTRO_SQUARE16
        CALL ASTRO_COPY_ACC_TO_N
        LD HL,(AST_NORTH)
        CALL ASTRO_SQUARE16
        CALL ASTRO_ADD_ACC_TO_N
        CALL ASTRO_ISQRT32
        LD (AST_HOR),HL

        ; elevation = atan2(up,horizontal)
        LD HL,(AST_UP)
        LD DE,(AST_HOR)
        CALL ASTRO_ATAN2_SIGNED90
        LD (AST_EL10),HL
        RET

; ----------------------------------------------------------------------------
; One-day temporary element adjustment for local evening -> next UTC date.
; Accuracy need only match the daily element recurrence.
; ----------------------------------------------------------------------------
ASTRO_ELEMENTS_PLUS_ONE_DAY:
        ; Rather than duplicate every fractional accumulator mutation here,
        ; advance AST_DAYS and rebuild. This path occurs at most once per
        ; option invocation and remains fast enough.
        LD HL,(AST_DAYS)
        INC HL
        LD (AST_DAYS),HL
        JP ASTRO_EVOLVE_ELEMENTS

ASTRO_ELEMENTS_MINUS_ONE_DAY:
        LD HL,(AST_DAYS)
        DEC HL
        LD (AST_DAYS),HL
        JP ASTRO_EVOLVE_ELEMENTS

; ============================================================================
; SIDEREAL TIME
; ============================================================================

; GMST0 in angle10 for AST_DAYS:
; Schlyter low-precision relation GMST0 = Sun M + Sun w + 180 deg.
ASTRO_GMST0:
        LD HL,(AST_SM)
        LD DE,(AST_SW)
        ADD HL,DE
        LD DE,1800
        ADD HL,DE
        JP ASTRO_NORM3600

; HL=minutes, returns angle10 = round(minutes * 2.50684).
; Integer approximation 2507/1000, maximum full-day error ~0.03 deg.
ASTRO_SID_ADV10:
        LD DE,2507
        CALL ASTRO_UMUL16          ; product in M32_ACC
        LD HL,1000
        CALL ASTRO_DIV32_BY_16
        RET                        ; quotient HL

; Returns A=integer UTC hour 0..23 from minutes HL.
ASTRO_MINUTES_TO_HOUR:
        LD B,0
AMTH_LOOP:
        LD DE,60
        OR A
        SBC HL,DE
        JR C,AMTH_DONE
        INC B
        JR AMTH_LOOP
AMTH_DONE:
        LD A,B
        RET

; ============================================================================
; TRIG TABLE
; ============================================================================

; HL angle10 unsigned/signed-ish. Returns signed Q15 in HL.
ASTRO_SIN10_SIGNED:
        CALL ASTRO_NORM3600_SIGNED
ASTRO_SIN10:
        CALL ASTRO_NORM3600
        ADD HL,HL
        LD DE,ASTRO_SIN_TABLE
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        RET

ASTRO_COS10_SIGNED:
        CALL ASTRO_NORM3600_SIGNED
ASTRO_COS10:
        LD DE,900
        ADD HL,DE
        CALL ASTRO_NORM3600
        JP ASTRO_SIN10

; HL=signed Q15, A=unsigned coefficient. Return signed HL=(HL*A)>>15.
ASTRO_SCALE_Q15_U8:
        LD E,A
        LD D,0
        JP ASTRO_MUL_Q15

; ============================================================================
; FIXED-POINT MULTIPLY
; ============================================================================

; Signed HL * signed DE >> 15 -> signed HL.
ASTRO_MUL_Q15:
        XOR A
        LD (M32_SIGN),A
        BIT 7,H
        JR Z,AMQ_XPOS
        CALL ASTRO_NEG_HL
        LD A,1
        LD (M32_SIGN),A
AMQ_XPOS:
        BIT 7,D
        JR Z,AMQ_YPOS
        EX DE,HL
        CALL ASTRO_NEG_HL
        EX DE,HL
        LD A,(M32_SIGN)
        XOR 1
        LD (M32_SIGN),A
AMQ_YPOS:
        CALL ASTRO_UMUL16

        ; product >> 15:
        ; low = bit7(P1) | (P2<<1)
        ; high = bit7(P2) | (P3<<1)
        LD A,(M32_ACC+1)
        RLCA
        AND 1
        LD L,A
        LD A,(M32_ACC+2)
        SLA A
        OR L
        LD L,A
        LD A,(M32_ACC+2)
        RLCA
        AND 1
        LD H,A
        LD A,(M32_ACC+3)
        SLA A
        OR H
        LD H,A

        LD A,(M32_SIGN)
        OR A
        RET Z
        JP ASTRO_NEG_HL

; Unsigned HL * DE -> 32-bit M32_ACC.
ASTRO_UMUL16:
        ; PURE Z80 FAST unsigned HL * DE -> 32-bit M32_ACC.
        ; Product is accumulated in HL:IX, avoiding four-byte RAM shifts and
        ; helper CALLs for every multiplier bit. No Z180 MLT is used.
        PUSH IX
        PUSH HL
        POP BC                     ; BC = multiplicand
        LD HL,0                    ; high product
        LD IX,0                    ; low product
        LD A,16
AUM16_FAST_LOOP:
        ADD IX,IX                  ; 32-bit product <<= 1
        ADC HL,HL
        BIT 7,D                    ; consume multiplier MSB first
        JR Z,AUM16_FAST_NOADD
        ADD IX,BC
        JR NC,AUM16_FAST_NOADD
        INC HL                     ; carry into high word
AUM16_FAST_NOADD:
        SLA E
        RL D
        DEC A
        JR NZ,AUM16_FAST_LOOP
        LD (M32_ACC),IX
        LD (M32_ACC+2),HL
        POP IX
        RET

ASTRO_ADD_MC_TO_ACC:
        LD A,(M32_ACC)
        LD C,A
        LD A,(M32_MC)
        ADD A,C
        LD (M32_ACC),A

        LD A,(M32_ACC+1)
        LD C,A
        LD A,(M32_MC+1)
        ADC A,C
        LD (M32_ACC+1),A

        LD A,(M32_ACC+2)
        LD C,A
        LD A,(M32_MC+2)
        ADC A,C
        LD (M32_ACC+2),A

        LD A,(M32_ACC+3)
        LD C,A
        LD A,(M32_MC+3)
        ADC A,C
        LD (M32_ACC+3),A
        RET

ASTRO_SHL_MC32:
        LD A,(M32_MC)
        SLA A
        LD (M32_MC),A
        LD A,(M32_MC+1)
        RL A
        LD (M32_MC+1),A
        LD A,(M32_MC+2)
        RL A
        LD (M32_MC+2),A
        LD A,(M32_MC+3)
        RL A
        LD (M32_MC+3),A
        RET

ASTRO_SHR_MR16:
        LD A,(M32_MR+1)
        SRL A
        LD (M32_MR+1),A
        LD A,(M32_MR)
        RR A
        LD (M32_MR),A
        RET

; ============================================================================
; 32-BIT DIVISION / SQUARE ROOT
; ============================================================================

; Divide unsigned 32-bit M32_ACC by unsigned HL.
; Returns 16-bit quotient HL.  Used where quotient is known to fit 16 bits.
ASTRO_DIV32_BY_16:
        ; PURE Z80 FAST exact 32/16 divide for the existing contract that the
        ; quotient fits in 16 bits.  In that case numerator high word < divisor,
        ; so seed the remainder with the high word and process only the low 16 bits.
        LD (AST_TMP0),HL           ; divisor
        LD DE,(M32_ACC+2)          ; initial remainder = numerator high word
        LD HL,(M32_ACC)            ; low numerator; becomes quotient in-place
        LD A,16
AD3216_FAST_LOOP:
        ADD HL,HL                  ; next numerator bit -> carry; quotient <<= 1
        RL E
        RL D                       ; remainder = remainder*2 + input bit
        PUSH HL
        LD H,D
        LD L,E
        LD BC,(AST_TMP0)
        OR A
        SBC HL,BC
        JR C,AD3216_FAST_NOSUB
        LD D,H
        LD E,L
        POP HL
        INC L                      ; set quotient bit 0 (shift made it zero)
        JR AD3216_FAST_NEXT
AD3216_FAST_NOSUB:
        POP HL
AD3216_FAST_NEXT:
        DEC A
        JR NZ,AD3216_FAST_LOOP
        RET

; Square signed HL. Returns unsigned square in M32_ACC.
ASTRO_SQUARE16:
        BIT 7,H
        JR Z,ASQ_POS
        CALL ASTRO_NEG_HL
ASQ_POS:
        LD D,H
        LD E,L
        JP ASTRO_UMUL16

ASTRO_COPY_ACC_TO_N:
        LD HL,M32_ACC
        LD DE,M32_N
        LD B,4
ACAN_LOOP:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ ACAN_LOOP
        RET

ASTRO_ADD_ACC_TO_N:
        LD A,(M32_N)
        LD C,A
        LD A,(M32_ACC)
        ADD A,C
        LD (M32_N),A
        LD A,(M32_N+1)
        LD C,A
        LD A,(M32_ACC+1)
        ADC A,C
        LD (M32_N+1),A
        LD A,(M32_N+2)
        LD C,A
        LD A,(M32_ACC+2)
        ADC A,C
        LD (M32_N+2),A
        LD A,(M32_N+3)
        LD C,A
        LD A,(M32_ACC+3)
        ADC A,C
        LD (M32_N+3),A
        RET

; sqrt(M32_N) via 15-step binary search, result HL 0..32767.
ASTRO_ISQRT32:
        LD HL,0
        LD (AST_LOW),HL
        LD HL,32767
        LD (AST_HIGH),HL
        LD A,15
        LD (AST_LOOPCTR),A

AISQ_LOOP:
        ; mid=(low+high+1)/2
        LD HL,(AST_LOW)
        LD DE,(AST_HIGH)
        ADD HL,DE
        INC HL
        SRL H
        RR L
        LD (AST_TMP0),HL

        ; square(mid)
        LD D,H
        LD E,L
        CALL ASTRO_UMUL16
        CALL ASTRO_CMP_ACC_N
        JR C,AISQ_TOO_BIG

        LD HL,(AST_TMP0)
        LD (AST_LOW),HL
        JR AISQ_NEXT

AISQ_TOO_BIG:
        LD HL,(AST_TMP0)
        DEC HL
        LD (AST_HIGH),HL

AISQ_NEXT:
        LD A,(AST_LOOPCTR)
        DEC A
        LD (AST_LOOPCTR),A
        JR NZ,AISQ_LOOP
        LD HL,(AST_LOW)
        RET

; Compare M32_ACC with M32_N.
; Carry set if ACC > N; carry clear otherwise.
ASTRO_CMP_ACC_N:
        LD A,(M32_N+3)
        LD C,A
        LD A,(M32_ACC+3)
        CP C
        JR C,ACAN_LE
        JR NZ,ACAN_GT
        LD A,(M32_N+2)
        LD C,A
        LD A,(M32_ACC+2)
        CP C
        JR C,ACAN_LE
        JR NZ,ACAN_GT
        LD A,(M32_N+1)
        LD C,A
        LD A,(M32_ACC+1)
        CP C
        JR C,ACAN_LE
        JR NZ,ACAN_GT
        LD A,(M32_N)
        LD C,A
        LD A,(M32_ACC)
        CP C
        JR C,ACAN_LE
        JR Z,ACAN_LE
ACAN_GT:
        SCF
        RET
ACAN_LE:
        OR A
        RET

; Vector distance sqrt(x^2+y^2+z^2) -> HL.
ASTRO_VECTOR_DISTANCE:
        LD HL,(AST_X)
        CALL ASTRO_SQUARE16
        CALL ASTRO_COPY_ACC_TO_N
        LD HL,(AST_Y)
        CALL ASTRO_SQUARE16
        CALL ASTRO_ADD_ACC_TO_N
        LD HL,(AST_Z)
        CALL ASTRO_SQUARE16
        CALL ASTRO_ADD_ACC_TO_N
        JP ASTRO_ISQRT32

; ============================================================================
; ATAN2
; ============================================================================

; HL=y signed, DE=x signed.
; Return HL=0..3599, 0=N/+x axis in mathematical atan2 convention.
; Caller passes east as y, north as x, therefore result is azimuth from north.
ASTRO_ATAN2_10:
        LD (AST_TMP0),HL           ; y
        LD (AST_TMP1),DE           ; x
        XOR A
        LD (AST_QUAD),A            ; quadrant flags

        BIT 7,H
        JR Z,AAT_YABS
        CALL ASTRO_NEG_HL
        LD A,(AST_QUAD)
        OR 1
        LD (AST_QUAD),A
AAT_YABS:
        EX DE,HL
        BIT 7,H
        JR Z,AAT_XABS
        CALL ASTRO_NEG_HL
        LD A,(AST_QUAD)
        OR 2
        LD (AST_QUAD),A
AAT_XABS:
        EX DE,HL                   ; HL=abs(y), DE=abs(x)
        CALL ASTRO_ATAN_Q1         ; HL=0..900
        LD (AST_TMP3),HL

        LD A,(AST_QUAD)
        CP 0
        JR Z,AAT_RET_Q1
        CP 2
        JR Z,AAT_Q2
        CP 3
        JR Z,AAT_Q3
        ; Q4: 3600-angle
        LD DE,3600
        EX DE,HL
        LD DE,(AST_TMP3)
        OR A
        SBC HL,DE
        RET
AAT_Q2:
        LD HL,1800
        LD DE,(AST_TMP3)
        OR A
        SBC HL,DE
        RET
AAT_Q3:
        LD HL,1800
        LD DE,(AST_TMP3)
        ADD HL,DE
        RET
AAT_RET_Q1:
        LD HL,(AST_TMP3)
        RET

; Signed elevation atan2(up,horizontal), result -900..+900.
ASTRO_ATAN2_SIGNED90:
        BIT 7,H
        JR Z,AAS90_POS
        CALL ASTRO_NEG_HL
        CALL ASTRO_ATAN_Q1
        JP ASTRO_NEG_HL
AAS90_POS:
        JP ASTRO_ATAN_Q1

; First-quadrant atan: HL=abs(y), DE=abs(x), return angle10 0..900.
; Binary search compares y*cos(a) with x*sin(a).
ASTRO_ATAN_Q1:
        LD (AST_TMP0),HL           ; abs(y)
        LD (AST_TMP1),DE           ; abs(x)
        LD HL,0
        LD (AST_LOW),HL
        LD HL,900
        LD (AST_HIGH),HL
        LD A,10
        LD (AST_LOOPCTR),A

AAQ1_LOOP:
        ; mid=(low+high+1)/2
        LD HL,(AST_LOW)
        LD DE,(AST_HIGH)
        ADD HL,DE
        INC HL
        SRL H
        RR L
        LD (AST_TMP3),HL

        ; left = y*cos(mid)
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_TMP0)
        CALL ASTRO_UMUL16
        CALL ASTRO_COPY_ACC_TO_TEST

        ; right = x*sin(mid)
        LD HL,(AST_TMP3)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_TMP1)
        CALL ASTRO_UMUL16

        ; if y*cos >= x*sin, true angle >= mid -> low=mid
        CALL ASTRO_CMP_TEST_ACC
        JR C,AAQ1_HIGH
        LD HL,(AST_TMP3)
        LD (AST_LOW),HL
        JR AAQ1_NEXT

AAQ1_HIGH:
        LD HL,(AST_TMP3)
        DEC HL
        LD (AST_HIGH),HL

AAQ1_NEXT:
        LD A,(AST_LOOPCTR)
        DEC A
        LD (AST_LOOPCTR),A
        JR NZ,AAQ1_LOOP
        LD HL,(AST_LOW)
        RET

ASTRO_COPY_ACC_TO_TEST:
        LD HL,M32_ACC
        LD DE,M32_TEST
        LD B,4
ACAT_LOOP:
        LD A,(HL)
        LD (DE),A
        INC HL
        INC DE
        DJNZ ACAT_LOOP
        RET

; Carry set if TEST < ACC, clear otherwise.
ASTRO_CMP_TEST_ACC:
        LD A,(M32_ACC+3)
        LD C,A
        LD A,(M32_TEST+3)
        CP C
        JR C,ACTA_LT
        JR NZ,ACTA_GE
        LD A,(M32_ACC+2)
        LD C,A
        LD A,(M32_TEST+2)
        CP C
        JR C,ACTA_LT
        JR NZ,ACTA_GE
        LD A,(M32_ACC+1)
        LD C,A
        LD A,(M32_TEST+1)
        CP C
        JR C,ACTA_LT
        JR NZ,ACTA_GE
        LD A,(M32_ACC)
        LD C,A
        LD A,(M32_TEST)
        CP C
        JR C,ACTA_LT
ACTA_GE:
        OR A
        RET
ACTA_LT:
        SCF
        RET

; ============================================================================
; PRINT HELPERS
; ============================================================================

; HL=minutes 0..1439 -> HH:MM.
ASTRO_PRINT_HHMM:
        LD B,0
APH_LOOP:
        LD DE,60
        OR A
        SBC HL,DE
        JR C,APH_DONE
        INC B
        JR APH_LOOP
APH_DONE:
        ADD HL,DE
        LD A,B
        CALL DISPLAY_DEC2
        LD A,':'
        CALL DISPLAY_PUT_ASCII
        LD A,L
        JP DISPLAY_DEC2

; HL angle10 0..3599 -> DDD.d
ASTRO_PRINT_AZ10:
        LD B,0
APA_1000:
        LD DE,1000
        OR A
        SBC HL,DE
        JR C,APA_1000_DONE
        INC B
        JR APA_1000
APA_1000_DONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII

        LD B,0
APA_100:
        LD DE,100
        OR A
        SBC HL,DE
        JR C,APA_100_DONE
        INC B
        JR APA_100
APA_100_DONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII

        LD B,0
APA_10:
        LD DE,10
        OR A
        SBC HL,DE
        JR C,APA_10_DONE
        INC B
        JR APA_10
APA_10_DONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,'.'
        CALL DISPLAY_PUT_ASCII
        LD A,L
        ADD A,'0'
        JP DISPLAY_PUT_ASCII

; HL signed angle10 -900..+900 -> +DD.d / -DD.d
ASTRO_PRINT_EL10:
        BIT 7,H
        JR Z,APE_POS
        LD A,'-'
        CALL DISPLAY_PUT_ASCII
        CALL ASTRO_NEG_HL
        JR APE_MAG
APE_POS:
        LD A,'+'
        CALL DISPLAY_PUT_ASCII
APE_MAG:
        ; Hundreds of tenths = tens of degrees
        LD B,0
APE_100:
        LD DE,100
        OR A
        SBC HL,DE
        JR C,APE_100_DONE
        INC B
        JR APE_100
APE_100_DONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII

        LD B,0
APE_10:
        LD DE,10
        OR A
        SBC HL,DE
        JR C,APE_10_DONE
        INC B
        JR APE_10
APE_10_DONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,'.'
        CALL DISPLAY_PUT_ASCII
        LD A,L
        ADD A,'0'
        JP DISPLAY_PUT_ASCII

; ============================================================================
; SMALL HELPERS
; ============================================================================

ASTRO_NEG_HL:
        LD A,H
        CPL
        LD H,A
        LD A,L
        CPL
        LD L,A
        INC HL
        RET

; ----------------------------------------------------------------------------
; Hour fractional anomaly corrections.
; Values are rounded tenths of degree at integer UTC hour.
; ----------------------------------------------------------------------------
SUN_HOUR_CORR:
        DB 0,0,1,1,2,2,2,3,3,4,4,5,5,5,6,6,7,7,7,8,8,9,9,9
JUP_HOUR_CORR:
        DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1
SAT_HOUR_CORR:
        DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; ----------------------------------------------------------------------------
; UI strings
; ----------------------------------------------------------------------------
MSG_JUP_VIS:    DB "JUPITER VIS",0
MSG_JUP_NOVIS:  DB "JUPITER NOVIS",0
MSG_RISE:       DB "RISE ",0
MSG_SET:        DB "SET ",0
MSG_AZ:         DB "AZ ",0
MSG_EL:         DB "EL ",0
MSG_DEG:        DB " DEG",0
MSG_NONE:       DB "NONE",0
MSG_DATE:        DB "DATE ",0
MSG_TIME:        DB "TIME ",0
MSG_DATE_PREFIX: DB "DATE ",0
MSG_DATE_MASK:   DB "MM/DD/YY",0
MSG_TIME_PREFIX: DB "TIME ",0
MSG_TIME_MASK:   DB "HH:MM:SS",0
MSG_START_TIME_MASK: DB "HH/MM/SS",0
MSG_ENTER_Q_SUFFIX: DB " ENTER ?",0
GMSG_UTC_SELECT: DB "UTC OFFSET ",0
MSG_UTC_OFFSET_Q: DB "UTC OFFSET ?",0
MSG_UTC_ENTRY_PREFIX: DB "UTC OFFSET ",0
MSG_UTC_CONFIRM_PREFIX: DB "UTC ",0
MSG_ENTER_SUFFIX2: DB " ENTER",0

; ============================================================================
; FULL 0.1-DEGREE SINE TABLE, Q15
; 3600 signed 16-bit words = 7200 bytes.
; ============================================================================
ASTRO_SIN_TABLE:
        DW 0,57,114,172,229,286,343,400,457,515,572,629   ; 0.0 deg
        DW 686,743,801,858,915,972,1029,1086,1144,1201,1258,1315   ; 1.2 deg
        DW 1372,1429,1486,1544,1601,1658,1715,1772,1829,1886,1943,2000   ; 2.4 deg
        DW 2057,2115,2172,2229,2286,2343,2400,2457,2514,2571,2628,2685   ; 3.6 deg
        DW 2742,2799,2856,2913,2970,3027,3084,3141,3197,3254,3311,3368   ; 4.8 deg
        DW 3425,3482,3539,3596,3653,3709,3766,3823,3880,3937,3993,4050   ; 6.0 deg
        DW 4107,4164,4220,4277,4334,4390,4447,4504,4560,4617,4674,4730   ; 7.2 deg
        DW 4787,4843,4900,4956,5013,5069,5126,5182,5239,5295,5352,5408   ; 8.4 deg
        DW 5465,5521,5577,5634,5690,5746,5803,5859,5915,5971,6028,6084   ; 9.6 deg
        DW 6140,6196,6252,6308,6364,6421,6477,6533,6589,6645,6701,6757   ; 10.8 deg
        DW 6813,6869,6924,6980,7036,7092,7148,7204,7259,7315,7371,7427   ; 12.0 deg
        DW 7482,7538,7594,7649,7705,7760,7816,7872,7927,7983,8038,8093   ; 13.2 deg
        DW 8149,8204,8260,8315,8370,8425,8481,8536,8591,8646,8701,8757   ; 14.4 deg
        DW 8812,8867,8922,8977,9032,9087,9142,9197,9251,9306,9361,9416   ; 15.6 deg
        DW 9471,9525,9580,9635,9689,9744,9799,9853,9908,9962,10017,10071   ; 16.8 deg
        DW 10126,10180,10234,10289,10343,10397,10451,10506,10560,10614,10668,10722   ; 18.0 deg
        DW 10776,10830,10884,10938,10992,11046,11099,11153,11207,11261,11314,11368   ; 19.2 deg
        DW 11422,11475,11529,11582,11636,11689,11743,11796,11849,11903,11956,12009   ; 20.4 deg
        DW 12062,12115,12169,12222,12275,12328,12381,12434,12487,12539,12592,12645   ; 21.6 deg
        DW 12698,12750,12803,12856,12908,12961,13013,13066,13118,13171,13223,13275   ; 22.8 deg
        DW 13328,13380,13432,13484,13536,13588,13640,13692,13744,13796,13848,13900   ; 24.0 deg
        DW 13952,14003,14055,14107,14158,14210,14261,14313,14364,14415,14467,14518   ; 25.2 deg
        DW 14569,14621,14672,14723,14774,14825,14876,14927,14978,15029,15079,15130   ; 26.4 deg
        DW 15181,15231,15282,15333,15383,15434,15484,15534,15585,15635,15685,15735   ; 27.6 deg
        DW 15786,15836,15886,15936,15986,16036,16085,16135,16185,16235,16284,16334   ; 28.8 deg
        DW 16383,16433,16482,16532,16581,16631,16680,16729,16778,16827,16876,16925   ; 30.0 deg
        DW 16974,17023,17072,17121,17169,17218,17267,17315,17364,17412,17461,17509   ; 31.2 deg
        DW 17557,17606,17654,17702,17750,17798,17846,17894,17942,17990,18038,18085   ; 32.4 deg
        DW 18133,18181,18228,18276,18323,18370,18418,18465,18512,18559,18607,18654   ; 33.6 deg
        DW 18701,18748,18794,18841,18888,18935,18981,19028,19074,19121,19167,19214   ; 34.8 deg
        DW 19260,19306,19352,19398,19445,19491,19537,19582,19628,19674,19720,19765   ; 36.0 deg
        DW 19811,19856,19902,19947,19993,20038,20083,20128,20173,20218,20263,20308   ; 37.2 deg
        DW 20353,20398,20443,20487,20532,20576,20621,20665,20710,20754,20798,20842   ; 38.4 deg
        DW 20886,20931,20974,21018,21062,21106,21150,21193,21237,21280,21324,21367   ; 39.6 deg
        DW 21411,21454,21497,21540,21583,21626,21669,21712,21755,21798,21840,21883   ; 40.8 deg
        DW 21925,21968,22010,22053,22095,22137,22179,22221,22263,22305,22347,22389   ; 42.0 deg
        DW 22431,22472,22514,22555,22597,22638,22679,22721,22762,22803,22844,22885   ; 43.2 deg
        DW 22926,22967,23007,23048,23089,23129,23170,23210,23251,23291,23331,23371   ; 44.4 deg
        DW 23411,23451,23491,23531,23571,23610,23650,23689,23729,23768,23808,23847   ; 45.6 deg
        DW 23886,23925,23964,24003,24042,24081,24120,24158,24197,24235,24274,24312   ; 46.8 deg
        DW 24351,24389,24427,24465,24503,24541,24579,24617,24654,24692,24730,24767   ; 48.0 deg
        DW 24804,24842,24879,24916,24953,24990,25027,25064,25101,25138,25174,25211   ; 49.2 deg
        DW 25247,25284,25320,25356,25393,25429,25465,25501,25537,25572,25608,25644   ; 50.4 deg
        DW 25679,25715,25750,25785,25821,25856,25891,25926,25961,25996,26031,26065   ; 51.6 deg
        DW 26100,26134,26169,26203,26238,26272,26306,26340,26374,26408,26442,26475   ; 52.8 deg
        DW 26509,26543,26576,26610,26643,26676,26709,26742,26775,26808,26841,26874   ; 54.0 deg
        DW 26907,26939,26972,27004,27036,27069,27101,27133,27165,27197,27229,27261   ; 55.2 deg
        DW 27292,27324,27355,27387,27418,27450,27481,27512,27543,27574,27605,27635   ; 56.4 deg
        DW 27666,27697,27727,27758,27788,27818,27848,27879,27909,27938,27968,27998   ; 57.6 deg
        DW 28028,28057,28087,28116,28146,28175,28204,28233,28262,28291,28320,28348   ; 58.8 deg
        DW 28377,28406,28434,28462,28491,28519,28547,28575,28603,28631,28659,28686   ; 60.0 deg
        DW 28714,28741,28769,28796,28823,28851,28878,28905,28932,28958,28985,29012   ; 61.2 deg
        DW 29038,29065,29091,29117,29144,29170,29196,29222,29247,29273,29299,29324   ; 62.4 deg
        DW 29350,29375,29400,29426,29451,29476,29501,29526,29550,29575,29600,29624   ; 63.6 deg
        DW 29648,29673,29697,29721,29745,29769,29793,29817,29840,29864,29887,29911   ; 64.8 deg
        DW 29934,29957,29980,30004,30026,30049,30072,30095,30117,30140,30162,30184   ; 66.0 deg
        DW 30207,30229,30251,30273,30295,30316,30338,30360,30381,30402,30424,30445   ; 67.2 deg
        DW 30466,30487,30508,30529,30549,30570,30591,30611,30631,30652,30672,30692   ; 68.4 deg
        DW 30712,30732,30752,30771,30791,30810,30830,30849,30868,30888,30907,30926   ; 69.6 deg
        DW 30944,30963,30982,31000,31019,31037,31056,31074,31092,31110,31128,31146   ; 70.8 deg
        DW 31163,31181,31198,31216,31233,31250,31268,31285,31302,31318,31335,31352   ; 72.0 deg
        DW 31368,31385,31401,31418,31434,31450,31466,31482,31498,31513,31529,31545   ; 73.2 deg
        DW 31560,31575,31591,31606,31621,31636,31650,31665,31680,31694,31709,31723   ; 74.4 deg
        DW 31738,31752,31766,31780,31794,31807,31821,31835,31848,31862,31875,31888   ; 75.6 deg
        DW 31901,31914,31927,31940,31953,31965,31978,31990,32003,32015,32027,32039   ; 76.8 deg
        DW 32051,32063,32075,32086,32098,32109,32121,32132,32143,32154,32165,32176   ; 78.0 deg
        DW 32187,32197,32208,32218,32229,32239,32249,32259,32269,32279,32289,32299   ; 79.2 deg
        DW 32308,32318,32327,32336,32345,32355,32364,32372,32381,32390,32399,32407   ; 80.4 deg
        DW 32415,32424,32432,32440,32448,32456,32464,32472,32479,32487,32494,32501   ; 81.6 deg
        DW 32509,32516,32523,32530,32537,32543,32550,32556,32563,32569,32575,32581   ; 82.8 deg
        DW 32587,32593,32599,32605,32611,32616,32622,32627,32632,32637,32642,32647   ; 84.0 deg
        DW 32652,32657,32661,32666,32670,32675,32679,32683,32687,32691,32695,32699   ; 85.2 deg
        DW 32702,32706,32709,32713,32716,32719,32722,32725,32728,32731,32733,32736   ; 86.4 deg
        DW 32738,32741,32743,32745,32747,32749,32751,32753,32754,32756,32757,32759   ; 87.6 deg
        DW 32760,32761,32762,32763,32764,32765,32765,32766,32766,32767,32767,32767   ; 88.8 deg
        DW 32767,32767,32767,32767,32766,32766,32765,32765,32764,32763,32762,32761   ; 90.0 deg
        DW 32760,32759,32757,32756,32754,32753,32751,32749,32747,32745,32743,32741   ; 91.2 deg
        DW 32738,32736,32733,32731,32728,32725,32722,32719,32716,32713,32709,32706   ; 92.4 deg
        DW 32702,32699,32695,32691,32687,32683,32679,32675,32670,32666,32661,32657   ; 93.6 deg
        DW 32652,32647,32642,32637,32632,32627,32622,32616,32611,32605,32599,32593   ; 94.8 deg
        DW 32587,32581,32575,32569,32563,32556,32550,32543,32537,32530,32523,32516   ; 96.0 deg
        DW 32509,32501,32494,32487,32479,32472,32464,32456,32448,32440,32432,32424   ; 97.2 deg
        DW 32415,32407,32399,32390,32381,32372,32364,32355,32345,32336,32327,32318   ; 98.4 deg
        DW 32308,32299,32289,32279,32269,32259,32249,32239,32229,32218,32208,32197   ; 99.6 deg
        DW 32187,32176,32165,32154,32143,32132,32121,32109,32098,32086,32075,32063   ; 100.8 deg
        DW 32051,32039,32027,32015,32003,31990,31978,31965,31953,31940,31927,31914   ; 102.0 deg
        DW 31901,31888,31875,31862,31848,31835,31821,31807,31794,31780,31766,31752   ; 103.2 deg
        DW 31738,31723,31709,31694,31680,31665,31650,31636,31621,31606,31591,31575   ; 104.4 deg
        DW 31560,31545,31529,31513,31498,31482,31466,31450,31434,31418,31401,31385   ; 105.6 deg
        DW 31368,31352,31335,31318,31302,31285,31268,31250,31233,31216,31198,31181   ; 106.8 deg
        DW 31163,31146,31128,31110,31092,31074,31056,31037,31019,31000,30982,30963   ; 108.0 deg
        DW 30944,30926,30907,30888,30868,30849,30830,30810,30791,30771,30752,30732   ; 109.2 deg
        DW 30712,30692,30672,30652,30631,30611,30591,30570,30549,30529,30508,30487   ; 110.4 deg
        DW 30466,30445,30424,30402,30381,30360,30338,30316,30295,30273,30251,30229   ; 111.6 deg
        DW 30207,30184,30162,30140,30117,30095,30072,30049,30026,30004,29980,29957   ; 112.8 deg
        DW 29934,29911,29887,29864,29840,29817,29793,29769,29745,29721,29697,29673   ; 114.0 deg
        DW 29648,29624,29600,29575,29550,29526,29501,29476,29451,29426,29400,29375   ; 115.2 deg
        DW 29350,29324,29299,29273,29247,29222,29196,29170,29144,29117,29091,29065   ; 116.4 deg
        DW 29038,29012,28985,28958,28932,28905,28878,28851,28823,28796,28769,28741   ; 117.6 deg
        DW 28714,28686,28659,28631,28603,28575,28547,28519,28491,28462,28434,28406   ; 118.8 deg
        DW 28377,28348,28320,28291,28262,28233,28204,28175,28146,28116,28087,28057   ; 120.0 deg
        DW 28028,27998,27968,27938,27909,27879,27848,27818,27788,27758,27727,27697   ; 121.2 deg
        DW 27666,27635,27605,27574,27543,27512,27481,27450,27418,27387,27355,27324   ; 122.4 deg
        DW 27292,27261,27229,27197,27165,27133,27101,27069,27036,27004,26972,26939   ; 123.6 deg
        DW 26907,26874,26841,26808,26775,26742,26709,26676,26643,26610,26576,26543   ; 124.8 deg
        DW 26509,26475,26442,26408,26374,26340,26306,26272,26238,26203,26169,26134   ; 126.0 deg
        DW 26100,26065,26031,25996,25961,25926,25891,25856,25821,25785,25750,25715   ; 127.2 deg
        DW 25679,25644,25608,25572,25537,25501,25465,25429,25393,25356,25320,25284   ; 128.4 deg
        DW 25247,25211,25174,25138,25101,25064,25027,24990,24953,24916,24879,24842   ; 129.6 deg
        DW 24804,24767,24730,24692,24654,24617,24579,24541,24503,24465,24427,24389   ; 130.8 deg
        DW 24351,24312,24274,24235,24197,24158,24120,24081,24042,24003,23964,23925   ; 132.0 deg
        DW 23886,23847,23808,23768,23729,23689,23650,23610,23571,23531,23491,23451   ; 133.2 deg
        DW 23411,23371,23331,23291,23251,23210,23170,23129,23089,23048,23007,22967   ; 134.4 deg
        DW 22926,22885,22844,22803,22762,22721,22679,22638,22597,22555,22514,22472   ; 135.6 deg
        DW 22431,22389,22347,22305,22263,22221,22179,22137,22095,22053,22010,21968   ; 136.8 deg
        DW 21925,21883,21840,21798,21755,21712,21669,21626,21583,21540,21497,21454   ; 138.0 deg
        DW 21411,21367,21324,21280,21237,21193,21150,21106,21062,21018,20974,20931   ; 139.2 deg
        DW 20886,20842,20798,20754,20710,20665,20621,20576,20532,20487,20443,20398   ; 140.4 deg
        DW 20353,20308,20263,20218,20173,20128,20083,20038,19993,19947,19902,19856   ; 141.6 deg
        DW 19811,19765,19720,19674,19628,19582,19537,19491,19445,19398,19352,19306   ; 142.8 deg
        DW 19260,19214,19167,19121,19074,19028,18981,18935,18888,18841,18794,18748   ; 144.0 deg
        DW 18701,18654,18607,18559,18512,18465,18418,18370,18323,18276,18228,18181   ; 145.2 deg
        DW 18133,18085,18038,17990,17942,17894,17846,17798,17750,17702,17654,17606   ; 146.4 deg
        DW 17557,17509,17461,17412,17364,17315,17267,17218,17169,17121,17072,17023   ; 147.6 deg
        DW 16974,16925,16876,16827,16778,16729,16680,16631,16581,16532,16482,16433   ; 148.8 deg
        DW 16383,16334,16284,16235,16185,16135,16085,16036,15986,15936,15886,15836   ; 150.0 deg
        DW 15786,15735,15685,15635,15585,15534,15484,15434,15383,15333,15282,15231   ; 151.2 deg
        DW 15181,15130,15079,15029,14978,14927,14876,14825,14774,14723,14672,14621   ; 152.4 deg
        DW 14569,14518,14467,14415,14364,14313,14261,14210,14158,14107,14055,14003   ; 153.6 deg
        DW 13952,13900,13848,13796,13744,13692,13640,13588,13536,13484,13432,13380   ; 154.8 deg
        DW 13328,13275,13223,13171,13118,13066,13013,12961,12908,12856,12803,12750   ; 156.0 deg
        DW 12698,12645,12592,12539,12487,12434,12381,12328,12275,12222,12169,12115   ; 157.2 deg
        DW 12062,12009,11956,11903,11849,11796,11743,11689,11636,11582,11529,11475   ; 158.4 deg
        DW 11422,11368,11314,11261,11207,11153,11099,11046,10992,10938,10884,10830   ; 159.6 deg
        DW 10776,10722,10668,10614,10560,10506,10451,10397,10343,10289,10234,10180   ; 160.8 deg
        DW 10126,10071,10017,9962,9908,9853,9799,9744,9689,9635,9580,9525   ; 162.0 deg
        DW 9471,9416,9361,9306,9251,9197,9142,9087,9032,8977,8922,8867   ; 163.2 deg
        DW 8812,8757,8701,8646,8591,8536,8481,8425,8370,8315,8260,8204   ; 164.4 deg
        DW 8149,8093,8038,7983,7927,7872,7816,7760,7705,7649,7594,7538   ; 165.6 deg
        DW 7482,7427,7371,7315,7259,7204,7148,7092,7036,6980,6924,6869   ; 166.8 deg
        DW 6813,6757,6701,6645,6589,6533,6477,6421,6364,6308,6252,6196   ; 168.0 deg
        DW 6140,6084,6028,5971,5915,5859,5803,5746,5690,5634,5577,5521   ; 169.2 deg
        DW 5465,5408,5352,5295,5239,5182,5126,5069,5013,4956,4900,4843   ; 170.4 deg
        DW 4787,4730,4674,4617,4560,4504,4447,4390,4334,4277,4220,4164   ; 171.6 deg
        DW 4107,4050,3993,3937,3880,3823,3766,3709,3653,3596,3539,3482   ; 172.8 deg
        DW 3425,3368,3311,3254,3197,3141,3084,3027,2970,2913,2856,2799   ; 174.0 deg
        DW 2742,2685,2628,2571,2514,2457,2400,2343,2286,2229,2172,2115   ; 175.2 deg
        DW 2057,2000,1943,1886,1829,1772,1715,1658,1601,1544,1486,1429   ; 176.4 deg
        DW 1372,1315,1258,1201,1144,1086,1029,972,915,858,801,743   ; 177.6 deg
        DW 686,629,572,515,457,400,343,286,229,172,114,57   ; 178.8 deg
        DW 0,-57,-114,-172,-229,-286,-343,-400,-457,-515,-572,-629   ; 180.0 deg
        DW -686,-743,-801,-858,-915,-972,-1029,-1086,-1144,-1201,-1258,-1315   ; 181.2 deg
        DW -1372,-1429,-1486,-1544,-1601,-1658,-1715,-1772,-1829,-1886,-1943,-2000   ; 182.4 deg
        DW -2057,-2115,-2172,-2229,-2286,-2343,-2400,-2457,-2514,-2571,-2628,-2685   ; 183.6 deg
        DW -2742,-2799,-2856,-2913,-2970,-3027,-3084,-3141,-3197,-3254,-3311,-3368   ; 184.8 deg
        DW -3425,-3482,-3539,-3596,-3653,-3709,-3766,-3823,-3880,-3937,-3993,-4050   ; 186.0 deg
        DW -4107,-4164,-4220,-4277,-4334,-4390,-4447,-4504,-4560,-4617,-4674,-4730   ; 187.2 deg
        DW -4787,-4843,-4900,-4956,-5013,-5069,-5126,-5182,-5239,-5295,-5352,-5408   ; 188.4 deg
        DW -5465,-5521,-5577,-5634,-5690,-5746,-5803,-5859,-5915,-5971,-6028,-6084   ; 189.6 deg
        DW -6140,-6196,-6252,-6308,-6364,-6421,-6477,-6533,-6589,-6645,-6701,-6757   ; 190.8 deg
        DW -6813,-6869,-6924,-6980,-7036,-7092,-7148,-7204,-7259,-7315,-7371,-7427   ; 192.0 deg
        DW -7482,-7538,-7594,-7649,-7705,-7760,-7816,-7872,-7927,-7983,-8038,-8093   ; 193.2 deg
        DW -8149,-8204,-8260,-8315,-8370,-8425,-8481,-8536,-8591,-8646,-8701,-8757   ; 194.4 deg
        DW -8812,-8867,-8922,-8977,-9032,-9087,-9142,-9197,-9251,-9306,-9361,-9416   ; 195.6 deg
        DW -9471,-9525,-9580,-9635,-9689,-9744,-9799,-9853,-9908,-9962,-10017,-10071   ; 196.8 deg
        DW -10126,-10180,-10234,-10289,-10343,-10397,-10451,-10506,-10560,-10614,-10668,-10722   ; 198.0 deg
        DW -10776,-10830,-10884,-10938,-10992,-11046,-11099,-11153,-11207,-11261,-11314,-11368   ; 199.2 deg
        DW -11422,-11475,-11529,-11582,-11636,-11689,-11743,-11796,-11849,-11903,-11956,-12009   ; 200.4 deg
        DW -12062,-12115,-12169,-12222,-12275,-12328,-12381,-12434,-12487,-12539,-12592,-12645   ; 201.6 deg
        DW -12698,-12750,-12803,-12856,-12908,-12961,-13013,-13066,-13118,-13171,-13223,-13275   ; 202.8 deg
        DW -13328,-13380,-13432,-13484,-13536,-13588,-13640,-13692,-13744,-13796,-13848,-13900   ; 204.0 deg
        DW -13952,-14003,-14055,-14107,-14158,-14210,-14261,-14313,-14364,-14415,-14467,-14518   ; 205.2 deg
        DW -14569,-14621,-14672,-14723,-14774,-14825,-14876,-14927,-14978,-15029,-15079,-15130   ; 206.4 deg
        DW -15181,-15231,-15282,-15333,-15383,-15434,-15484,-15534,-15585,-15635,-15685,-15735   ; 207.6 deg
        DW -15786,-15836,-15886,-15936,-15986,-16036,-16085,-16135,-16185,-16235,-16284,-16334   ; 208.8 deg
        DW -16384,-16433,-16482,-16532,-16581,-16631,-16680,-16729,-16778,-16827,-16876,-16925   ; 210.0 deg
        DW -16974,-17023,-17072,-17121,-17169,-17218,-17267,-17315,-17364,-17412,-17461,-17509   ; 211.2 deg
        DW -17557,-17606,-17654,-17702,-17750,-17798,-17846,-17894,-17942,-17990,-18038,-18085   ; 212.4 deg
        DW -18133,-18181,-18228,-18276,-18323,-18370,-18418,-18465,-18512,-18559,-18607,-18654   ; 213.6 deg
        DW -18701,-18748,-18794,-18841,-18888,-18935,-18981,-19028,-19074,-19121,-19167,-19214   ; 214.8 deg
        DW -19260,-19306,-19352,-19398,-19445,-19491,-19537,-19582,-19628,-19674,-19720,-19765   ; 216.0 deg
        DW -19811,-19856,-19902,-19947,-19993,-20038,-20083,-20128,-20173,-20218,-20263,-20308   ; 217.2 deg
        DW -20353,-20398,-20443,-20487,-20532,-20576,-20621,-20665,-20710,-20754,-20798,-20842   ; 218.4 deg
        DW -20886,-20931,-20974,-21018,-21062,-21106,-21150,-21193,-21237,-21280,-21324,-21367   ; 219.6 deg
        DW -21411,-21454,-21497,-21540,-21583,-21626,-21669,-21712,-21755,-21798,-21840,-21883   ; 220.8 deg
        DW -21925,-21968,-22010,-22053,-22095,-22137,-22179,-22221,-22263,-22305,-22347,-22389   ; 222.0 deg
        DW -22431,-22472,-22514,-22555,-22597,-22638,-22679,-22721,-22762,-22803,-22844,-22885   ; 223.2 deg
        DW -22926,-22967,-23007,-23048,-23089,-23129,-23170,-23210,-23251,-23291,-23331,-23371   ; 224.4 deg
        DW -23411,-23451,-23491,-23531,-23571,-23610,-23650,-23689,-23729,-23768,-23808,-23847   ; 225.6 deg
        DW -23886,-23925,-23964,-24003,-24042,-24081,-24120,-24158,-24197,-24235,-24274,-24312   ; 226.8 deg
        DW -24351,-24389,-24427,-24465,-24503,-24541,-24579,-24617,-24654,-24692,-24730,-24767   ; 228.0 deg
        DW -24804,-24842,-24879,-24916,-24953,-24990,-25027,-25064,-25101,-25138,-25174,-25211   ; 229.2 deg
        DW -25247,-25284,-25320,-25356,-25393,-25429,-25465,-25501,-25537,-25572,-25608,-25644   ; 230.4 deg
        DW -25679,-25715,-25750,-25785,-25821,-25856,-25891,-25926,-25961,-25996,-26031,-26065   ; 231.6 deg
        DW -26100,-26134,-26169,-26203,-26238,-26272,-26306,-26340,-26374,-26408,-26442,-26475   ; 232.8 deg
        DW -26509,-26543,-26576,-26610,-26643,-26676,-26709,-26742,-26775,-26808,-26841,-26874   ; 234.0 deg
        DW -26907,-26939,-26972,-27004,-27036,-27069,-27101,-27133,-27165,-27197,-27229,-27261   ; 235.2 deg
        DW -27292,-27324,-27355,-27387,-27418,-27450,-27481,-27512,-27543,-27574,-27605,-27635   ; 236.4 deg
        DW -27666,-27697,-27727,-27758,-27788,-27818,-27848,-27879,-27909,-27938,-27968,-27998   ; 237.6 deg
        DW -28028,-28057,-28087,-28116,-28146,-28175,-28204,-28233,-28262,-28291,-28320,-28348   ; 238.8 deg
        DW -28377,-28406,-28434,-28462,-28491,-28519,-28547,-28575,-28603,-28631,-28659,-28686   ; 240.0 deg
        DW -28714,-28741,-28769,-28796,-28823,-28851,-28878,-28905,-28932,-28958,-28985,-29012   ; 241.2 deg
        DW -29038,-29065,-29091,-29117,-29144,-29170,-29196,-29222,-29247,-29273,-29299,-29324   ; 242.4 deg
        DW -29350,-29375,-29400,-29426,-29451,-29476,-29501,-29526,-29550,-29575,-29600,-29624   ; 243.6 deg
        DW -29648,-29673,-29697,-29721,-29745,-29769,-29793,-29817,-29840,-29864,-29887,-29911   ; 244.8 deg
        DW -29934,-29957,-29980,-30004,-30026,-30049,-30072,-30095,-30117,-30140,-30162,-30184   ; 246.0 deg
        DW -30207,-30229,-30251,-30273,-30295,-30316,-30338,-30360,-30381,-30402,-30424,-30445   ; 247.2 deg
        DW -30466,-30487,-30508,-30529,-30549,-30570,-30591,-30611,-30631,-30652,-30672,-30692   ; 248.4 deg
        DW -30712,-30732,-30752,-30771,-30791,-30810,-30830,-30849,-30868,-30888,-30907,-30926   ; 249.6 deg
        DW -30944,-30963,-30982,-31000,-31019,-31037,-31056,-31074,-31092,-31110,-31128,-31146   ; 250.8 deg
        DW -31163,-31181,-31198,-31216,-31233,-31250,-31268,-31285,-31302,-31318,-31335,-31352   ; 252.0 deg
        DW -31368,-31385,-31401,-31418,-31434,-31450,-31466,-31482,-31498,-31513,-31529,-31545   ; 253.2 deg
        DW -31560,-31575,-31591,-31606,-31621,-31636,-31650,-31665,-31680,-31694,-31709,-31723   ; 254.4 deg
        DW -31738,-31752,-31766,-31780,-31794,-31807,-31821,-31835,-31848,-31862,-31875,-31888   ; 255.6 deg
        DW -31901,-31914,-31927,-31940,-31953,-31965,-31978,-31990,-32003,-32015,-32027,-32039   ; 256.8 deg
        DW -32051,-32063,-32075,-32086,-32098,-32109,-32121,-32132,-32143,-32154,-32165,-32176   ; 258.0 deg
        DW -32187,-32197,-32208,-32218,-32229,-32239,-32249,-32259,-32269,-32279,-32289,-32299   ; 259.2 deg
        DW -32308,-32318,-32327,-32336,-32345,-32355,-32364,-32372,-32381,-32390,-32399,-32407   ; 260.4 deg
        DW -32415,-32424,-32432,-32440,-32448,-32456,-32464,-32472,-32479,-32487,-32494,-32501   ; 261.6 deg
        DW -32509,-32516,-32523,-32530,-32537,-32543,-32550,-32556,-32563,-32569,-32575,-32581   ; 262.8 deg
        DW -32587,-32593,-32599,-32605,-32611,-32616,-32622,-32627,-32632,-32637,-32642,-32647   ; 264.0 deg
        DW -32652,-32657,-32661,-32666,-32670,-32675,-32679,-32683,-32687,-32691,-32695,-32699   ; 265.2 deg
        DW -32702,-32706,-32709,-32713,-32716,-32719,-32722,-32725,-32728,-32731,-32733,-32736   ; 266.4 deg
        DW -32738,-32741,-32743,-32745,-32747,-32749,-32751,-32753,-32754,-32756,-32757,-32759   ; 267.6 deg
        DW -32760,-32761,-32762,-32763,-32764,-32765,-32765,-32766,-32766,-32767,-32767,-32767   ; 268.8 deg
        DW -32767,-32767,-32767,-32767,-32766,-32766,-32765,-32765,-32764,-32763,-32762,-32761   ; 270.0 deg
        DW -32760,-32759,-32757,-32756,-32754,-32753,-32751,-32749,-32747,-32745,-32743,-32741   ; 271.2 deg
        DW -32738,-32736,-32733,-32731,-32728,-32725,-32722,-32719,-32716,-32713,-32709,-32706   ; 272.4 deg
        DW -32702,-32699,-32695,-32691,-32687,-32683,-32679,-32675,-32670,-32666,-32661,-32657   ; 273.6 deg
        DW -32652,-32647,-32642,-32637,-32632,-32627,-32622,-32616,-32611,-32605,-32599,-32593   ; 274.8 deg
        DW -32587,-32581,-32575,-32569,-32563,-32556,-32550,-32543,-32537,-32530,-32523,-32516   ; 276.0 deg
        DW -32509,-32501,-32494,-32487,-32479,-32472,-32464,-32456,-32448,-32440,-32432,-32424   ; 277.2 deg
        DW -32415,-32407,-32399,-32390,-32381,-32372,-32364,-32355,-32345,-32336,-32327,-32318   ; 278.4 deg
        DW -32308,-32299,-32289,-32279,-32269,-32259,-32249,-32239,-32229,-32218,-32208,-32197   ; 279.6 deg
        DW -32187,-32176,-32165,-32154,-32143,-32132,-32121,-32109,-32098,-32086,-32075,-32063   ; 280.8 deg
        DW -32051,-32039,-32027,-32015,-32003,-31990,-31978,-31965,-31953,-31940,-31927,-31914   ; 282.0 deg
        DW -31901,-31888,-31875,-31862,-31848,-31835,-31821,-31807,-31794,-31780,-31766,-31752   ; 283.2 deg
        DW -31738,-31723,-31709,-31694,-31680,-31665,-31650,-31636,-31621,-31606,-31591,-31575   ; 284.4 deg
        DW -31560,-31545,-31529,-31513,-31498,-31482,-31466,-31450,-31434,-31418,-31401,-31385   ; 285.6 deg
        DW -31368,-31352,-31335,-31318,-31302,-31285,-31268,-31250,-31233,-31216,-31198,-31181   ; 286.8 deg
        DW -31163,-31146,-31128,-31110,-31092,-31074,-31056,-31037,-31019,-31000,-30982,-30963   ; 288.0 deg
        DW -30944,-30926,-30907,-30888,-30868,-30849,-30830,-30810,-30791,-30771,-30752,-30732   ; 289.2 deg
        DW -30712,-30692,-30672,-30652,-30631,-30611,-30591,-30570,-30549,-30529,-30508,-30487   ; 290.4 deg
        DW -30466,-30445,-30424,-30402,-30381,-30360,-30338,-30316,-30295,-30273,-30251,-30229   ; 291.6 deg
        DW -30207,-30184,-30162,-30140,-30117,-30095,-30072,-30049,-30026,-30004,-29980,-29957   ; 292.8 deg
        DW -29934,-29911,-29887,-29864,-29840,-29817,-29793,-29769,-29745,-29721,-29697,-29673   ; 294.0 deg
        DW -29648,-29624,-29600,-29575,-29550,-29526,-29501,-29476,-29451,-29426,-29400,-29375   ; 295.2 deg
        DW -29350,-29324,-29299,-29273,-29247,-29222,-29196,-29170,-29144,-29117,-29091,-29065   ; 296.4 deg
        DW -29038,-29012,-28985,-28958,-28932,-28905,-28878,-28851,-28823,-28796,-28769,-28741   ; 297.6 deg
        DW -28714,-28686,-28659,-28631,-28603,-28575,-28547,-28519,-28491,-28462,-28434,-28406   ; 298.8 deg
        DW -28377,-28348,-28320,-28291,-28262,-28233,-28204,-28175,-28146,-28116,-28087,-28057   ; 300.0 deg
        DW -28028,-27998,-27968,-27938,-27909,-27879,-27848,-27818,-27788,-27758,-27727,-27697   ; 301.2 deg
        DW -27666,-27635,-27605,-27574,-27543,-27512,-27481,-27450,-27418,-27387,-27355,-27324   ; 302.4 deg
        DW -27292,-27261,-27229,-27197,-27165,-27133,-27101,-27069,-27036,-27004,-26972,-26939   ; 303.6 deg
        DW -26907,-26874,-26841,-26808,-26775,-26742,-26709,-26676,-26643,-26610,-26576,-26543   ; 304.8 deg
        DW -26509,-26475,-26442,-26408,-26374,-26340,-26306,-26272,-26238,-26203,-26169,-26134   ; 306.0 deg
        DW -26100,-26065,-26031,-25996,-25961,-25926,-25891,-25856,-25821,-25785,-25750,-25715   ; 307.2 deg
        DW -25679,-25644,-25608,-25572,-25537,-25501,-25465,-25429,-25393,-25356,-25320,-25284   ; 308.4 deg
        DW -25247,-25211,-25174,-25138,-25101,-25064,-25027,-24990,-24953,-24916,-24879,-24842   ; 309.6 deg
        DW -24804,-24767,-24730,-24692,-24654,-24617,-24579,-24541,-24503,-24465,-24427,-24389   ; 310.8 deg
        DW -24351,-24312,-24274,-24235,-24197,-24158,-24120,-24081,-24042,-24003,-23964,-23925   ; 312.0 deg
        DW -23886,-23847,-23808,-23768,-23729,-23689,-23650,-23610,-23571,-23531,-23491,-23451   ; 313.2 deg
        DW -23411,-23371,-23331,-23291,-23251,-23210,-23170,-23129,-23089,-23048,-23007,-22967   ; 314.4 deg
        DW -22926,-22885,-22844,-22803,-22762,-22721,-22679,-22638,-22597,-22555,-22514,-22472   ; 315.6 deg
        DW -22431,-22389,-22347,-22305,-22263,-22221,-22179,-22137,-22095,-22053,-22010,-21968   ; 316.8 deg
        DW -21925,-21883,-21840,-21798,-21755,-21712,-21669,-21626,-21583,-21540,-21497,-21454   ; 318.0 deg
        DW -21411,-21367,-21324,-21280,-21237,-21193,-21150,-21106,-21062,-21018,-20974,-20931   ; 319.2 deg
        DW -20886,-20842,-20798,-20754,-20710,-20665,-20621,-20576,-20532,-20487,-20443,-20398   ; 320.4 deg
        DW -20353,-20308,-20263,-20218,-20173,-20128,-20083,-20038,-19993,-19947,-19902,-19856   ; 321.6 deg
        DW -19811,-19765,-19720,-19674,-19628,-19582,-19537,-19491,-19445,-19398,-19352,-19306   ; 322.8 deg
        DW -19260,-19214,-19167,-19121,-19074,-19028,-18981,-18935,-18888,-18841,-18794,-18748   ; 324.0 deg
        DW -18701,-18654,-18607,-18559,-18512,-18465,-18418,-18370,-18323,-18276,-18228,-18181   ; 325.2 deg
        DW -18133,-18085,-18038,-17990,-17942,-17894,-17846,-17798,-17750,-17702,-17654,-17606   ; 326.4 deg
        DW -17557,-17509,-17461,-17412,-17364,-17315,-17267,-17218,-17169,-17121,-17072,-17023   ; 327.6 deg
        DW -16974,-16925,-16876,-16827,-16778,-16729,-16680,-16631,-16581,-16532,-16482,-16433   ; 328.8 deg
        DW -16384,-16334,-16284,-16235,-16185,-16135,-16085,-16036,-15986,-15936,-15886,-15836   ; 330.0 deg
        DW -15786,-15735,-15685,-15635,-15585,-15534,-15484,-15434,-15383,-15333,-15282,-15231   ; 331.2 deg
        DW -15181,-15130,-15079,-15029,-14978,-14927,-14876,-14825,-14774,-14723,-14672,-14621   ; 332.4 deg
        DW -14569,-14518,-14467,-14415,-14364,-14313,-14261,-14210,-14158,-14107,-14055,-14003   ; 333.6 deg
        DW -13952,-13900,-13848,-13796,-13744,-13692,-13640,-13588,-13536,-13484,-13432,-13380   ; 334.8 deg
        DW -13328,-13275,-13223,-13171,-13118,-13066,-13013,-12961,-12908,-12856,-12803,-12750   ; 336.0 deg
        DW -12698,-12645,-12592,-12539,-12487,-12434,-12381,-12328,-12275,-12222,-12169,-12115   ; 337.2 deg
        DW -12062,-12009,-11956,-11903,-11849,-11796,-11743,-11689,-11636,-11582,-11529,-11475   ; 338.4 deg
        DW -11422,-11368,-11314,-11261,-11207,-11153,-11099,-11046,-10992,-10938,-10884,-10830   ; 339.6 deg
        DW -10776,-10722,-10668,-10614,-10560,-10506,-10451,-10397,-10343,-10289,-10234,-10180   ; 340.8 deg
        DW -10126,-10071,-10017,-9962,-9908,-9853,-9799,-9744,-9689,-9635,-9580,-9525   ; 342.0 deg
        DW -9471,-9416,-9361,-9306,-9251,-9197,-9142,-9087,-9032,-8977,-8922,-8867   ; 343.2 deg
        DW -8812,-8757,-8701,-8646,-8591,-8536,-8481,-8425,-8370,-8315,-8260,-8204   ; 344.4 deg
        DW -8149,-8093,-8038,-7983,-7927,-7872,-7816,-7760,-7705,-7649,-7594,-7538   ; 345.6 deg
        DW -7482,-7427,-7371,-7315,-7259,-7204,-7148,-7092,-7036,-6980,-6924,-6869   ; 346.8 deg
        DW -6813,-6757,-6701,-6645,-6589,-6533,-6477,-6421,-6364,-6308,-6252,-6196   ; 348.0 deg
        DW -6140,-6084,-6028,-5971,-5915,-5859,-5803,-5746,-5690,-5634,-5577,-5521   ; 349.2 deg
        DW -5465,-5408,-5352,-5295,-5239,-5182,-5126,-5069,-5013,-4956,-4900,-4843   ; 350.4 deg
        DW -4787,-4730,-4674,-4617,-4560,-4504,-4447,-4390,-4334,-4277,-4220,-4164   ; 351.6 deg
        DW -4107,-4050,-3993,-3937,-3880,-3823,-3766,-3709,-3653,-3596,-3539,-3482   ; 352.8 deg
        DW -3425,-3368,-3311,-3254,-3197,-3141,-3084,-3027,-2970,-2913,-2856,-2799   ; 354.0 deg
        DW -2742,-2685,-2628,-2571,-2514,-2457,-2400,-2343,-2286,-2229,-2172,-2115   ; 355.2 deg
        DW -2057,-2000,-1943,-1886,-1829,-1772,-1715,-1658,-1601,-1544,-1486,-1429   ; 356.4 deg
        DW -1372,-1315,-1258,-1201,-1144,-1086,-1029,-972,-915,-858,-801,-743   ; 357.6 deg
        DW -686,-629,-572,-515,-457,-400,-343,-286,-229,-172,-114,-57   ; 358.8 deg

; ============================================================================
; TRANZ 330 STANDALONE 10-OBJECT ASTRONOMY FRONT END + GENERIC ENGINE
; Uses math/RTC primitives from TRANZ330_JUPITER_FIXED_V1_PATCHED above.
; ============================================================================

; User-facing objects
G_OBJ_MERCURY   EQU 0
G_OBJ_VENUS     EQU 1
G_OBJ_SUN       EQU 2
G_OBJ_MARS      EQU 3
G_OBJ_JUPITER   EQU 4
G_OBJ_SATURN    EQU 5
G_OBJ_URANUS    EQU 6
G_OBJ_NEPTUNE   EQU 7
G_OBJ_PLUTO     EQU 8
G_OBJ_MOON      EQU 9

; Extra RAM after the Jupiter module's documented block (+117 last byte)
G_RAM           EQU ASTRO_RAM+128
G_OBJECT        EQU G_RAM+0
G_SCREEN        EQU G_RAM+1
G_PHASE         EQU G_RAM+2
G_TRANSIT       EQU G_RAM+3       ; word
G_MAXUP         EQU G_RAM+5       ; signed word
G_COARSE_TRANS  EQU G_RAM+7       ; word
G_H0_Q15        EQU G_RAM+9       ; signed word
G_UTC_MIN       EQU G_RAM+11      ; word
G_TMPW0         EQU G_RAM+13
G_TMPW1         EQU G_RAM+15
G_TMPW2         EQU G_RAM+17
G_TMPW3         EQU G_RAM+19
G_TMPB0         EQU G_RAM+21
G_CALC_BASE     EQU G_RAM+22
G_CALC_RATE     EQU G_RAM+24
G_CALC_INT      EQU G_RAM+26
G_CALC_FRAC     EQU G_RAM+28
G_CALC_SIGN     EQU G_RAM+30

; Selected normal-planet parameters, copied from ROM table
G_N0            EQU G_RAM+32
G_NR            EQU G_RAM+34
G_I0            EQU G_RAM+36
G_IR            EQU G_RAM+38
G_W0            EQU G_RAM+40
G_WR            EQU G_RAM+42
G_M0            EQU G_RAM+44
G_MI            EQU G_RAM+46
G_MF            EQU G_RAM+48
G_MX100         EQU G_RAM+50
G_AQ            EQU G_RAM+52
G_AEQ           EQU G_RAM+54
G_BQ            EQU G_RAM+56
G_K1            EQU G_RAM+58
G_K2            EQU G_RAM+60
G_N             EQU G_RAM+62
G_I             EQU G_RAM+64
G_W             EQU G_RAM+66
G_M             EQU G_RAM+68

; Ecliptic / temporary vectors
G_SX            EQU G_RAM+70
G_SY            EQU G_RAM+72
G_XV            EQU G_RAM+74
G_YV            EQU G_RAM+76
G_X1            EQU G_RAM+78
G_Y1            EQU G_RAM+80
G_XH            EQU G_RAM+82
G_YH            EQU G_RAM+84
G_ZH            EQU G_RAM+86
G_LON           EQU G_RAM+88
G_LAT           EQU G_RAM+90
G_PSUM          EQU G_RAM+92
G_MOON_LON      EQU G_RAM+94
G_SUN_LON       EQU G_RAM+96
G_PREV_MIN      EQU G_RAM+98      ; word
G_EVENT_KIND    EQU G_RAM+100
G_SCAN_STEP     EQU G_RAM+101
G_CUR_UP        EQU G_RAM+102     ; word
G_DYN_PREV      EQU G_RAM+104
G_DYN_STATE     EQU G_RAM+106
G_SUN_M_CUR     EQU G_RAM+108     ; current solar mean anomaly, angle10
G_SAVE_MIN      EQU G_RAM+110
G_SAVE_HOUR     EQU G_RAM+111
G_SAVE_DAY      EQU G_RAM+112
G_SAVE_MONTH    EQU G_RAM+113
G_SAVE_YEAR     EQU G_RAM+114
G_DBG_SUN_E     EQU G_RAM+116
G_DBG_PLAN_M    EQU G_RAM+118
G_DBG_PLAN_E    EQU G_RAM+120
G_DBG_HEL_X     EQU G_RAM+122
G_DBG_HEL_Y     EQU G_RAM+124
G_DBG_HEL_Z     EQU G_RAM+126
G_DBG_GEO_X     EQU G_RAM+128
G_DBG_GEO_Y     EQU G_RAM+130
G_DBG_GEO_Z     EQU G_RAM+132
G_DBG_XV        EQU G_RAM+134
G_DBG_YV        EQU G_RAM+136
G_PHASE_DIR     EQU G_RAM+138     ; 0=waxing, 1=waning
G_PROGRESS      EQU G_RAM+139     ; 0..5 progress dots
G_MOON_LOCAL_MIN EQU G_RAM+140 ; word: local minute preserved across lunar vector scratch use
G_REFINE_MIN    EQU G_RAM+142  ; word: refinement scan minute preserved across lunar vector scratch use

; V11 runtime GPS/site state.
G_SITE_LON10          EQU G_RAM+144  ; signed tenths degree
G_SITE_LAT10          EQU G_RAM+146  ; signed tenths degree
G_SITE_LAT_SIN_Q15    EQU G_RAM+148
G_SITE_LAT_COS_Q15    EQU G_RAM+150
GPS_UTC_YEAR          EQU G_RAM+152
GPS_UTC_MONTH         EQU G_RAM+153
GPS_UTC_DAY           EQU G_RAM+154
GPS_UTC_HOUR          EQU G_RAM+155
GPS_UTC_MINUTE        EQU G_RAM+156
GPS_UTC_SECOND        EQU G_RAM+157
GPS_SITE_LAT_DEG      EQU G_RAM+158
GPS_SITE_LAT_FRAC3    EQU G_RAM+159  ; word 000..999
GPS_SITE_LAT_HEMI     EQU G_RAM+161
GPS_SITE_LON_DEG      EQU G_RAM+162
GPS_SITE_LON_FRAC3    EQU G_RAM+163  ; word 000..999
GPS_SITE_LON_HEMI     EQU G_RAM+165
GPS_COLLECTING        EQU G_RAM+166
GPS_INDEX             EQU G_RAM+167
GPS_FIX_READY         EQU G_RAM+168
GPS_RX_SAVED          EQU G_RAM+169
GPS_FIELD_PTR         EQU G_RAM+170  ; word
GPS_TMP_UTC_YEAR      EQU G_RAM+172
GPS_TMP_UTC_MONTH     EQU G_RAM+173
GPS_TMP_UTC_DAY       EQU G_RAM+174
GPS_TMP_UTC_HOUR      EQU G_RAM+175
GPS_TMP_UTC_MIN       EQU G_RAM+176
GPS_TMP_UTC_SEC       EQU G_RAM+177
GPS_TMP_LAT_DEG       EQU G_RAM+178
GPS_TMP_LAT_FRAC3     EQU G_RAM+179  ; word
GPS_TMP_LAT_HEMI      EQU G_RAM+181
GPS_TMP_LON_DEG       EQU G_RAM+182
GPS_TMP_LON_FRAC3     EQU G_RAM+183  ; word
GPS_TMP_LON_HEMI      EQU G_RAM+185
GPS_TMP_LAT10         EQU G_RAM+186  ; word
GPS_TMP_LON10         EQU G_RAM+188  ; word
GPS_TMP_COORD_DEG     EQU G_RAM+190
GPS_TMP_COORD_FRAC3   EQU G_RAM+191  ; word
GPS_TMP_COORD_ANGLE10 EQU G_RAM+193  ; word
GPS_TMP_MINUTES       EQU G_RAM+195
GPS_TMP_F1            EQU G_RAM+196
GPS_TMP_F2            EQU G_RAM+197
GPS_TMP_F3            EQU G_RAM+198
GPS_TMP_MIN_MILLI     EQU G_RAM+199  ; word
GPS_TMP_COORD_ORIG_DEG EQU G_RAM+201
; RTC read staging uses the six-byte gap immediately before GPS_BUFFER.
; Values are committed to AST_* only after the complete RTC snapshot validates.
RTC_TMP_YEAR          EQU G_RAM+202
RTC_TMP_MONTH         EQU G_RAM+203
RTC_TMP_DAY           EQU G_RAM+204
RTC_TMP_HOUR          EQU G_RAM+205
RTC_TMP_MINUTE        EQU G_RAM+206
RTC_TMP_SECOND        EQU G_RAM+207
GPS_BUFFER            EQU G_RAM+208  ; 80-byte sentence buffer through +287

; V11d11 print workflow state.  This starts immediately after the 80-byte
; GPS sentence buffer, so it does not overlap any existing V11d10b RAM.
G_PRINT_CHOICE        EQU G_RAM+288  ; 0=NO, 1=YES
G_PRINT_NOW           EQU G_RAM+289  ; 0=future entered UTC, 1=current result
G_PRINT_UTC_YEAR      EQU G_RAM+290
G_PRINT_UTC_MONTH     EQU G_RAM+291
G_PRINT_UTC_DAY       EQU G_RAM+292
G_PRINT_UTC_HOUR      EQU G_RAM+293
G_PRINT_UTC_MINUTE    EQU G_RAM+294
G_PRINT_UTC_SECOND    EQU G_RAM+295

; Timestamp captured at the instant the normal object calculation completes.
; This lets a later CURRENT printout report the time that actually belongs to
; the displayed AZ/EL result even if the user has since visited the live clock
; screens, which refresh AST_* from the RTC.
G_CALC_YEAR           EQU G_RAM+296
G_CALC_MONTH          EQU G_RAM+297
G_CALC_DAY            EQU G_RAM+298
G_CALC_HOUR           EQU G_RAM+299
G_CALC_MINUTE         EQU G_RAM+300
G_CALC_SECOND         EQU G_RAM+301

; Save area used only while a future-time print calculation is in progress.
G_PR_SAVE_YEAR        EQU G_RAM+302
G_PR_SAVE_MONTH       EQU G_RAM+303
G_PR_SAVE_DAY         EQU G_RAM+304
G_PR_SAVE_HOUR        EQU G_RAM+305
G_SAVE_MINUTE         EQU G_RAM+306
G_SAVE_SECOND         EQU G_RAM+307
G_SAVE_RISE           EQU G_RAM+308  ; word
G_SAVE_SET            EQU G_RAM+310  ; word
G_SAVE_AZ10           EQU G_RAM+312  ; word
G_SAVE_EL10           EQU G_RAM+314  ; word
G_SAVE_VISIBLE        EQU G_RAM+316
G_SAVE_TRANSIT        EQU G_RAM+317  ; word
G_SAVE_PHASE          EQU G_RAM+319
G_SAVE_PHASE_DIR      EQU G_RAM+320
G_SAVE_MOON_LON       EQU G_RAM+321  ; word
G_SAVE_SUN_LON        EQU G_RAM+323  ; word

; Temporary AST clock save used when converting the captured calculation
; timestamp from local civil time back to UTC for a CURRENT print report.
G_TMP_YEAR            EQU G_RAM+325
G_TMP_MONTH           EQU G_RAM+326
G_TMP_DAY             EQU G_RAM+327
G_TMP_HOUR            EQU G_RAM+328
G_TMP_MINUTE          EQU G_RAM+329
G_TMP_SECOND          EQU G_RAM+330

; V11d11n coarse-to-fine rise/set search scratch.
G_EDU_MIN             EQU G_RAM+331  ; word: current guessed local minute
G_EDU_EL10            EQU G_RAM+333  ; word: signed elevation, tenths deg
G_EDU_COUNT           EQU G_RAM+335  ; byte: safety iteration counter
G_EDU_MODE            EQU G_RAM+336  ; 0=rise, 1=set
G_EDU_STEP            EQU G_RAM+337  ; word: step in minutes
G_EDU_DIR             EQU G_RAM+339  ; 0=forward/add, 1=backward/subtract
G_EDU_PREV_MIN        EQU G_RAM+340  ; word: minute before last trial step
G_EDU_PREV_SIGN       EQU G_RAM+342  ; byte: 0=negative, 1=nonnegative

; Sun constants at 512 coordinate units/AU
G_SUN_AQ        EQU 512
G_SUN_AEQ       EQU 9
G_SUN_BQ        EQU 512
G_SUN_M0        EQU 3560
G_SUN_MI        EQU 9
G_SUN_MF        EQU 8560
G_SUN_MX100     EQU 986
G_SUN_W0        EQU 2829
G_SUN_WR        EQU 5             ; 1e-4 tenth/day

G_H0_PLANET     EQU -324          ; sin(-0.5667 deg) Q15
G_H0_SUN        EQU -476          ; sin(-0.833 deg) Q15
G_H0_MOON       EQU 71            ; sin(+0.125 deg) Q15

; ---------------------------------------------------------------------------
; MAIN USER INTERFACE
; ---------------------------------------------------------------------------
G_ASTRO_MAIN:
G_OBJECT_MENU:
        DI
        XOR A
        LD (G_PROGRESS),A
        LD HL,GMSG_OPTION
        CALL DISPLAY_SHOW
G_OBJECT_WAIT:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JP Z,G_OBJECT_MENU
        CALL KEYCODE_TO_DIGIT
        JP C,G_OBJECT_MENU

        ; 1 Mercury, 2 Venus, 3 Sun, 4 Mars, 5 Jupiter,
        ; 6 Saturn, 7 Uranus, 8 Neptune, 9 Pluto, 0 Moon.
        OR A
        JP Z,G_SELECT_MOON
        CP 1
        JP Z,G_SELECT_MERCURY
        CP 2
        JP Z,G_SELECT_VENUS
        CP 3
        JP Z,G_SELECT_SUN
        CP 4
        JP Z,G_SELECT_MARS
        CP 5
        JP Z,G_SELECT_JUPITER
        CP 6
        JP Z,G_SELECT_SATURN
        CP 7
        JP Z,G_SELECT_URANUS
        CP 8
        JP Z,G_SELECT_NEPTUNE
        CP 9
        JP Z,G_SELECT_PLUTO
        JP G_OBJECT_MENU

G_SELECT_MOON:     LD A,G_OBJ_MOON
                   JR G_STORE_OBJECT
G_SELECT_MERCURY:  LD A,G_OBJ_MERCURY
                   JR G_STORE_OBJECT
G_SELECT_MARS:     LD A,G_OBJ_MARS
                   JR G_STORE_OBJECT
G_SELECT_SUN:      LD A,G_OBJ_SUN
                   JR G_STORE_OBJECT
G_SELECT_VENUS:    LD A,G_OBJ_VENUS
                   JR G_STORE_OBJECT
G_SELECT_JUPITER:  LD A,G_OBJ_JUPITER
                   JR G_STORE_OBJECT
G_SELECT_SATURN:   LD A,G_OBJ_SATURN
                   JR G_STORE_OBJECT
G_SELECT_URANUS:   LD A,G_OBJ_URANUS
                   JR G_STORE_OBJECT
G_SELECT_NEPTUNE:  LD A,G_OBJ_NEPTUNE
                   JR G_STORE_OBJECT
G_SELECT_PLUTO:    LD A,G_OBJ_PLUTO

G_STORE_OBJECT:
        LD (G_OBJECT),A

        ; q2: One-key calculation.  Selecting 0-9 immediately starts the
        ; selected object's calculation; the redundant <OBJECT> ENTER
        ; confirmation screen has been removed.  Keep one stable status
        ; message on the VFD for the entire calculation.
        CALL DISPLAY_CLEAR
        CALL G_PRINT_OBJECT
        LD HL,GMSG_CALC_SUFFIX
        CALL DISPLAY_PRINT_Z

        ; Refresh the clock and perform common preparation while the stable
        ; <OBJECT> CALC message remains displayed.

        ; Refresh the local civil clock from the battery-backed RTC immediately
        ; before calculating the selected object.  GPS synchronized this RTC
        ; after acquisition, so elapsed time since startup is reflected here.
        ; If the RTC read fails, ASTRO_CLOCK_INIT leaves AST_CLOCK_OK=0 and the
        ; existing in-RAM time remains available; do not abort a GPS-valid run.
        CALL ASTRO_CLOCK_INIT
        CALL G_CALC_COMMON

        ; Object-specific work now starts.  Progress dots are added at real
        ; checkpoints, including the midpoint of the event scan.
        ; q2: Progress-star redraws removed.  They added no useful astronomy
        ; information and repeatedly cleared/redrew the VFD.
        XOR A
        LD (G_PROGRESS),A
        CALL G_CALCULATE_SELECTED

        ; Capture the local civil timestamp that belongs to the newly
        ; calculated AZ/EL result before any live RTC display screen can
        ; refresh AST_* later.
        CALL G_CAPTURE_CALC_TIMESTAMP

        ; Audible completion indication.  The timestamp above is captured
        ; first so the roughly half-second chime cannot shift the calculation
        ; time associated with this result.
        CALL CALC_DONE_TUNE

        ; Every completed calculation enters the result carousel with
        ; PRINT defaulting to NO.
        XOR A
        LD (G_PRINT_CHOICE),A

        ; Required completion screen: <OBJECT> VIS / <OBJECT> NOT VIS.
        XOR A
        LD (G_SCREEN),A
        CALL G_DRAW_RESULT_SCREEN

G_RESULT_WAIT:
        ; PRINT is the final screen in every result carousel and accepts
        ; *, # and ENTER rather than ENTER alone.
        CALL G_IS_PRINT_SCREEN
        JP Z,G_PRINT_SCREEN_WAIT

        CALL G_GET_UI_KEY
        CP KEY_ENTER
        JR NZ,G_RESULT_WAIT
        CALL G_ADVANCE_RESULT_SCREEN
        CALL G_DRAW_RESULT_SCREEN
        JR G_RESULT_WAIT

; Z flag set if the current G_SCREEN value is the PRINT screen index for the
; selected object type.  Normal planets use 8, Sun uses 6, Moon uses 7.
G_IS_PRINT_SCREEN:
        LD A,(G_SCREEN)
        LD B,A
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_IPS_SUN
        CP G_OBJ_MOON
        JR Z,G_IPS_MOON
        LD A,B
        CP 8
        RET
G_IPS_SUN:
        LD A,B
        CP 6
        RET
G_IPS_MOON:
        LD A,B
        CP 7
        RET

G_PRINT_SCREEN_WAIT:
        CALL G_GET_UI_KEY
        CP KEY_UTC_NEG                 ; * toggles NO <-> YES
        JR Z,G_PRINT_TOGGLE
        CP KEY_ENTER
        JR NZ,G_PRINT_SCREEN_WAIT

        LD A,(G_PRINT_CHOICE)
        OR A
        JP NZ,G_PRINT_NOW_DIALOG

        ; PRINT NO + ENTER resumes the normal carousel at STATUS.
        CALL G_ADVANCE_RESULT_SCREEN
        CALL G_DRAW_RESULT_SCREEN
        JP G_RESULT_WAIT

G_PRINT_TOGGLE:
        LD A,(G_PRINT_CHOICE)
        XOR 1
        LD (G_PRINT_CHOICE),A
        CALL G_DRAW_PRINT
        JP G_PRINT_SCREEN_WAIT

; CLEAR returns to OPTION menu.  ALPHA is a full software reset.
G_GET_UI_KEY:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        RET NZ
        DI
        LD SP,$FFFE
        JP G_OBJECT_MENU

G_FULL_RESET:
        DI
        LD SP,$FFFE
        JP RESET

; Nonblocking CLEAR/ALPHA check at calculation checkpoints.
G_CALC_ABORT_CHECK:
        CALL KEY_SCAN
        OR A
        RET Z
        LD E,A
        CALL KEY_WAIT_RELEASE
        LD A,E
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        RET NZ
        DI
        LD SP,$FFFE
        JP G_OBJECT_MENU

; CALCULATING, CALCULATING*, ... CALCULATING*****
G_DRAW_PROGRESS:
        CALL DISPLAY_CLEAR
        LD HL,GMSG_CALCULATING
        CALL DISPLAY_PRINT_Z
        LD A,(G_PROGRESS)
        LD B,A
        OR A
        JR Z,G_PROGRESS_KEYS
G_PROGRESS_DOTS:
        LD A,'*'
        CALL DISPLAY_PUT_ASCII
        DJNZ G_PROGRESS_DOTS
G_PROGRESS_KEYS:
        JP G_CALC_ABORT_CHECK

G_PROGRESS_NEXT:
        ; q2: Deliberately no display update.  Retained as a no-op so the
        ; existing calculation checkpoints do not need invasive changes.
        RET

; Common calculations done while the object name remains on the VFD.
G_CALC_COMMON:
        CALL DEBUG_HEADER
        CALL G_REFRESH_RTC_SAFE
        CALL ASTRO_DAY_NUMBER
        CALL G_PREPARE_SUN_BASE
        CALL DEBUG_DATE_STAGE
        RET

; Result-screen sequence.
; Normal planets: STATUS, RISE, SET, AZ, EL, LOCAL DATE/TIME, UTC DATE/TIME, LAT/LON.
; Sun:            STATUS, RISE, SET, LOCAL DATE/TIME, UTC DATE/TIME, LAT/LON.
; Moon:           STATUS, RISE, SET, PHASE, LOCAL DATE/TIME, UTC DATE/TIME, LAT/LON.
G_ADVANCE_RESULT_SCREEN:
        LD A,(G_SCREEN)
        INC A
        LD B,A
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_ADV_SUN
        CP G_OBJ_MOON
        JR Z,G_ADV_MOON
        LD A,B
        CP 9                          ; 0..8, PRINT is screen 8
        JR C,G_ADV_STORE
        XOR A
        JR G_ADV_STORE
G_ADV_SUN:
        LD A,B
        CP 7                          ; 0..6, PRINT is screen 6
        JR C,G_ADV_STORE
        XOR A
        JR G_ADV_STORE
G_ADV_MOON:
        LD A,B
        CP 8                          ; 0..7, PRINT is screen 7
        JR C,G_ADV_STORE
        XOR A
G_ADV_STORE:
        LD (G_SCREEN),A
        RET

G_DRAW_RESULT_SCREEN:
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_DRAW_SUN_RESULT
        CP G_OBJ_MOON
        JR Z,G_DRAW_MOON_RESULT

        LD A,(G_SCREEN)
        OR A
        JP Z,G_DRAW_OBJECT_STATUS
        CP 1
        JP Z,G_DRAW_RISE
        CP 2
        JP Z,G_DRAW_SET
        CP 3
        JP Z,G_DRAW_AZ
        CP 4
        JP Z,G_DRAW_EL
        CP 5
        JP Z,G_DRAW_DATE_TIME
        CP 6
        JP Z,G_DRAW_UTC_DATE_TIME
        CP 7
        JP Z,G_DRAW_LAT_LON
        JP G_DRAW_PRINT

G_DRAW_SUN_RESULT:
        LD A,(G_SCREEN)
        OR A
        JP Z,G_DRAW_OBJECT_STATUS
        CP 1
        JP Z,G_DRAW_RISE
        CP 2
        JP Z,G_DRAW_SET
        CP 3
        JP Z,G_DRAW_DATE_TIME
        CP 4
        JP Z,G_DRAW_UTC_DATE_TIME
        CP 5
        JP Z,G_DRAW_LAT_LON
        JP G_DRAW_PRINT

G_DRAW_MOON_RESULT:
        LD A,(G_SCREEN)
        OR A
        JP Z,G_DRAW_OBJECT_STATUS
        CP 1
        JP Z,G_DRAW_RISE
        CP 2
        JP Z,G_DRAW_SET
        CP 3
        JP Z,G_DRAW_MOON_PHASE
        CP 4
        JP Z,G_DRAW_DATE_TIME
        CP 5
        JP Z,G_DRAW_UTC_DATE_TIME
        CP 6
        JP Z,G_DRAW_LAT_LON
        JP G_DRAW_PRINT

G_DRAW_OBJECT_STATUS:
        CALL DISPLAY_CLEAR
        CALL G_PRINT_OBJECT
        LD A,(AST_VISIBLE)
        OR A
        LD HL,GMSG_NOT_VIS_SUFFIX
        JR Z,G_DOS_WORD
        LD HL,GMSG_VIS_SUFFIX
G_DOS_WORD:
        JP DISPLAY_PRINT_Z

G_DRAW_DATE_TIME:
        ; Refresh from the battery-backed RTC every time this result screen
        ; is entered/cycled to.  On a transient RTC read failure the staged
        ; reader leaves the previously valid AST_* values intact.
        CALL ASTRO_CLOCK_INIT
        CALL DISPLAY_CLEAR
        LD A,(AST_MONTH)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_DAY)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_YEAR)
        CALL DISPLAY_DEC2
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_HOUR)
        CALL DISPLAY_DEC2
        LD A,':'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_MINUTE)
        CALL DISPLAY_DEC2
        LD A,'L'
        JP DISPLAY_PUT_ASCII

G_DRAW_LAT_LON:
        JP G_DRAW_LAT_LON_DYNAMIC

G_DRAW_MOON_PHASE:
        CALL DISPLAY_CLEAR
        LD A,(G_PHASE)
        OR A
        JR Z,G_MPH_NEW
        CP 100
        JR NC,G_MPH_FULL
        LD A,(G_PHASE_DIR)
        OR A
        LD HL,GMSG_WAXING
        JR Z,G_MPH_WORD
        LD HL,GMSG_WANING
G_MPH_WORD:
        CALL DISPLAY_PRINT_Z
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(G_PHASE)
        CALL DISPLAY_DEC2
        LD A,'%'
        JP DISPLAY_PUT_ASCII
G_MPH_NEW:
        LD HL,GMSG_NEW_PHASE
        JP DISPLAY_PRINT_Z
G_MPH_FULL:
        LD HL,GMSG_FULL_PHASE
        JP DISPLAY_PRINT_Z


; ===========================================================================
; V11d11i PRINT WORKFLOW
; ===========================================================================
; The PRINT screen is the last screen in every result carousel.
;
;   PRINT NO
;       * -> PRINT YES
;       # -> PRINT NO
;       ENTER on NO returns to STATUS
;       ENTER on YES enters NOW selection
;
;   NOW YES
;       * -> NOW YES
;       # -> NOW NO
;       ENTER on YES prints the already calculated/current result
;       ENTER on NO asks for a UTC date and time, calculates that instant
;       temporarily, and prints it without permanently replacing the current
;       displayed result.
;
; CLEAR remains globally meaningful while in the yes/no screens because they
; use G_GET_UI_KEY.  Future DATE/TIME entry explicitly returns C on CLEAR so
; the print workflow can be cancelled back to the PRINT screen.
; ---------------------------------------------------------------------------

G_DRAW_PRINT:
        LD A,(G_PRINT_CHOICE)
        OR A
        LD HL,GMSG_PRINT_NO_HELP
        JR Z,G_DP_SHOW
        LD HL,GMSG_PRINT_YES_HELP
G_DP_SHOW:
        JP DISPLAY_SHOW

G_PRINT_NOW_DIALOG:
        LD A,1
        LD (G_PRINT_NOW),A
G_PRINT_NOW_REDRAW:
        LD A,(G_PRINT_NOW)
        OR A
        LD HL,GMSG_NOW_NO_HELP
        JR Z,G_PND_SHOW
        LD HL,GMSG_NOW_YES_HELP
G_PND_SHOW:
        CALL DISPLAY_SHOW

G_PRINT_NOW_WAIT:
        CALL G_GET_UI_KEY
        CP KEY_UTC_NEG                 ; * toggles NO <-> YES
        JR Z,G_PND_TOGGLE
        CP KEY_ENTER
        JR NZ,G_PRINT_NOW_WAIT

        LD A,(G_PRINT_NOW)
        OR A
        JP Z,G_PRINT_FUTURE
        JP G_PRINT_CURRENT

G_PND_TOGGLE:
        LD A,(G_PRINT_NOW)
        XOR 1
        LD (G_PRINT_NOW),A
        JR G_PRINT_NOW_REDRAW

; ---------------------------------------------------------------------------
; CURRENT print
; ---------------------------------------------------------------------------
G_PRINT_CURRENT:
        ; Build UTC from the timestamp captured at calculation completion,
        ; not from the potentially newer live RTC display time.
        CALL G_BUILD_CURRENT_PRINT_UTC
        CALL G_PRINT_REPORT_AND_FINISH

        ; A completed print is a finished transaction.  Reset PRINT to NO so
        ; the next trip through the result carousel never inherits YES from
        ; the previous print request.
        XOR A
        LD (G_PRINT_CHOICE),A

        ; After printing, return to the first result/status screen, e.g.
        ; "JUPITER VIS", rather than returning to the PRINT screen.
        LD (G_SCREEN),A
        CALL G_DRAW_RESULT_SCREEN
        JP G_RESULT_WAIT

; Convert G_CALC_* local civil time to UTC while preserving the live AST clock.
G_BUILD_CURRENT_PRINT_UTC:
        CALL G_SAVE_AST_CLOCK_TEMP

        LD A,(G_CALC_YEAR)
        LD (AST_YEAR),A
        LD A,(G_CALC_MONTH)
        LD (AST_MONTH),A
        LD A,(G_CALC_DAY)
        LD (AST_DAY),A
        LD A,(G_CALC_HOUR)
        LD (AST_HOUR),A
        LD A,(G_CALC_MINUTE)
        LD (AST_MINUTE),A
        LD A,(G_CALC_SECOND)
        LD (AST_SECOND),A

        CALL G_RTC_LOCAL_TO_UTC
        CALL G_COPY_GPS_UTC_TO_PRINT
        CALL G_RESTORE_AST_CLOCK_TEMP
        RET

G_CAPTURE_CALC_TIMESTAMP:
        LD A,(AST_YEAR)
        LD (G_CALC_YEAR),A
        LD A,(AST_MONTH)
        LD (G_CALC_MONTH),A
        LD A,(AST_DAY)
        LD (G_CALC_DAY),A
        LD A,(AST_HOUR)
        LD (G_CALC_HOUR),A
        LD A,(AST_MINUTE)
        LD (G_CALC_MINUTE),A
        LD A,(AST_SECOND)
        LD (G_CALC_SECOND),A
        RET

G_SAVE_AST_CLOCK_TEMP:
        LD A,(AST_YEAR)
        LD (G_TMP_YEAR),A
        LD A,(AST_MONTH)
        LD (G_TMP_MONTH),A
        LD A,(AST_DAY)
        LD (G_TMP_DAY),A
        LD A,(AST_HOUR)
        LD (G_TMP_HOUR),A
        LD A,(AST_MINUTE)
        LD (G_TMP_MINUTE),A
        LD A,(AST_SECOND)
        LD (G_TMP_SECOND),A
        RET

G_RESTORE_AST_CLOCK_TEMP:
        LD A,(G_TMP_YEAR)
        LD (AST_YEAR),A
        LD A,(G_TMP_MONTH)
        LD (AST_MONTH),A
        LD A,(G_TMP_DAY)
        LD (AST_DAY),A
        LD A,(G_TMP_HOUR)
        LD (AST_HOUR),A
        LD A,(G_TMP_MINUTE)
        LD (AST_MINUTE),A
        LD A,(G_TMP_SECOND)
        LD (AST_SECOND),A
        RET

; ---------------------------------------------------------------------------
; FUTURE print
; ---------------------------------------------------------------------------
G_PRINT_FUTURE:
        CALL G_SAVE_CURRENT_RESULT

G_PF_DATE:
        XOR A
        LD (AST_INPUT_MODE),A
        CALL G_PRINT_READ_SIX
        JR C,G_PF_CANCEL
        CALL ASI_PARSE_DATE
        JR C,G_PF_DATE

        LD A,(AST_YEAR)
        LD (G_PRINT_UTC_YEAR),A
        LD A,(AST_MONTH)
        LD (G_PRINT_UTC_MONTH),A
        LD A,(AST_DAY)
        LD (G_PRINT_UTC_DAY),A

G_PF_TIME:
        LD A,1
        LD (AST_INPUT_MODE),A
        CALL G_PRINT_READ_SIX
        JR C,G_PF_CANCEL
        CALL ASI_PARSE_TIME
        JR C,G_PF_TIME

        LD A,(AST_HOUR)
        LD (G_PRINT_UTC_HOUR),A
        LD A,(AST_MINUTE)
        LD (G_PRINT_UTC_MINUTE),A
        LD A,(AST_SECOND)
        LD (G_PRINT_UTC_SECOND),A

        ; Convert entered UTC to local civil time using the already selected
        ; runtime UTC offset.  GPS_APPLY_OFFSET_TO_LOCAL only changes RAM; it
        ; does not write the RTC.
        CALL G_COPY_PRINT_UTC_TO_GPS
        CALL GPS_APPLY_OFFSET_TO_LOCAL

        ; Calculate the requested future instant using the current GPS site.
        ; Do not call G_CAPTURE_CALC_TIMESTAMP here: the normal current result
        ; must retain its original calculation timestamp.
        XOR A
        LD (G_PROGRESS),A
        CALL G_DRAW_PROGRESS
        CALL G_CALC_COMMON
        CALL G_CALCULATE_SELECTED

        ; Future-print calculations get the same audible completion indication
        ; as normal/current calculations.
        CALL CALC_DONE_TUNE

        ; Future calculation is complete: print immediately.  There is no
        ; intermediate ENTER 2 PRINT confirmation screen.
        ; Reassert the entered UTC timestamp in case the calculation used
        ; GPS_UTC_* as scratch.
        CALL G_COPY_PRINT_UTC_TO_GPS
        CALL G_PRINT_REPORT_AND_FINISH

        ; Put the original current result back exactly as it was before the
        ; temporary future calculation, then return to its first STATUS screen
        ; (for example "JUPITER VIS").
        CALL G_RESTORE_CURRENT_RESULT

        ; Just like a CURRENT print, a completed FUTURE print must not leave
        ; the next PRINT screen defaulting to YES.
        XOR A
        LD (G_PRINT_CHOICE),A
        LD (G_SCREEN),A
        CALL G_DRAW_RESULT_SCREEN
        JP G_RESULT_WAIT

G_PF_CANCEL:
        CALL G_RESTORE_CURRENT_RESULT
        CALL G_DRAW_PRINT
        JP G_PRINT_SCREEN_WAIT

; Print-specific six-digit entry.
; Uses DATE MM/DD/YY U or TIME HH/MM/SS U presentation.
; ENTER is accepted only after six digits.
; BACKSPACE removes a digit.
; CLEAR cancels the print workflow and returns with carry set.
G_PRINT_READ_SIX:
        XOR A
        LD (AST_INCOUNT),A

G_PRS_REDRAW:
        CALL DISPLAY_CLEAR
        LD A,(AST_INPUT_MODE)
        OR A
        JR NZ,G_PRS_TIME
        LD HL,MSG_DATE_PREFIX
        CALL DISPLAY_PRINT_Z
        LD HL,MSG_DATE_MASK
        JR G_PRS_FORMAT
G_PRS_TIME:
        LD HL,MSG_TIME_PREFIX
        CALL DISPLAY_PRINT_Z
        LD HL,MSG_START_TIME_MASK
G_PRS_FORMAT:
        LD DE,AST_INPUT
        LD A,(AST_INCOUNT)
        LD (AST_TMP5),A
        LD B,8
G_PRS_CHAR:
        LD A,(HL)
        CP '/'
        JR Z,G_PRS_LITERAL
        LD A,(AST_TMP5)
        OR A
        JR Z,G_PRS_MASK
        LD A,(DE)
        ADD A,'0'
        INC DE
        LD C,A
        LD A,(AST_TMP5)
        DEC A
        LD (AST_TMP5),A
        LD A,C
        JR G_PRS_PUT
G_PRS_MASK:
        LD A,(HL)
        JR G_PRS_PUT
G_PRS_LITERAL:
        LD A,'/'
G_PRS_PUT:
        PUSH BC
        PUSH DE
        PUSH HL
        CALL DISPLAY_PUT_ASCII
        POP HL
        POP DE
        POP BC
        INC HL
        DJNZ G_PRS_CHAR

        ; Explicit U suffix: future entry is always UTC.
        LD A,'U'
        CALL DISPLAY_PUT_ASCII

G_PRS_KEY:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JR Z,G_PRS_CANCEL
        CP KEY_BACKSPACE
        JR Z,G_PRS_BACK
        CP KEY_ENTER
        JR Z,G_PRS_ENTER
        CALL KEYCODE_TO_DIGIT
        JR C,G_PRS_KEY

        LD C,A
        LD A,(AST_INCOUNT)
        CP 6
        JR NC,G_PRS_KEY
        LD E,A
        LD D,0
        LD HL,AST_INPUT
        ADD HL,DE
        LD (HL),C
        LD A,E
        INC A
        LD (AST_INCOUNT),A
        JP G_PRS_REDRAW

G_PRS_BACK:
        LD A,(AST_INCOUNT)
        OR A
        JR Z,G_PRS_KEY
        DEC A
        LD (AST_INCOUNT),A
        JP G_PRS_REDRAW

G_PRS_ENTER:
        LD A,(AST_INCOUNT)
        CP 6
        JR NZ,G_PRS_KEY
        OR A                            ; clear carry
        RET
G_PRS_CANCEL:
        SCF
        RET

G_SAVE_CURRENT_RESULT:
        LD A,(AST_YEAR)
        LD (G_PR_SAVE_YEAR),A
        LD A,(AST_MONTH)
        LD (G_PR_SAVE_MONTH),A
        LD A,(AST_DAY)
        LD (G_PR_SAVE_DAY),A
        LD A,(AST_HOUR)
        LD (G_PR_SAVE_HOUR),A
        LD A,(AST_MINUTE)
        LD (G_SAVE_MINUTE),A
        LD A,(AST_SECOND)
        LD (G_SAVE_SECOND),A
        LD HL,(AST_RISE)
        LD (G_SAVE_RISE),HL
        LD HL,(AST_SET)
        LD (G_SAVE_SET),HL
        LD HL,(AST_AZ10)
        LD (G_SAVE_AZ10),HL
        LD HL,(AST_EL10)
        LD (G_SAVE_EL10),HL
        LD A,(AST_VISIBLE)
        LD (G_SAVE_VISIBLE),A
        LD A,(G_PHASE)
        LD (G_SAVE_PHASE),A
        LD A,(G_PHASE_DIR)
        LD (G_SAVE_PHASE_DIR),A
        LD HL,(G_MOON_LON)
        LD (G_SAVE_MOON_LON),HL
        LD HL,(G_SUN_LON)
        LD (G_SAVE_SUN_LON),HL
        RET

G_RESTORE_CURRENT_RESULT:
        LD A,(G_PR_SAVE_YEAR)
        LD (AST_YEAR),A
        LD A,(G_PR_SAVE_MONTH)
        LD (AST_MONTH),A
        LD A,(G_PR_SAVE_DAY)
        LD (AST_DAY),A
        LD A,(G_PR_SAVE_HOUR)
        LD (AST_HOUR),A
        LD A,(G_SAVE_MINUTE)
        LD (AST_MINUTE),A
        LD A,(G_SAVE_SECOND)
        LD (AST_SECOND),A
        LD HL,(G_SAVE_RISE)
        LD (AST_RISE),HL
        LD HL,(G_SAVE_SET)
        LD (AST_SET),HL
        LD HL,(G_SAVE_AZ10)
        LD (AST_AZ10),HL
        LD HL,(G_SAVE_EL10)
        LD (AST_EL10),HL
        LD A,(G_SAVE_VISIBLE)
        LD (AST_VISIBLE),A
        LD A,(G_SAVE_PHASE)
        LD (G_PHASE),A
        LD A,(G_SAVE_PHASE_DIR)
        LD (G_PHASE_DIR),A
        LD HL,(G_SAVE_MOON_LON)
        LD (G_MOON_LON),HL
        LD HL,(G_SAVE_SUN_LON)
        LD (G_SUN_LON),HL
        RET

G_COPY_GPS_UTC_TO_PRINT:
        LD A,(GPS_UTC_YEAR)
        LD (G_PRINT_UTC_YEAR),A
        LD A,(GPS_UTC_MONTH)
        LD (G_PRINT_UTC_MONTH),A
        LD A,(GPS_UTC_DAY)
        LD (G_PRINT_UTC_DAY),A
        LD A,(GPS_UTC_HOUR)
        LD (G_PRINT_UTC_HOUR),A
        LD A,(GPS_UTC_MINUTE)
        LD (G_PRINT_UTC_MINUTE),A
        LD A,(GPS_UTC_SECOND)
        LD (G_PRINT_UTC_SECOND),A
        RET

G_COPY_PRINT_UTC_TO_GPS:
        LD A,(G_PRINT_UTC_YEAR)
        LD (GPS_UTC_YEAR),A
        LD A,(G_PRINT_UTC_MONTH)
        LD (GPS_UTC_MONTH),A
        LD A,(G_PRINT_UTC_DAY)
        LD (GPS_UTC_DAY),A
        LD A,(G_PRINT_UTC_HOUR)
        LD (GPS_UTC_HOUR),A
        LD A,(G_PRINT_UTC_MINUTE)
        LD (GPS_UTC_MINUTE),A
        LD A,(G_PRINT_UTC_SECOND)
        LD (GPS_UTC_SECOND),A
        RET

; ---------------------------------------------------------------------------
; Printer serial layer.
;
; IMPORTANT: the rear TRANZ serial connector used by our proven GPS/PC bridge
; is DART B ($22 data / $23 control).  DART A is the internal modem/debug path
; and must NOT be used for the external Printer 250.
;
; DART B is already initialized at startup for the hardware-proven 9600 8-N-1
; GPS link.  Printing therefore uses only the DART-B transmitter; no baud-rate
; or CTC reconfiguration is needed.  GPS acquisition is complete before the
; print UI can be reached, so transmitting a report cannot disturb an active
; startup acquisition.
;
; A short inter-character delay is provided so a report remains conservative
; even if hardware flow control is not present in the particular printer cable.
; ---------------------------------------------------------------------------
; ===========================================================================
; r22: Centered Jolly Wrencher 113x56 at start of astronomy report.
; Original PC-tested transmission protocol: CAN, FS, ESC g; 13 blanks + 10 odd + $24,
; 13 blanks + 10 even + $21 per row, 150ms after each pass, CAN to exit.
; Bitmap rows are bottom-up to match the PC-tested BMP sender.
; G_PRN_TX_CHAR already paces every byte by approximately 12ms.
; ===========================================================================
G_PRN_JOLLY_WRENCHER:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL
        LD A,$18
        CALL G_PRN_TX_CHAR
        LD A,$1C
        CALL G_PRN_TX_CHAR
        LD A,$1B
        CALL G_PRN_TX_CHAR
        LD A,$67
        CALL G_PRN_TX_CHAR
        LD HL,G_JW_BITMAP
        LD C,56
G_JW_ROW:
        CALL G_JW_LEFT_MARGIN
        LD B,10
G_JW_ODD:
        LD A,(HL)
        CALL G_PRN_TX_CHAR
        INC HL
        DJNZ G_JW_ODD
        LD A,$24
        CALL G_PRN_TX_CHAR
        CALL G_JW_PASS_PAUSE
        CALL G_JW_LEFT_MARGIN
        LD B,10
G_JW_EVEN:
        LD A,(HL)
        CALL G_PRN_TX_CHAR
        INC HL
        DJNZ G_JW_EVEN
        LD A,$21
        CALL G_PRN_TX_CHAR
        CALL G_JW_PASS_PAUSE
        DEC C
        JR NZ,G_JW_ROW
        LD A,$18
        CALL G_PRN_TX_CHAR
        POP HL
        POP DE
        POP BC
        POP AF
        RET

; 13 blank six-dot characters per pass = 78 positions per pass,
; or 156 horizontal dots across the interleaved 420-dot print width.
; 113-pixel image: left 156 dots, right 151 dots (within 2.5 dots of center).
; Uses $40 as blank graphics data; no bitmap expansion required.
G_JW_LEFT_MARGIN:
        PUSH BC
        LD B,13
G_JW_MARGIN_LOOP:
        LD A,$40
        CALL G_PRN_TX_CHAR
        DJNZ G_JW_MARGIN_LOOP
        POP BC
        RET

G_JW_PASS_PAUSE:
        PUSH BC
        LD B,75
G_JW_PAUSE_LOOP:
        CALL DELAY_2MS
        DJNZ G_JW_PAUSE_LOOP
        POP BC
        RET

G_JW_BITMAP:
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$47,$40,$40,$40,$40,$40,$47,$40,$40 ; row odd
        DB $40,$4F,$40,$40,$40,$40,$40,$4F,$40,$40 ; row even
        DB $40,$43,$70,$40,$40,$40,$40,$5E,$40,$40 ; row odd
        DB $40,$47,$60,$40,$40,$40,$40,$5E,$40,$40 ; row even
        DB $40,$41,$70,$40,$40,$40,$40,$5C,$40,$40 ; row odd
        DB $40,$43,$70,$40,$40,$40,$40,$7C,$40,$40 ; row even
        DB $40,$41,$78,$40,$40,$40,$40,$7C,$40,$40 ; row odd
        DB $40,$41,$70,$40,$40,$40,$40,$78,$40,$40 ; row even
        DB $40,$43,$78,$40,$40,$40,$40,$7E,$40,$40 ; row odd
        DB $40,$43,$78,$40,$40,$40,$41,$7C,$40,$40 ; row even
        DB $48,$43,$78,$40,$40,$40,$40,$7E,$40,$60 ; row odd
        DB $40,$47,$78,$40,$40,$40,$41,$7E,$40,$40 ; row even
        DB $4C,$47,$78,$40,$40,$40,$40,$7F,$41,$60 ; row odd
        DB $4C,$4F,$78,$40,$40,$40,$41,$7F,$43,$40 ; row even
        DB $46,$4F,$7C,$40,$40,$40,$41,$7F,$63,$40 ; row odd
        DB $4E,$5F,$78,$40,$40,$40,$41,$7F,$67,$40 ; row even
        DB $47,$5F,$7E,$40,$40,$40,$43,$7F,$77,$40 ; row odd
        DB $4F,$7F,$7C,$40,$40,$40,$43,$7F,$7F,$40 ; row even
        DB $43,$7F,$7F,$40,$40,$40,$47,$7F,$7E,$40 ; row odd
        DB $47,$7F,$7F,$40,$40,$40,$4F,$7F,$7E,$40 ; row even
        DB $43,$7F,$7F,$60,$4F,$60,$4F,$7F,$7E,$40 ; row odd
        DB $43,$7F,$7F,$60,$4F,$40,$5F,$7F,$7C,$40 ; row even
        DB $40,$7F,$7F,$71,$7F,$7C,$5F,$7F,$78,$40 ; row odd
        DB $40,$7F,$7F,$71,$7F,$78,$7F,$7F,$78,$40 ; row even
        DB $40,$40,$7F,$63,$7F,$7E,$4F,$78,$40,$40 ; row odd
        DB $40,$41,$7F,$67,$7F,$7E,$5F,$78,$40,$40 ; row even
        DB $40,$40,$5F,$4F,$7F,$7F,$67,$70,$40,$40 ; row odd
        DB $40,$40,$7F,$4F,$7F,$7F,$4F,$70,$40,$40 ; row even
        DB $40,$40,$4F,$4F,$7F,$7F,$63,$60,$40,$40 ; row odd
        DB $40,$40,$5E,$5F,$7F,$7F,$67,$60,$40,$40 ; row even
        DB $40,$40,$46,$5F,$7F,$7F,$73,$40,$40,$40 ; row odd
        DB $40,$40,$4C,$7F,$7F,$7F,$73,$40,$40,$40 ; row even
        DB $40,$40,$40,$7F,$7F,$7F,$78,$40,$40,$40 ; row odd
        DB $40,$40,$40,$7F,$7F,$7F,$70,$40,$40,$40 ; row even
        DB $40,$40,$40,$7F,$7F,$7F,$78,$40,$40,$40 ; row odd
        DB $40,$40,$41,$7F,$7F,$7F,$78,$40,$40,$40 ; row even
        DB $40,$40,$41,$7F,$7F,$7F,$7C,$40,$40,$40 ; row odd
        DB $40,$40,$41,$7F,$7F,$7F,$78,$40,$40,$40 ; row even
        DB $40,$40,$41,$7F,$7F,$7F,$7C,$40,$40,$40 ; row odd
        DB $40,$40,$43,$7F,$7F,$7F,$7C,$40,$40,$40 ; row even
        DB $40,$40,$41,$78,$5F,$70,$7C,$40,$40,$40 ; row odd
        DB $40,$40,$43,$78,$5F,$61,$7C,$40,$40,$40 ; row even
        DB $40,$40,$43,$70,$4F,$60,$5E,$40,$40,$40 ; row odd
        DB $40,$40,$43,$70,$4F,$40,$7C,$40,$40,$40 ; row even
        DB $40,$40,$43,$70,$47,$40,$5E,$40,$40,$40 ; row odd
        DB $40,$40,$43,$60,$4F,$40,$5C,$40,$40,$40 ; row even
        DB $40,$40,$43,$60,$4F,$60,$4E,$40,$40,$40 ; row odd
        DB $40,$40,$43,$60,$4F,$40,$5C,$40,$40,$40 ; row even
        DB $40,$40,$43,$60,$4F,$60,$4E,$40,$40,$40 ; row odd
        DB $40,$40,$43,$60,$5F,$60,$5C,$40,$40,$40 ; row even
        DB $40,$40,$43,$60,$7F,$78,$4E,$40,$40,$40 ; row odd
        DB $40,$40,$43,$61,$7F,$78,$5C,$40,$40,$40 ; row even
        DB $40,$40,$43,$73,$7F,$7E,$5E,$40,$40,$40 ; row odd
        DB $40,$40,$43,$63,$7F,$7C,$5C,$40,$40,$40 ; row even
        DB $40,$40,$41,$7B,$7D,$7E,$7C,$40,$40,$40 ; row odd
        DB $40,$40,$43,$77,$7B,$7E,$7C,$40,$40,$40 ; row even
        DB $40,$40,$41,$7F,$79,$7F,$7C,$40,$40,$40 ; row odd
        DB $40,$40,$43,$7F,$79,$7F,$7C,$40,$40,$40 ; row even
        DB $40,$40,$41,$7F,$78,$7F,$7C,$40,$40,$40 ; row odd
        DB $40,$40,$41,$7F,$79,$7F,$78,$40,$40,$40 ; row even
        DB $40,$40,$44,$7F,$7A,$7F,$79,$40,$40,$40 ; row odd
        DB $40,$40,$4D,$7F,$79,$7F,$7B,$40,$40,$40 ; row even
        DB $40,$40,$4E,$7F,$7A,$7F,$7B,$60,$40,$40 ; row odd
        DB $40,$40,$5C,$7F,$7F,$7F,$73,$60,$40,$40 ; row even
        DB $40,$40,$5E,$5F,$7F,$7F,$73,$70,$40,$40 ; row odd
        DB $40,$40,$7E,$5F,$7F,$7F,$67,$70,$40,$40 ; row even
        DB $40,$41,$7F,$4F,$7F,$7F,$67,$7C,$40,$40 ; row odd
        DB $40,$41,$7E,$5F,$7F,$7F,$67,$78,$40,$40 ; row even
        DB $40,$7F,$7F,$67,$7F,$7F,$4F,$7F,$78,$40 ; row odd
        DB $41,$7F,$7F,$47,$7F,$7E,$4F,$7F,$78,$40 ; row even
        DB $43,$7F,$7F,$67,$7F,$7F,$4F,$7F,$7E,$40 ; row odd
        DB $43,$7F,$7F,$67,$7F,$7E,$5F,$7F,$7C,$40 ; row even
        DB $43,$7F,$7F,$47,$7F,$7F,$47,$7F,$7E,$40 ; row odd
        DB $47,$7F,$7F,$47,$6F,$5E,$4F,$7F,$7E,$40 ; row even
        DB $47,$5F,$7E,$43,$67,$4E,$43,$7F,$77,$40 ; row odd
        DB $4F,$7F,$7C,$47,$6F,$5E,$43,$7F,$7F,$40 ; row even
        DB $46,$4F,$7C,$40,$40,$40,$41,$7F,$63,$40 ; row odd
        DB $4E,$5F,$78,$40,$40,$40,$41,$7F,$67,$40 ; row even
        DB $4C,$47,$78,$40,$40,$40,$40,$7F,$41,$60 ; row odd
        DB $4C,$4F,$78,$40,$40,$40,$41,$7F,$43,$40 ; row even
        DB $48,$43,$78,$40,$40,$40,$40,$7E,$40,$60 ; row odd
        DB $40,$47,$78,$40,$40,$40,$41,$7E,$40,$40 ; row even
        DB $40,$41,$78,$40,$40,$40,$40,$7C,$40,$40 ; row odd
        DB $40,$43,$78,$40,$40,$40,$41,$7C,$40,$40 ; row even
        DB $40,$41,$78,$40,$40,$40,$40,$7C,$40,$40 ; row odd
        DB $40,$41,$70,$40,$40,$40,$40,$78,$40,$40 ; row even
        DB $40,$41,$70,$40,$40,$40,$40,$5C,$40,$40 ; row odd
        DB $40,$43,$70,$40,$40,$40,$40,$7C,$40,$40 ; row even
        DB $40,$43,$70,$40,$40,$40,$40,$5E,$40,$40 ; row odd
        DB $40,$47,$60,$40,$40,$40,$40,$5E,$40,$40 ; row even
        DB $40,$4F,$40,$40,$40,$40,$40,$47,$60,$40 ; row odd
        DB $40,$4F,$40,$40,$40,$40,$40,$4F,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row odd
        DB $40,$40,$40,$40,$40,$40,$40,$40,$40,$40 ; row even

G_PRINTER_INIT:
        ; DART B is already 9600 8-N-1 and TX-enabled by DEBUG_DART_INIT.
        RET

G_PRINTER_RESTORE_DEBUG:
        ; Nothing was reconfigured; leave the proven GPS/DART-B setup intact.
        RET

G_PRN_TX_CHAR:
        PUSH BC
        LD B,A
G_PRN_TX_WAIT:
        IN A,(DART_B_CTRL)
        AND $04
        JR Z,G_PRN_TX_WAIT
        LD A,B
        OUT (DART_B_DATA),A

        ; Approximately 12 ms pacing at the firmware's nominal DELAY_2MS.
        LD B,6
G_PRN_PACE:
        CALL DELAY_2MS
        DJNZ G_PRN_PACE
        POP BC
        RET

G_PRN_PRINT_Z:
        PUSH AF
        PUSH HL
G_PRN_PZ_LOOP:
        LD A,(HL)
        OR A
        JR Z,G_PRN_PZ_DONE
        CALL G_PRN_TX_CHAR
        INC HL
        JR G_PRN_PZ_LOOP
G_PRN_PZ_DONE:
        POP HL
        POP AF
        RET

G_PRN_CRLF:
        LD A,13
        CALL G_PRN_TX_CHAR
        LD A,10
        CALL G_PRN_TX_CHAR

        ; Extra end-of-line settling pause: 200 x nominal 2 ms = ~400 ms.
        ; Existing per-character pacing in G_PRN_TX_CHAR is unchanged.
        PUSH BC
        LD B,200              ; 200 x nominal 2 ms = ~400 ms
G_PRN_EOL_PAUSE:
        CALL DELAY_2MS
        DJNZ G_PRN_EOL_PAUSE
        POP BC
        RET

; A=0..99, print exactly two decimal digits.
G_PRN_DEC2:
        PUSH BC
        LD B,'0'
G_PD2_LOOP:
        CP 10
        JR C,G_PD2_DONE
        SUB 10
        INC B
        JR G_PD2_LOOP
G_PD2_DONE:
        LD C,A
        LD A,B
        CALL G_PRN_TX_CHAR
        LD A,C
        ADD A,'0'
        CALL G_PRN_TX_CHAR
        POP BC
        RET

; HL=0..999, print exactly three decimal digits.
G_PRN_DEC3:
        PUSH BC
        PUSH DE
        LD DE,100
        CALL G_PRN_DIGIT
        LD DE,10
        CALL G_PRN_DIGIT
        LD A,L
        ADD A,'0'
        CALL G_PRN_TX_CHAR
        POP DE
        POP BC
        RET

; Helper for fixed decimal digit, HL value and DE divisor.
G_PRN_DIGIT:
        LD B,'0'
G_PRN_DIGIT_LOOP:
        OR A
        SBC HL,DE
        JR C,G_PRN_DIGIT_DONE
        INC B
        JR G_PRN_DIGIT_LOOP
G_PRN_DIGIT_DONE:
        ADD HL,DE
        LD A,B
        JP G_PRN_TX_CHAR

; HL unsigned 0..999, print without leading zeroes.
G_PRN_U16_TRIM3:
        PUSH BC
        PUSH DE
        LD B,0
        LD DE,100
G_PUT3_HUND_LOOP:
        OR A
        SBC HL,DE
        JR C,G_PUT3_HUND_DONE
        INC B
        JR G_PUT3_HUND_LOOP
G_PUT3_HUND_DONE:
        ADD HL,DE
        LD A,B
        OR A
        JR Z,G_PUT3_TENS
        ADD A,'0'
        CALL G_PRN_TX_CHAR
        LD B,1                         ; hundreds already emitted

G_PUT3_TENS:
        LD C,0
        LD DE,10
G_PUT3_TENS_LOOP:
        OR A
        SBC HL,DE
        JR C,G_PUT3_TENS_DONE
        INC C
        JR G_PUT3_TENS_LOOP
G_PUT3_TENS_DONE:
        ADD HL,DE
        LD A,B
        OR A
        JR NZ,G_PUT3_EMIT_TENS
        LD A,C
        OR A
        JR Z,G_PUT3_ONES
G_PUT3_EMIT_TENS:
        LD A,C
        ADD A,'0'
        CALL G_PRN_TX_CHAR
G_PUT3_ONES:
        LD A,L
        ADD A,'0'
        CALL G_PRN_TX_CHAR
        POP DE
        POP BC
        RET

; HL=angle in tenths.  Print unsigned degrees with one decimal.
G_PRN_ANGLE10:
        CALL ASTRO_DIVU10              ; HL=integer, DE=remainder 0..9
        PUSH DE
        CALL G_PRN_U16_TRIM3
        LD A,'.'
        CALL G_PRN_TX_CHAR
        POP DE
        LD A,E
        ADD A,'0'
        JP G_PRN_TX_CHAR

; HL=signed elevation in tenths.  Print explicit +/- sign and one decimal.
G_PRN_SIGNED_ANGLE10:
        BIT 7,H
        JR Z,G_PSA_POS
        LD A,'-'
        CALL G_PRN_TX_CHAR
        CALL ASTRO_NEG_HL
        JP G_PRN_ANGLE10
G_PSA_POS:
        LD A,'+'
        CALL G_PRN_TX_CHAR
        JP G_PRN_ANGLE10

; Print compass sector corresponding to unsigned AZ10 in HL.
G_PRN_COMPASS16:
        LD DE,112
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD B,0
        LD DE,225
G_PCOMP_DIV:
        OR A
        SBC HL,DE
        JR C,G_PCOMP_DONE
        INC B
        JR G_PCOMP_DIV
G_PCOMP_DONE:
        LD A,B
        AND $0F
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_COMPASS_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP G_PRN_PRINT_Z

; Select one of the eight traditional phase names from corrected Moon-Sun
; elongation.  Boundaries are 22.5-degree half-sector points.
G_PRN_MOON_PHASE_NAME:
        LD HL,(G_MOON_LON)
        LD DE,(G_SUN_LON)
        OR A
        SBC HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW0),HL

        LD DE,225
        OR A
        SBC HL,DE
        JR C,G_PMP_NEW

        LD HL,(G_TMPW0)
        LD DE,675
        OR A
        SBC HL,DE
        JR C,G_PMP_WAX_CRES

        LD HL,(G_TMPW0)
        LD DE,1125
        OR A
        SBC HL,DE
        JR C,G_PMP_FIRST

        LD HL,(G_TMPW0)
        LD DE,1575
        OR A
        SBC HL,DE
        JR C,G_PMP_WAX_GIB

        LD HL,(G_TMPW0)
        LD DE,2025
        OR A
        SBC HL,DE
        JR C,G_PMP_FULL

        LD HL,(G_TMPW0)
        LD DE,2475
        OR A
        SBC HL,DE
        JR C,G_PMP_WAN_GIB

        LD HL,(G_TMPW0)
        LD DE,2925
        OR A
        SBC HL,DE
        JR C,G_PMP_LAST

        LD HL,(G_TMPW0)
        LD DE,3375
        OR A
        SBC HL,DE
        JR C,G_PMP_WAN_CRES
G_PMP_NEW:
        LD HL,GPRN_PHASE_NEW
        JP G_PRN_PRINT_Z
G_PMP_WAX_CRES:
        LD HL,GPRN_PHASE_WAX_CRES
        JP G_PRN_PRINT_Z
G_PMP_FIRST:
        LD HL,GPRN_PHASE_FIRST
        JP G_PRN_PRINT_Z
G_PMP_WAX_GIB:
        LD HL,GPRN_PHASE_WAX_GIB
        JP G_PRN_PRINT_Z
G_PMP_FULL:
        LD HL,GPRN_PHASE_FULL
        JP G_PRN_PRINT_Z
G_PMP_WAN_GIB:
        LD HL,GPRN_PHASE_WAN_GIB
        JP G_PRN_PRINT_Z
G_PMP_LAST:
        LD HL,GPRN_PHASE_LAST
        JP G_PRN_PRINT_Z
G_PMP_WAN_CRES:
        LD HL,GPRN_PHASE_WAN_CRES
        JP G_PRN_PRINT_Z

; ---------------------------------------------------------------------------
; Build and send the complete 42-column-friendly report.
; ---------------------------------------------------------------------------
G_PRINT_REPORT_AND_FINISH:
        LD HL,GMSG_PRINTING
        CALL DISPLAY_SHOW
        CALL G_PRINTER_INIT
        ; Printer 250 CAN ($18): discard any buffered startup garbage.
        ; Send before every report, prior to the first printable byte.
        LD A,$18
        CALL G_PRN_TX_CHAR

        ; Print the PC-proven Jolly Wrencher before the report heading.
        CALL G_PRN_JOLLY_WRENCHER
        CALL G_PRN_CRLF

        ; Object heading: centered on its own 42-column line.
        CALL G_PRN_CENTER_OBJECT
        CALL G_PRN_CRLF

        ; WILL BE [NOT ]VISIBLE FOR LOCATION
        LD A,(AST_VISIBLE)
        OR A
        LD HL,GPRN_NOT_VISIBLE_LOC
        JR Z,G_PRR_VIS_WORD
        LD HL,GPRN_VISIBLE_LOC
G_PRR_VIS_WORD:
        CALL G_PRN_PRINT_Z
        CALL G_PRN_CRLF

        ; LAT: DD.DDD N   LON: DDD.DDD W
        LD HL,GPRN_LAT
        CALL G_PRN_PRINT_Z
        LD A,(GPS_SITE_LAT_DEG)
        CALL G_PRN_DEC2
        LD A,'.'
        CALL G_PRN_TX_CHAR
        LD HL,(GPS_SITE_LAT_FRAC3)
        CALL G_PRN_DEC3
        LD A,' '
        CALL G_PRN_TX_CHAR
        LD A,(GPS_SITE_LAT_HEMI)
        CALL G_PRN_TX_CHAR

        LD HL,GPRN_LON
        CALL G_PRN_PRINT_Z
        LD A,(GPS_SITE_LON_DEG)
        LD L,A
        LD H,0
        CALL G_PRN_DEC3
        LD A,'.'
        CALL G_PRN_TX_CHAR
        LD HL,(GPS_SITE_LON_FRAC3)
        CALL G_PRN_DEC3
        LD A,' '
        CALL G_PRN_TX_CHAR
        LD A,(GPS_SITE_LON_HEMI)
        CALL G_PRN_TX_CHAR
        CALL G_PRN_CRLF

        ; ON MM/DD/YY AT HH:MM:SS UTC
        LD HL,GPRN_ON
        CALL G_PRN_PRINT_Z
        LD A,(G_PRINT_UTC_MONTH)
        CALL G_PRN_DEC2
        LD A,'/'
        CALL G_PRN_TX_CHAR
        LD A,(G_PRINT_UTC_DAY)
        CALL G_PRN_DEC2
        LD A,'/'
        CALL G_PRN_TX_CHAR
        LD A,(G_PRINT_UTC_YEAR)
        CALL G_PRN_DEC2
        LD HL,GPRN_AT
        CALL G_PRN_PRINT_Z
        LD A,(G_PRINT_UTC_HOUR)
        CALL G_PRN_DEC2
        LD A,':'
        CALL G_PRN_TX_CHAR
        LD A,(G_PRINT_UTC_MINUTE)
        CALL G_PRN_DEC2
        LD A,':'
        CALL G_PRN_TX_CHAR
        LD A,(G_PRINT_UTC_SECOND)
        CALL G_PRN_DEC2
        LD HL,GPRN_UTC
        CALL G_PRN_PRINT_Z
        CALL G_PRN_CRLF
        CALL G_PRN_CRLF

        ; ITS AZIMUTH WILL BE xxx.x DEGREES (NNW)
        LD HL,GPRN_AZ
        CALL G_PRN_PRINT_Z
        LD HL,(AST_AZ10)
        PUSH HL
        CALL G_PRN_ANGLE10
        LD HL,GPRN_DEGREES_OPEN
        CALL G_PRN_PRINT_Z
        POP HL
        CALL G_PRN_COMPASS16
        LD A,')'
        CALL G_PRN_TX_CHAR
        CALL G_PRN_CRLF

        ; ITS ELEVATION WILL BE +/-xx.x DEGREES
        LD HL,GPRN_EL
        CALL G_PRN_PRINT_Z
        LD HL,(AST_EL10)
        CALL G_PRN_SIGNED_ANGLE10
        LD HL,GPRN_DEGREES
        CALL G_PRN_PRINT_Z
        CALL G_PRN_CRLF

        ; Extra lunar phase wording, exactly as designed.
        LD A,(G_OBJECT)
        CP G_OBJ_MOON
        JR NZ,G_PRR_FINISH

        CALL G_PRN_CRLF
        LD HL,GPRN_PHASE_LEAD
        CALL G_PRN_PRINT_Z
        CALL G_PRN_MOON_PHASE_NAME
        LD HL,GPRN_PHASE_TRAIL
        CALL G_PRN_PRINT_Z
        CALL G_PRN_CRLF

        LD A,(G_PHASE)
        LD L,A
        LD H,0
        CALL G_PRN_U16_TRIM3
        LD HL,GPRN_ILLUMINATED
        CALL G_PRN_PRINT_Z
        CALL G_PRN_CRLF

G_PRR_FINISH:
        CALL G_PRN_CRLF
        CALL G_PRN_CRLF

        ; Advance the Printer 250 paper after the completed report.
        ; Send 23 LF bytes (no CR), each using the existing TX pacing.
        ; Preserve BC across the feed loop because TX_CHAR uses B.
        PUSH BC
        LD C,23
G_PRR_PAPER_FEED:
        LD A,10
        CALL G_PRN_TX_CHAR
        DEC C
        JR NZ,G_PRR_PAPER_FEED
        POP BC

        CALL G_PRINTER_RESTORE_DEBUG

        ; Brief completion acknowledgement, then return automatically.
        ; Do NOT wait for a key here.  The caller will restore G_SCREEN=0
        ; and redraw the normal object status screen (for example JUPITER VIS).
        LD HL,GMSG_PRINT_COMPLETE
        CALL DISPLAY_SHOW

        LD B,200                     ; ~0.4-0.5 s nominal at current delay calibration
G_PRR_DONE_DELAY:
        CALL DELAY_2MS
        DJNZ G_PRR_DONE_DELAY
        RET

; Print selected object centered within 42 printer columns.
; Counts the zero-terminated name and prints floor((42-length)/2)
; leading spaces.  The existing object-name table is unchanged.
G_PRN_CENTER_OBJECT:
        LD A,(G_OBJECT)
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_OBJECT_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        PUSH HL
        LD B,0
G_PRN_CTR_COUNT:
        LD A,(HL)
        OR A
        JR Z,G_PRN_CTR_SPACES
        INC B
        INC HL
        JR G_PRN_CTR_COUNT
G_PRN_CTR_SPACES:
        LD A,42
        SUB B
        SRL A
        LD B,A
G_PRN_CTR_PAD:
        LD A,' '
        CALL G_PRN_TX_CHAR
        DJNZ G_PRN_CTR_PAD
        POP HL
        JP G_PRN_PRINT_Z

; Print selected object name to Printer 250.
G_PRN_OBJECT:
        LD A,(G_OBJECT)
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_OBJECT_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP G_PRN_PRINT_Z

; ---------------------------------------------------------------------------
; ALPHA DATE / TIME VIEW
; ---------------------------------------------------------------------------
G_CLOCK_VIEW:
        XOR A
G_CLOCK_DRAW:
        PUSH AF
        OR A
        JR Z,G_CLOCK_DATE
        CALL G_DRAW_TIME
        JR G_CLOCK_WAIT
G_CLOCK_DATE:
        CALL G_DRAW_DATE
G_CLOCK_WAIT:
        POP AF
        LD B,A
G_CLOCK_KEY:
        CALL G_GET_UI_KEY
        CP KEY_ENTER
        JR NZ,G_CLOCK_KEY
        LD A,B
        XOR 1
        JR G_CLOCK_DRAW

G_DRAW_DATE:
        CALL DISPLAY_CLEAR
        LD A,(AST_MONTH)
        DEC A
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_MONTH_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        CALL DISPLAY_PRINT_Z
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_DAY)
        CALL DISPLAY_DEC2
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,'2'
        CALL DISPLAY_PUT_ASCII
        LD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_YEAR)
        JP DISPLAY_DEC2

G_DRAW_TIME:
        CALL DISPLAY_CLEAR
        LD A,(AST_HOUR)
        CALL DISPLAY_DEC2
        LD A,':'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_MINUTE)
        CALL DISPLAY_DEC2
        LD A,':'
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_SECOND)
        CALL DISPLAY_DEC2
        LD HL,GMSG_LOCAL
        JP DISPLAY_PRINT_Z

; ---------------------------------------------------------------------------
; SIX SCREEN DISPATCH
; ---------------------------------------------------------------------------
G_DRAW_SCREEN:
        LD A,(G_SCREEN)
        OR A
        JP Z,G_DRAW_STATUS
        CP 1
        JP Z,G_DRAW_RISE
        CP 2
        JP Z,G_DRAW_SET
        CP 3
        JP Z,G_DRAW_AZ
        JP G_DRAW_EL

G_DRAW_STATUS:
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JP Z,G_STATUS_SUN
        CP G_OBJ_MOON
        JP Z,G_STATUS_MOON
        CALL DISPLAY_CLEAR
        CALL G_PRINT_OBJECT
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_VISIBLE)
        OR A
        LD HL,GMSG_NOVIS
        JR Z,G_STATUS_WORD
        LD HL,GMSG_VIS
G_STATUS_WORD:
        JP DISPLAY_PRINT_Z

G_STATUS_SUN:
        CALL DISPLAY_CLEAR
        LD HL,GNAME_SUN
        CALL DISPLAY_PRINT_Z
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_VISIBLE)
        OR A
        LD HL,GMSG_DN
        JR Z,G_SUN_UPDN
        LD HL,GMSG_UP
G_SUN_UPDN:
        JP DISPLAY_PRINT_Z

G_STATUS_MOON:
        CALL DISPLAY_CLEAR
        LD HL,GNAME_MOON
        CALL DISPLAY_PRINT_Z
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(AST_VISIBLE)
        OR A
        LD HL,GMSG_DN
        JR Z,G_MOON_UPDN
        LD HL,GMSG_UP
G_MOON_UPDN:
        CALL DISPLAY_PRINT_Z
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(G_PHASE)
        OR A
        JR Z,G_PHASE_NEW
        CP 100
        JR NC,G_PHASE_FULL
        CALL DISPLAY_DEC2
        LD HL,GMSG_PHASE
        JP DISPLAY_PRINT_Z
G_PHASE_NEW:
        LD HL,GMSG_NEW
        JP DISPLAY_PRINT_Z
G_PHASE_FULL:
        LD HL,GMSG_FULL
        JP DISPLAY_PRINT_Z

G_DRAW_RISE:
        CALL DISPLAY_CLEAR
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_RISE_SUN
        CP G_OBJ_MOON
        JR Z,G_RISE_MOON
        LD HL,GMSG_RISE
        JR G_RISE_PREFIX
G_RISE_SUN:
        LD HL,GMSG_SUNRISE
        JR G_RISE_PREFIX
G_RISE_MOON:
        LD HL,GMSG_MOONRISE
G_RISE_PREFIX:
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_RISE)
        JP G_PRINT_TIME_OR_NONE_L

G_DRAW_SET:
        CALL DISPLAY_CLEAR
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_SET_SUN
        CP G_OBJ_MOON
        JR Z,G_SET_MOON
        LD HL,GMSG_SET
        JR G_SET_PREFIX
G_SET_SUN:
        LD HL,GMSG_SUNSET
        JR G_SET_PREFIX
G_SET_MOON:
        LD HL,GMSG_MOONSET
G_SET_PREFIX:
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_SET)
        JP G_PRINT_TIME_OR_NONE_L

G_DRAW_AZ:
        CALL DISPLAY_CLEAR
        LD HL,GMSG_AZ
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_AZ10)
        PUSH HL
        CALL ASTRO_PRINT_AZ10
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,'('
        CALL DISPLAY_PUT_ASCII
        POP HL
        CALL G_PRINT_COMPASS16
        LD A,')'
        JP DISPLAY_PUT_ASCII

G_DRAW_EL:
        CALL DISPLAY_CLEAR
        LD HL,GMSG_EL
        CALL DISPLAY_PRINT_Z
        LD HL,(AST_EL10)
        CALL ASTRO_PRINT_EL10
        LD HL,GMSG_DEG
        JP DISPLAY_PRINT_Z

G_PRINT_TIME_OR_NONE:
        LD A,H
        CP $FF
        JR NZ,G_PTON_TIME
        LD A,L
        CP $FF
        JR NZ,G_PTON_TIME
        LD HL,GMSG_NONE
        JP DISPLAY_PRINT_Z
G_PTON_TIME:
        JP ASTRO_PRINT_HHMM

; HL=local event time in minutes.  Print HH:MM followed by L.
; Used for RISE and SET screens so the display explicitly identifies
; these event times as local time.  NONE remains unchanged.
G_PRINT_TIME_OR_NONE_L:
        LD A,H
        CP $FF
        JR NZ,G_PTONL_TIME
        LD A,L
        CP $FF
        JR NZ,G_PTONL_TIME
        LD HL,GMSG_NONE
        JP DISPLAY_PRINT_Z
G_PTONL_TIME:
        CALL ASTRO_PRINT_HHMM
        LD A,'L'
        JP DISPLAY_PUT_ASCII

; ---------------------------------------------------------------------------
; OBJECT NAME + COMPASS
; ---------------------------------------------------------------------------
G_PRINT_OBJECT:
        LD A,(G_OBJECT)
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_OBJECT_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP DISPLAY_PRINT_Z

G_PRINT_COMPASS16:
        LD DE,112
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD B,0
        LD DE,225
G_COMP_DIV:
        OR A
        SBC HL,DE
        JR C,G_COMP_DONE
        INC B
        JR G_COMP_DIV
G_COMP_DONE:
        LD A,B
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_COMPASS_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        JP DISPLAY_PRINT_Z

; Safe RTC refresh. ASTRO_RTC_READ writes candidate fields before it
; validates them, so save the current valid/manual clock and restore on error.
G_REFRESH_RTC_SAFE:
        ; V1H: Manual-clock mode.
        ; Preserve the date/time entered at startup and do not overwrite it
        ; with the hardware RTC during object selection/calculation.
        SCF
        RET

; ---------------------------------------------------------------------------
; DATE PREPARATION AND FAST LINEAR ELEMENT EVOLUTION
; ---------------------------------------------------------------------------
G_PREPARE_DATE:
        CALL G_REFRESH_RTC_SAFE
        JR C,G_PD_KEEP_MANUAL
        ; RTC valid -> AST_* refreshed.
G_PD_KEEP_MANUAL:
        CALL ASTRO_DAY_NUMBER
        CALL G_PREPARE_SUN_BASE
        RET

G_PREPARE_SUN_BASE:
        ; Sun mean anomaly at UTC 00:00
        LD HL,G_SUN_M0
        LD (G_CALC_BASE),HL
        LD HL,G_SUN_MI
        LD (G_CALC_INT),HL
        LD HL,G_SUN_MF
        LD (G_CALC_FRAC),HL
        CALL G_CALC_MEAN
        LD (AST_SM),HL
        ; Sun longitude of perihelion
        LD HL,G_SUN_W0
        LD (G_CALC_BASE),HL
        LD HL,G_SUN_WR
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (AST_SW),HL
        RET

; G_CALC_SMALL: base angle + signed small drift.
; rate units = 1/10000 of a tenth-degree per day.
G_CALC_SMALL:
        LD HL,(G_CALC_RATE)
        XOR A
        LD (G_CALC_SIGN),A
        BIT 7,H
        JR Z,G_CS_POS
        CALL ASTRO_NEG_HL
        LD A,1
        LD (G_CALC_SIGN),A
G_CS_POS:
        EX DE,HL
        LD HL,(AST_DAYS)
        CALL ASTRO_UMUL16
        LD HL,5000
        CALL G_M32_ADD16
        LD HL,10000
        CALL ASTRO_DIV32_BY_16
        EX DE,HL                   ; DE=correction
        LD HL,(G_CALC_BASE)
        LD A,(G_CALC_SIGN)
        OR A
        JR Z,G_CS_ADD
        OR A
        SBC HL,DE
        JP ASTRO_NORM3600_SIGNED
G_CS_ADD:
        ADD HL,DE
        JP ASTRO_NORM3600

; G_CALC_MEAN: base + days*(integer + frac/10000), modulo 3600.
G_CALC_MEAN:
        ; fractional contribution, rounded
        LD HL,(AST_DAYS)
        LD DE,(G_CALC_FRAC)
        CALL ASTRO_UMUL16
        LD HL,5000
        CALL G_M32_ADD16
        LD HL,10000
        CALL ASTRO_DIV32_BY_16
        LD (G_TMPW0),HL
        ; integer contribution
        LD HL,(AST_DAYS)
        LD DE,(G_CALC_INT)
        CALL ASTRO_UMUL16
        LD HL,(G_TMPW0)
        CALL G_M32_ADD16
        LD HL,(G_CALC_BASE)
        CALL G_M32_ADD16
        LD HL,3600
        CALL ASTRO_DIV32_BY_16
        EX DE,HL                   ; divider leaves remainder in DE
        RET

; Add unsigned HL to little-endian M32_ACC.
G_M32_ADD16:
        LD A,(M32_ACC)
        ADD A,L
        LD (M32_ACC),A
        LD A,(M32_ACC+1)
        ADC A,H
        LD (M32_ACC+1),A
        LD A,(M32_ACC+2)
        ADC A,0
        LD (M32_ACC+2),A
        LD A,(M32_ACC+3)
        ADC A,0
        LD (M32_ACC+3),A
        RET

; Fractional-day correction: input HL=UTC minutes (may be up to 1739),
; DE=mean motion in hundredths of a tenth-degree/day. Returns HL=angle10 delta.
G_MINUTE_MDELTA:
        CALL ASTRO_UMUL16
        LD HL,1440
        CALL ASTRO_DIV32_BY_16     ; hundredths of tenth in HL
        LD DE,50
        ADD HL,DE
        CALL ASTRO_DIVU10
        JP ASTRO_DIVU10

; Load normal planet table for current object and evolve date elements.
G_PREPARE_NORMAL:
        LD A,(G_OBJECT)
        ; map user object id to normal table 0..6; Sun/Pluto/Moon never call here.
        CP G_OBJ_MARS
        JR C,G_PN_LOW              ; Mercury/Venus (0/1)
        CP G_OBJ_JUPITER
        JR C,G_PN_MARS             ; Mars id3
        ; Jupiter..Neptune ids4..7 -> table index3..6
        DEC A
        JR G_PN_INDEX
G_PN_MARS:
        LD A,2
        JR G_PN_INDEX
G_PN_LOW:
        ; A already 0 or 1
G_PN_INDEX:
        ADD A,A
        LD E,A
        LD D,0
        LD HL,G_PLANET_PTRS
        ADD HL,DE
        LD E,(HL)
        INC HL
        LD D,(HL)
        EX DE,HL
        LD DE,G_N0
        LD BC,30
        LDIR

        ; N
        LD HL,(G_N0)
        LD (G_CALC_BASE),HL
        LD HL,(G_NR)
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_N),HL
        ; inclination
        LD HL,(G_I0)
        LD (G_CALC_BASE),HL
        LD HL,(G_IR)
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_I),HL
        ; w
        LD HL,(G_W0)
        LD (G_CALC_BASE),HL
        LD HL,(G_WR)
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_W),HL
        ; M
        LD HL,(G_M0)
        LD (G_CALC_BASE),HL
        LD HL,(G_MI)
        LD (G_CALC_INT),HL
        LD HL,(G_MF)
        LD (G_CALC_FRAC),HL
        CALL G_CALC_MEAN
        LD (G_M),HL
        RET

; ---------------------------------------------------------------------------
; TOP-LEVEL CALCULATION
; ---------------------------------------------------------------------------
G_CALCULATE_SELECTED:
        ; G_CALC_COMMON has already prepared date and Sun base while the
        ; selected object's name was displayed.

        ; Object-specific element preparation.
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_CALC_PREP_DONE
        CP G_OBJ_PLUTO
        JR Z,G_CALC_PREP_DONE
        CP G_OBJ_MOON
        JR Z,G_PREP_MOON
        CALL G_PREPARE_NORMAL
        CALL DEBUG_PLANET_STAGE
        JR G_CALC_PREP_DONE
G_PREP_MOON:
        CALL G_PREPARE_MOON
G_CALC_PREP_DONE:
        CALL G_PROGRESS_NEXT          ; .

        ; Rise/set only. Transit calculation has been removed completely.
        LD A,(G_OBJECT)
        CP G_OBJ_MOON
        JR Z,G_CALC_MOON_EVENTS
        CALL G_EVENTS_FIXED
        CALL DEBUG_EVENTS_STAGE
        JR G_CALC_EVENTS_DONE
G_CALC_MOON_EVENTS:
        CALL G_EVENTS_MOON
G_CALC_EVENTS_DONE:
        ; The event scan itself supplied dots 2, 3 and 4 at quarter points.

        ; Current position / visibility.
        CALL G_CURRENT_HORIZONTAL
        CALL DEBUG_CURRENT_STAGE

        LD A,(G_OBJECT)
        CP G_OBJ_MOON
        JR NZ,G_CALC_FINAL_PROGRESS
        CALL G_CALC_MOON_PHASE
G_CALC_FINAL_PROGRESS:
        CALL G_PROGRESS_NEXT          ; ..... final dot only after all work is complete
        RET

; ---------------------------------------------------------------------------
; SUN ECLIPTIC VECTOR, input HL=UTC minutes 0..1739
; returns G_SX/G_SY, and G_SUN_LON
; ---------------------------------------------------------------------------
G_SUN_VECTOR:
        LD (G_UTC_MIN),HL
        LD DE,G_SUN_MX100
        CALL G_MINUTE_MDELTA
        EX DE,HL
        LD HL,(AST_SM)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW0),HL            ; M
        LD (G_SUN_M_CUR),HL
        ; E = M + 10*sin(M)
        PUSH HL
        CALL ASTRO_SIN10
        LD A,10
        CALL ASTRO_SCALE_Q15_U8
        EX DE,HL
        POP HL
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW1),HL            ; E
        LD (G_DBG_SUN_E),HL
        ; xv
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,G_SUN_AQ
        CALL ASTRO_MUL_Q15
        LD DE,G_SUN_AEQ
        OR A
        SBC HL,DE
        LD (G_XV),HL
        ; yv
        LD HL,(G_TMPW1)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,G_SUN_BQ
        CALL ASTRO_MUL_Q15
        LD (G_YV),HL
        ; rotate by w
        LD HL,(AST_SW)
        CALL ASTRO_COS10
        LD (G_TMPW2),HL
        LD HL,(AST_SW)
        CALL ASTRO_SIN10
        LD (G_TMPW3),HL
        LD HL,(G_XV)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW0),HL
        LD HL,(G_YV)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW0)
        OR A
        SBC HL,DE
        LD (G_SX),HL
        LD HL,(G_XV)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW0),HL
        LD HL,(G_YV)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW0)
        ADD HL,DE
        LD (G_SY),HL
        ; sun true ecliptic longitude
        LD HL,(G_SY)
        LD DE,(G_SX)
        CALL ASTRO_ATAN2_10
        LD (G_SUN_LON),HL
        RET

; ---------------------------------------------------------------------------
; GENERIC NORMAL PLANET HELIOCENTRIC VECTOR, input HL=UTC minutes.
; returns G_XH/G_YH/G_ZH.
; ---------------------------------------------------------------------------
G_PLANET_HELIO:
        LD (G_UTC_MIN),HL
        LD DE,(G_MX100)
        CALL G_MINUTE_MDELTA
        EX DE,HL
        LD HL,(G_M)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW0),HL            ; Mcur
        LD (G_DBG_PLAN_M),HL

        ; E = M + K1*sinM + K2*sin2M
        CALL ASTRO_SIN10
        LD DE,(G_K1)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW1),HL
        LD HL,(G_TMPW0)
        ADD HL,HL
        CALL ASTRO_NORM3600
        CALL ASTRO_SIN10
        LD DE,(G_K2)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        EX DE,HL
        LD HL,(G_TMPW0)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW1),HL            ; E
        LD (G_DBG_PLAN_E),HL

        ; xv = A cosE - AE
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(G_AQ)
        CALL ASTRO_MUL_Q15
        LD DE,(G_AEQ)
        OR A
        SBC HL,DE
        LD (G_XV),HL
        LD (G_DBG_XV),HL
        ; yv = B sinE
        LD HL,(G_TMPW1)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(G_BQ)
        CALL ASTRO_MUL_Q15
        LD (G_YV),HL
        LD (G_DBG_YV),HL

        ; x1/y1 rotate by argument of perihelion
        LD HL,(G_W)
        CALL ASTRO_COS10
        LD (G_TMPW2),HL
        LD HL,(G_W)
        CALL ASTRO_SIN10
        LD (G_TMPW3),HL
        LD HL,(G_XV)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW0),HL
        LD HL,(G_YV)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW0)
        OR A
        SBC HL,DE
        LD (G_X1),HL
        LD HL,(G_XV)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW0),HL
        LD HL,(G_YV)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW0)
        ADD HL,DE
        LD (G_Y1),HL

        ; node and inclination trig
        LD HL,(G_N)
        CALL ASTRO_COS10
        LD (G_TMPW2),HL            ; cosN
        LD HL,(G_N)
        CALL ASTRO_SIN10
        LD (G_TMPW3),HL            ; sinN
        LD HL,(G_I)
        CALL ASTRO_COS10
        LD (G_TMPW0),HL            ; cosi
        LD HL,(G_I)
        CALL ASTRO_SIN10
        LD (G_TMPW1),HL            ; sini

        ; xh = x1 cosN - y1 cosi sinN
        LD HL,(G_X1)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_XH),HL
        LD HL,(G_Y1)
        LD DE,(G_TMPW0)
        CALL ASTRO_MUL_Q15
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_XH)
        OR A
        SBC HL,DE
        LD (G_XH),HL
        ; yh
        LD HL,(G_X1)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        LD (G_YH),HL
        LD HL,(G_Y1)
        LD DE,(G_TMPW0)
        CALL ASTRO_MUL_Q15
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_YH)
        ADD HL,DE
        LD (G_YH),HL
        ; zh
        LD HL,(G_Y1)
        LD DE,(G_TMPW1)
        CALL ASTRO_MUL_Q15
        LD (G_ZH),HL
        RET

; ---------------------------------------------------------------------------
; SELECTED OBJECT VECTOR, input HL=UTC minutes from local day's UTC midnight.
; Output AST_X/Y/Z = geocentric equatorial vector.
; ---------------------------------------------------------------------------
G_VECTOR_SELECTED:
        LD (G_UTC_MIN),HL
        CALL G_SUN_VECTOR
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_VEC_SUN
        CP G_OBJ_MOON
        JP Z,G_VECTOR_MOON
        CP G_OBJ_PLUTO
        JP Z,G_VECTOR_PLUTO
        LD HL,(G_UTC_MIN)
        CALL G_PLANET_HELIO
        LD HL,(G_XH)
        LD (G_DBG_HEL_X),HL
        LD HL,(G_YH)
        LD (G_DBG_HEL_Y),HL
        LD HL,(G_ZH)
        LD (G_DBG_HEL_Z),HL
        LD HL,(G_XH)
        LD DE,(G_SX)
        ADD HL,DE
        LD (G_XH),HL
        LD HL,(G_YH)
        LD DE,(G_SY)
        ADD HL,DE
        LD (G_YH),HL
        LD HL,(G_XH)
        LD (G_DBG_GEO_X),HL
        LD HL,(G_YH)
        LD (G_DBG_GEO_Y),HL
        LD HL,(G_ZH)
        LD (G_DBG_GEO_Z),HL
        JR G_ECL_TO_EQ
G_VEC_SUN:
        LD HL,(G_SX)
        LD (G_XH),HL
        LD HL,(G_SY)
        LD (G_YH),HL
        LD HL,0
        LD (G_ZH),HL

G_ECL_TO_EQ:
        LD HL,(G_XH)
        LD (AST_X),HL
        LD HL,(G_YH)
        LD DE,OBL_COS_Q15
        CALL ASTRO_MUL_Q15
        LD (G_TMPW0),HL
        LD HL,(G_ZH)
        LD DE,OBL_SIN_Q15
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW0)
        OR A
        SBC HL,DE
        LD (AST_Y),HL
        LD HL,(G_YH)
        LD DE,OBL_SIN_Q15
        CALL ASTRO_MUL_Q15
        LD (G_TMPW0),HL
        LD HL,(G_ZH)
        LD DE,OBL_COS_Q15
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW0)
        ADD HL,DE
        LD (AST_Z),HL
        RET

; ---------------------------------------------------------------------------
; FIXED-VECTOR RISE/SET for Sun/planets/Pluto. Transit intentionally omitted.
; ---------------------------------------------------------------------------
G_EVENTS_FIXED:
        LD HL,$FFFF
        LD (AST_RISE),HL
        LD (AST_SET),HL

        ; Fixed vector at local noon, exactly as in V11d11k.
        LD HL,720
        CALL G_LOCAL_TO_UTC_MIN
        CALL G_VECTOR_SELECTED
        CALL ASTRO_VECTOR_DISTANCE
        LD (AST_DIST_Q),HL

        ; Preserve the established apparent-horizon threshold for visibility.
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        LD DE,G_H0_PLANET
        JR NZ,G_EF_H0
        LD DE,G_H0_SUN
G_EF_H0:
        CALL ASTRO_MUL_Q15
        LD (AST_HORIZON_Q),HL
        CALL G_SET_LST0

        ; V11d11o: find SET first with the proven V11d11n coarse-to-fine
        ; search.  Then use that known SET as the anchor for RISE instead of
        ; starting a second independent search from NOW.
        ;
        ; RISE seed sequence requested after hardware timing tests:
        ;       SET + 10 hours
        ;       SET + 11 hours
        ;       SET + 12 hours ...
        ; in one-hour steps until elevation changes from negative to
        ; nonnegative.  That brackets RISE inside one hour.  The existing
        ; 30/15/5/1-minute polarity refinement then finds the minute.
        ;
        ; If SET+10 is already nonnegative (unusual geometry) or SET was not
        ; found, fall back to the independent V11d11n RISE search so this
        ; optimization cannot silently lose an event.
        CALL G_EF_NOW_MIN
        LD (G_EDU_MIN),HL
        LD A,1
        LD (G_EDU_MODE),A
        CALL G_EF_EDU_SEARCH
        LD (AST_SET),HL

        CALL G_EF_RISE_FROM_SET
        LD (AST_RISE),HL

        ; V11d11q: TRANSIT removed.  Rise and set are the only timed events.
        RET

; Return NOW as local minute-of-day in HL.
G_EF_NOW_MIN:
        LD A,(AST_HOUR)
        LD H,0
        LD L,A
        PUSH HL
        ADD HL,HL
        ADD HL,HL
        EX DE,HL
        POP HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        OR A
        SBC HL,DE                  ; hour*60
        LD A,(AST_MINUTE)
        LD E,A
        LD D,0
        ADD HL,DE
        RET

; Find RISE from the SET time already calculated above.
; First sample is SET+10 hours.  If still below the horizon, advance in
; one-hour steps: +11h, +12h, ... until the sign changes.  On the crossing,
; reuse the V11d11n 30/15/5/1-minute refinement path.
; Return HL = local minute of RISE.
G_EF_RISE_FROM_SET:
        LD HL,(AST_SET)
        LD A,H
        CP $FF
        JR Z,G_EF_RFS_FALLBACK

        ; SET + 10 hours, wrapped into the local 0..1439 minute day.
        LD DE,600
        ADD HL,DE
        LD DE,1440
        OR A
        SBC HL,DE
        JR NC,G_EF_RFS_SEED_OK
        ADD HL,DE
G_EF_RFS_SEED_OK:
        LD (G_EDU_MIN),HL
        ; Only above/below is needed at this seed.  Use the fast UP-only
        ; path rather than computing east/north, sqrt and atan elevation.
        CALL G_EF_SIGN_AT_MIN
        OR A
        JR NZ,G_EF_RFS_FALLBACK     ; rise happened before SET+10: use safe path

        ; We are below the horizon at SET+10.  Lock forward direction and
        ; walk one hour at a time until negative -> nonnegative crossing.
        XOR A
        LD (G_EDU_PREV_SIGN),A
        LD (G_EDU_DIR),A             ; forward/add
        LD HL,60
        LD (G_EDU_STEP),HL
        LD A,14                      ; +11 through +24 hours maximum guard
        LD (G_EDU_COUNT),A
G_EF_RFS_HOUR_LOOP:
        CALL G_EF_TRY_STEP_FAST
        JP C,G_EF_BIG_CROSSED        ; bracketed: refine 30/15/5/1 minutes
        LD A,(G_EDU_COUNT)
        DEC A
        LD (G_EDU_COUNT),A
        JR NZ,G_EF_RFS_HOUR_LOOP

        ; Defensive fallback if no rise was bracketed within a full day.
G_EF_RFS_FALLBACK:
        CALL G_EF_NOW_MIN
        LD (G_EDU_MIN),HL
        XOR A
        LD (G_EDU_MODE),A            ; RISE
        CALL G_EF_EDU_SEARCH
        RET

; Coarse-to-fine horizon search. G_EDU_MODE: 0 rise, 1 set.
; Direction is chosen ONCE from the initial elevation and never changes:
;   RISE: EL<0 forward (WILL RISE), EL>=0 backward (HAS RISEN)
;   SET : EL>=0 forward (WILL SET), EL<0 backward (HAS SET)
;
; Search sequence requested for V11d11n:
;   >=15 deg : educated |EL|/15-hour jump(s)
;   inside +/-15 deg: one 30-minute check
;   if no crossing: one 15-minute check
;   if no crossing: one 5-minute check
;   then 1-minute checks until polarity changes.
; A polarity change is tested after EVERY trial. If a coarse trial crosses,
; restore the pre-crossing minute and continue with the next finer step.
G_EF_EDU_SEARCH:
        LD A,96                    ; hard safety guard, mainly for 1-min tail
        LD (G_EDU_COUNT),A

        ; Evaluate starting point and save its polarity.
        LD HL,(G_EDU_MIN)
        CALL G_EF_ELEV_AT_MIN
        LD (G_EDU_EL10),HL
        CALL G_EF_SIGN_HL
        LD (G_EDU_PREV_SIGN),A

        ; Lock search direction from MODE + initial sign.
        ; DIR 0=forward/add, 1=backward/subtract.
        LD B,A                     ; B = initial sign: 0 neg, 1 nonneg
        LD A,(G_EDU_MODE)
        OR A
        JR NZ,G_EF_DIR_SET
        ; rise: negative -> forward, nonnegative -> backward
        LD A,B
        OR A
        JR Z,G_EF_DIR_FWD
        JR G_EF_DIR_BACK
G_EF_DIR_SET:
        ; set: nonnegative -> forward, negative -> backward
        LD A,B
        OR A
        JR NZ,G_EF_DIR_FWD
G_EF_DIR_BACK:
        LD A,1
        LD (G_EDU_DIR),A
        JR G_EF_BIG_TEST
G_EF_DIR_FWD:
        XOR A
        LD (G_EDU_DIR),A

G_EF_BIG_TEST:
        ; If abs(EL) < 15 degrees, begin the fixed 30/15/5/1 sequence.
        LD HL,(G_EDU_EL10)
        BIT 7,H
        JR Z,G_EF_BIG_ABS_OK
        CALL ASTRO_NEG_HL
G_EF_BIG_ABS_OK:
        LD DE,150
        OR A
        SBC HL,DE
        JP C,G_EF_PHASE30

        ; Educated jump = round(abs(EL)/15) whole hours, minimum one hour.
        LD HL,(G_EDU_EL10)
        BIT 7,H
        JR Z,G_EF_BIG_ABS2
        CALL ASTRO_NEG_HL
G_EF_BIG_ABS2:
        LD DE,75
        ADD HL,DE
        LD B,0
G_EF_BIG_DIV150:
        LD DE,150
        OR A
        SBC HL,DE
        JR C,G_EF_BIG_DIV_DONE
        INC B
        JR G_EF_BIG_DIV150
G_EF_BIG_DIV_DONE:
        LD A,B
        OR A
        JR NZ,G_EF_BIG_HOURS_OK
        INC B
G_EF_BIG_HOURS_OK:
        LD HL,0
        LD DE,60
G_EF_BIG_MUL60:
        ADD HL,DE
        DJNZ G_EF_BIG_MUL60
        LD (G_EDU_STEP),HL
        ; The educated-jump loop still needs the actual elevation magnitude
        ; to choose its next |EL|/15-hour jump, so keep the full calculation.
        CALL G_EF_TRY_STEP_FULL
        JP C,G_EF_BIG_CROSSED
        JP G_EF_BIG_TEST

G_EF_BIG_CROSSED:
        ; The large jump bracketed the horizon. Go back to the old side and
        ; approach it in 30-minute increments before the finer checks.
        LD HL,(G_EDU_PREV_MIN)
        LD (G_EDU_MIN),HL
        LD A,(G_EDU_PREV_SIGN)
        LD (G_EDU_PREV_SIGN),A
G_EF_BIG_30_LOOP:
        LD HL,30
        LD (G_EDU_STEP),HL
        CALL G_EF_TRY_STEP_FAST
        JR NC,G_EF_BIG_30_LOOP
        LD HL,(G_EDU_PREV_MIN)
        LD (G_EDU_MIN),HL
        JP G_EF_PHASE15

G_EF_PHASE30:
        LD HL,30
        LD (G_EDU_STEP),HL
        CALL G_EF_TRY_STEP_FAST
        JR NC,G_EF_PHASE15
        LD HL,(G_EDU_PREV_MIN)
        LD (G_EDU_MIN),HL

G_EF_PHASE15:
        LD HL,15
        LD (G_EDU_STEP),HL
        CALL G_EF_TRY_STEP_FAST
        JR NC,G_EF_PHASE5
        LD HL,(G_EDU_PREV_MIN)
        LD (G_EDU_MIN),HL

G_EF_PHASE5:
        LD HL,5
        LD (G_EDU_STEP),HL
        CALL G_EF_TRY_STEP_FAST
        JR NC,G_EF_PHASE1
        LD HL,(G_EDU_PREV_MIN)
        LD (G_EDU_MIN),HL

G_EF_PHASE1:
        LD HL,1
        LD (G_EDU_STEP),HL
G_EF_ONE_LOOP:
        CALL G_EF_TRY_STEP_FAST
        JR C,G_EF_ES_DONE
        LD A,(G_EDU_COUNT)
        DEC A
        LD (G_EDU_COUNT),A
        JR NZ,G_EF_ONE_LOOP
        ; Defensive safety exit if no crossing appeared in the 1-minute tail.
G_EF_ES_DONE:
        LD HL,(G_EDU_MIN)
        RET

; Return A=0 for negative HL, A=1 for zero/positive HL.
G_EF_SIGN_HL:
        BIT 7,H
        JR Z,G_EF_SIGN_POS
        XOR A
        RET
G_EF_SIGN_POS:
        LD A,1
        RET

; Fast trial used once a crossing search only needs polarity.  This is
; mathematically equivalent to testing the sign of elevation because
; atan2(UP,horizontal) has the same sign as UP.  It deliberately avoids
; EAST, NORTH, squares, integer square root, and atan2.
G_EF_TRY_STEP_FAST:
        LD HL,(G_EDU_MIN)
        LD (G_EDU_PREV_MIN),HL
        LD A,(G_EDU_PREV_SIGN)
        PUSH AF

        LD A,(G_EDU_DIR)
        OR A
        JR NZ,G_EF_FAST_SUB
G_EF_FAST_ADD:
        LD DE,(G_EDU_STEP)
        ADD HL,DE
        LD DE,1440
        OR A
        SBC HL,DE
        JR C,G_EF_FAST_ADD_RESTORE
        JR G_EF_FAST_STORE
G_EF_FAST_ADD_RESTORE:
        ADD HL,DE
        JR G_EF_FAST_STORE
G_EF_FAST_SUB:
        LD DE,(G_EDU_STEP)
        OR A
        SBC HL,DE
        JR NC,G_EF_FAST_STORE
        LD DE,1440
        ADD HL,DE
G_EF_FAST_STORE:
        LD (G_EDU_MIN),HL
        CALL G_EF_SIGN_AT_MIN
        LD B,A
        POP AF
        CP B
        JR Z,G_EF_FAST_NO_CROSS
        LD (G_EDU_PREV_SIGN),A
        SCF
        RET
G_EF_FAST_NO_CROSS:
        LD A,B
        LD (G_EDU_PREV_SIGN),A
        OR A
        RET

; Full trial retained only for the educated |EL|/15-hour jump, because that
; stage genuinely needs elevation magnitude to choose the next coarse step.
; Carry set = polarity changed (horizon bracketed).
G_EF_TRY_STEP_FULL:
        LD HL,(G_EDU_MIN)
        LD (G_EDU_PREV_MIN),HL
        LD A,(G_EDU_PREV_SIGN)
        PUSH AF

        LD A,(G_EDU_DIR)
        OR A
        JR NZ,G_EF_TRY_SUB
G_EF_TRY_ADD:
        LD DE,(G_EDU_STEP)
        ADD HL,DE
        LD DE,1440
        OR A
        SBC HL,DE
        JR C,G_EF_TRY_ADD_RESTORE
        JR G_EF_TRY_STORE
G_EF_TRY_ADD_RESTORE:
        ADD HL,DE
        JR G_EF_TRY_STORE
G_EF_TRY_SUB:
        LD DE,(G_EDU_STEP)
        OR A
        SBC HL,DE
        JR NC,G_EF_TRY_STORE
        LD DE,1440
        ADD HL,DE
G_EF_TRY_STORE:
        LD (G_EDU_MIN),HL
        CALL G_EF_ELEV_AT_MIN
        LD (G_EDU_EL10),HL
        CALL G_EF_SIGN_HL
        LD B,A                      ; B = sign after trial
        POP AF                      ; A = sign before trial
        CP B
        JR Z,G_EF_TRY_NO_CROSS
        ; Crossing: preserve the OLD-side polarity because callers restore
        ; G_EDU_PREV_MIN before trying the next finer step.
        LD (G_EDU_PREV_SIGN),A
        SCF
        RET
G_EF_TRY_NO_CROSS:
        LD A,B
        LD (G_EDU_PREV_SIGN),A      ; new point becomes the old side next time
        OR A                        ; clear carry
        RET

; HL=local minute. Return A=0 below geometric horizon, A=1 at/above it.
; For crossing polarity we only need the sign of UP; EAST/NORTH and the
; elevation angle are unnecessary.  This preserves the existing geometric
; zero-degree crossing exactly (it intentionally does NOT apply H0 here).
G_EF_SIGN_AT_MIN:
        CALL G_UP_FOR_VECTOR_FAST
        LD HL,(AST_UP)
        JP G_EF_SIGN_HL

; Compute only q and UP for the fixed AST_X/Y/Z vector.  Compared with
; G_HORIZONTAL_FOR_VECTOR this skips EAST and NORTH entirely: two trig calls
; and four Q15 multiplies instead of four trig calls and eight multiplies.
G_UP_FOR_VECTOR_FAST:
        PUSH HL
        CALL ASTRO_SID_ADV10
        EX DE,HL
        LD HL,(AST_LST0)
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (G_TMPW0),HL

        ; q = x*cos(LST) + y*sin(LST)
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_X)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW1),HL
        LD HL,(G_TMPW0)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_Y)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        LD (AST_Q),HL

        ; up = q*cos(lat) + z*sin(lat)
        LD DE,(G_SITE_LAT_COS_Q15)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW1),HL
        LD HL,(AST_Z)
        LD DE,(G_SITE_LAT_SIN_Q15)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        LD (AST_UP),HL
        POP HL
        RET

; HL=local minute, fixed AST_X/Y/Z vector.  Return signed elevation in
; tenths of a degree.  Used only where the educated coarse jump needs |EL|.
G_EF_ELEV_AT_MIN:
        CALL G_HORIZONTAL_FOR_VECTOR
        LD HL,(AST_EAST)
        CALL ASTRO_SQUARE16
        CALL ASTRO_COPY_ACC_TO_N
        LD HL,(AST_NORTH)
        CALL ASTRO_SQUARE16
        CALL ASTRO_ADD_ACC_TO_N
        CALL ASTRO_ISQRT32
        EX DE,HL                   ; DE = horizontal magnitude
        LD HL,(AST_UP)
        CALL ASTRO_ATAN2_SIGNED90
        RET

; Refine a detected coarse horizon crossing.
; AST_PREV = state at previous coarse sample; AST_SCAN_MIN = current sample.
; Search current-9 through current.  For ordinary 10-minute samples this is
; exactly previous+1..current.  At the special 1439 sample it harmlessly starts
; at 1430 (one duplicate evaluation) and still covers through 1439.
G_EF_REFINE_CROSSING:
        LD HL,(AST_SCAN_MIN)
        LD DE,9
        OR A
        SBC HL,DE
        LD (AST_TMP6),HL               ; candidate minute
G_EF_RC_LOOP:
        LD HL,(AST_TMP6)
        CALL ASTRO_UP_AT_LOCAL_MIN
        CALL ASTRO_ABOVE_HORIZON
        LD D,A
        LD A,(AST_PREV)
        CP D
        JR NZ,G_EF_RC_FOUND

        LD HL,(AST_TMP6)
        INC HL
        LD (AST_TMP6),HL
        LD DE,(AST_SCAN_MIN)
        OR A
        SBC HL,DE
        JR C,G_EF_RC_LOOP
        JR Z,G_EF_RC_LOOP
        RET                             ; defensive: no crossing found

G_EF_RC_FOUND:
        LD A,(AST_PREV)
        OR A
        JR NZ,G_EF_RC_SET
        LD HL,(AST_RISE)
        LD A,H
        CP $FF
        RET NZ
        LD HL,(AST_TMP6)
        LD (AST_RISE),HL
        RET
G_EF_RC_SET:
        LD HL,(AST_SET)
        LD A,H
        CP $FF
        RET NZ
        LD HL,(AST_TMP6)
        LD (AST_SET),HL
        RET


; Convert local minute-of-day in HL to the UTC-minute coordinate used by
; the active astronomy vector routines. Runtime offset is signed minutes:
; local = UTC + offset, therefore UTC = local - offset.
G_LOCAL_TO_UTC_MIN:
        LD DE,(AST_UTC_OFFSET_MIN)
        OR A
        SBC HL,DE
        RET

; Set AST_LST0 for local midnight.
G_SET_LST0:
        LD HL,(AST_SM)
        LD DE,(AST_SW)
        ADD HL,DE
        LD DE,1800
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD DE,(G_SITE_LON10)
        ADD HL,DE
        PUSH HL
        LD HL,0
        CALL G_LOCAL_TO_UTC_MIN
        CALL ASTRO_SID_ADV10
        POP DE
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (AST_LST0),HL
        RET

; ---------------------------------------------------------------------------
; CURRENT HORIZONTAL POSITION
; ---------------------------------------------------------------------------
G_CURRENT_HORIZONTAL:
        ; local minute = hour*60 + minute
        LD A,(AST_HOUR)
        LD H,0
        LD L,A
        PUSH HL
        ADD HL,HL
        ADD HL,HL
        EX DE,HL
        POP HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        OR A
        SBC HL,DE
        LD A,(AST_MINUTE)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (AST_LOCAL_MIN),HL
        ; Convert local minute using the selected runtime UTC offset.
        CALL G_LOCAL_TO_UTC_MIN
        CALL G_VECTOR_SELECTED
        CALL G_SET_LST0
        LD HL,(AST_LOCAL_MIN)
        CALL G_HORIZONTAL_FOR_VECTOR
        ; visibility
        CALL ASTRO_VECTOR_DISTANCE
        LD A,(G_OBJECT)
        CP G_OBJ_SUN
        JR Z,G_CH_SUNH
        CP G_OBJ_MOON
        JR Z,G_CH_MOONH
        LD DE,G_H0_PLANET
        JR G_CH_HSET
G_CH_SUNH:
        LD DE,G_H0_SUN
        JR G_CH_HSET
G_CH_MOONH:
        LD DE,G_H0_MOON
G_CH_HSET:
        CALL ASTRO_MUL_Q15
        LD (AST_HORIZON_Q),HL
        LD HL,(AST_UP)
        CALL ASTRO_ABOVE_HORIZON
        LD (AST_VISIBLE),A
        ; azimuth
        LD HL,(AST_EAST)
        LD DE,(AST_NORTH)
        CALL ASTRO_ATAN2_10
        LD (AST_AZ10),HL
        ; horizontal magnitude
        LD HL,(AST_EAST)
        CALL ASTRO_SQUARE16
        CALL ASTRO_COPY_ACC_TO_N
        LD HL,(AST_NORTH)
        CALL ASTRO_SQUARE16
        CALL ASTRO_ADD_ACC_TO_N
        CALL ASTRO_ISQRT32
        LD (AST_HOR),HL
        ; elevation
        LD HL,(AST_UP)
        LD DE,(AST_HOR)
        CALL ASTRO_ATAN2_SIGNED90
        LD (AST_EL10),HL
        RET

; HL=local minute, current AST_X/Y/Z vector. Computes east/north/up.
G_HORIZONTAL_FOR_VECTOR:
        PUSH HL
        CALL ASTRO_SID_ADV10
        EX DE,HL
        LD HL,(AST_LST0)
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (G_TMPW0),HL            ; LST
        ; q=x cosLST + y sinLST
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_X)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW1),HL
        LD HL,(G_TMPW0)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_Y)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        LD (AST_Q),HL
        ; east=-x sinLST + y cosLST
        LD HL,(G_TMPW0)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,(AST_X)
        CALL ASTRO_MUL_Q15
        CALL ASTRO_NEG_HL
        LD (G_TMPW1),HL
        LD HL,(G_TMPW0)
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,(AST_Y)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        LD (AST_EAST),HL
        ; north=-q sinlat + z coslat
        LD HL,(AST_Q)
        LD DE,(G_SITE_LAT_SIN_Q15)
        CALL ASTRO_MUL_Q15
        CALL ASTRO_NEG_HL
        LD (G_TMPW1),HL
        LD HL,(AST_Z)
        LD DE,(G_SITE_LAT_COS_Q15)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        LD (AST_NORTH),HL
        ; up=q coslat + z sinlat
        LD HL,(AST_Q)
        LD DE,(G_SITE_LAT_COS_Q15)
        CALL ASTRO_MUL_Q15
        LD (G_TMPW1),HL
        LD HL,(AST_Z)
        LD DE,(G_SITE_LAT_SIN_Q15)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        LD (AST_UP),HL
        POP HL
        RET

; ---------------------------------------------------------------------------
; MOON DATE ELEMENTS + VECTOR
; ---------------------------------------------------------------------------
G_PREPARE_MOON:
        ; N = 125.1228 -0.0529538083*d
        LD HL,1251
        LD (G_CALC_BASE),HL
        LD HL,-5295
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_N),HL
        ; i=5.1454
        LD HL,51
        LD (G_I),HL
        ; w=318.0634 +0.1643573223*d
        LD HL,3181
        LD (G_CALC_BASE),HL
        LD HL,16436
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_W),HL
        ; M=115.3654 +13.0649929509*d
        LD HL,1154
        LD (G_CALC_BASE),HL
        LD HL,130
        LD (G_CALC_INT),HL
        LD HL,6499
        LD (G_CALC_FRAC),HL
        CALL G_CALC_MEAN
        LD (G_M),HL
        RET

G_VECTOR_MOON:
        ; Sun vector already computed, G_UTC_MIN preserved by G_SUN_VECTOR.
        LD HL,(G_UTC_MIN)
        LD DE,13065
        CALL G_MINUTE_MDELTA
        EX DE,HL
        LD HL,(G_M)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW0),HL            ; Mm current
        ; E = M + 31*sinM + 1*sin2M (e=.0549 => K1=31,K2=1)
        CALL ASTRO_SIN10
        LD DE,31
        CALL ASTRO_MUL_Q15
        LD (G_TMPW1),HL
        LD HL,(G_TMPW0)
        ADD HL,HL
        CALL ASTRO_NORM3600
        CALL ASTRO_SIN10
        LD DE,1
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW1)
        ADD HL,DE
        EX DE,HL
        LD HL,(G_TMPW0)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW1),HL            ; E
        ; normalized lunar orbital radius: A=16384, AE=899, B=16359
        CALL ASTRO_COS10
        EX DE,HL
        LD HL,16384
        CALL ASTRO_MUL_Q15
        LD DE,899
        OR A
        SBC HL,DE
        LD (G_XV),HL
        LD HL,(G_TMPW1)
        CALL ASTRO_SIN10
        EX DE,HL
        LD HL,16359
        CALL ASTRO_MUL_Q15
        LD (G_YV),HL
        ; rotate w -> x1,y1
        LD HL,(G_W)
        CALL ASTRO_COS10
        LD (G_TMPW2),HL
        LD HL,(G_W)
        CALL ASTRO_SIN10
        LD (G_TMPW3),HL
        LD HL,(G_XV)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_X1),HL
        LD HL,(G_YV)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_X1)
        OR A
        SBC HL,DE
        LD (G_X1),HL
        LD HL,(G_XV)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        LD (G_Y1),HL
        LD HL,(G_YV)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_Y1)
        ADD HL,DE
        LD (G_Y1),HL
        ; node/inc
        LD HL,(G_N)
        CALL ASTRO_COS10
        LD (G_TMPW2),HL
        LD HL,(G_N)
        CALL ASTRO_SIN10
        LD (G_TMPW3),HL
        LD HL,(G_I)
        CALL ASTRO_COS10
        LD (G_TMPW1),HL
        LD HL,(G_I)
        CALL ASTRO_SIN10
        LD (G_TMPW0),HL
        ; xh/yh/zh
        LD HL,(G_X1)
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_XH),HL
        LD HL,(G_Y1)
        LD DE,(G_TMPW1)
        CALL ASTRO_MUL_Q15
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_XH)
        OR A
        SBC HL,DE
        LD (G_XH),HL
        LD HL,(G_X1)
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        LD (G_YH),HL
        LD HL,(G_Y1)
        LD DE,(G_TMPW1)
        CALL ASTRO_MUL_Q15
        LD DE,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_YH)
        ADD HL,DE
        LD (G_YH),HL
        LD HL,(G_Y1)
        LD DE,(G_TMPW0)
        CALL ASTRO_MUL_Q15
        LD (G_ZH),HL
        ; base lon/lat
        LD HL,(G_YH)
        LD DE,(G_XH)
        CALL ASTRO_ATAN2_10
        LD (G_LON),HL
        LD HL,(G_XH)
        CALL ASTRO_SQUARE16
        CALL ASTRO_COPY_ACC_TO_N
        LD HL,(G_YH)
        CALL ASTRO_SQUARE16
        CALL ASTRO_ADD_ACC_TO_N
        CALL ASTRO_ISQRT32
        EX DE,HL
        LD HL,(G_ZH)
        CALL ASTRO_ATAN2_SIGNED90
        LD (G_LAT),HL
        ; lunar perturbations in angle10
        CALL G_MOON_PERTURB
        ; reconstruct unit vector radius 16384 from corrected lon/lat
        LD HL,(G_LAT)
        CALL ASTRO_COS10_SIGNED
        LD (G_TMPW0),HL            ; coslat
        LD HL,(G_LAT)
        CALL ASTRO_SIN10_SIGNED
        LD (G_TMPW1),HL            ; sinlat
        LD HL,(G_LON)
        CALL ASTRO_COS10
        LD DE,(G_TMPW0)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,16384
        CALL ASTRO_MUL_Q15
        LD (G_XH),HL
        LD HL,(G_LON)
        CALL ASTRO_SIN10
        LD DE,(G_TMPW0)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,16384
        CALL ASTRO_MUL_Q15
        LD (G_YH),HL
        LD HL,(G_TMPW1)
        EX DE,HL
        LD HL,16384
        CALL ASTRO_MUL_Q15
        LD (G_ZH),HL
        LD HL,(G_LON)
        LD (G_MOON_LON),HL
        JP G_ECL_TO_EQ

; Add signed coefficient DE * sin(angle HL) to G_PSUM.
G_ADD_SIN_TERM:
        PUSH DE
        CALL ASTRO_SIN10_SIGNED
        POP DE
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_PSUM)
        ADD HL,DE
        LD (G_PSUM),HL
        RET
; Add signed coefficient DE * cos(angle HL) to G_PSUM.
G_ADD_COS_TERM:
        PUSH DE
        CALL ASTRO_COS10_SIGNED
        POP DE
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_PSUM)
        ADD HL,DE
        LD (G_PSUM),HL
        RET

; Moon perturbations, coefficients rounded to 0.1 degree.
G_MOON_PERTURB:
        ; Compute Lm=N+w+Mm; Ls=sun true longitude; D=Lm-Ls; F=Lm-N.
        LD HL,(G_N)
        LD DE,(G_W)
        ADD HL,DE
        ; reload current Mm from date + minute
        PUSH HL
        LD HL,(G_UTC_MIN)
        LD DE,13065
        CALL G_MINUTE_MDELTA
        EX DE,HL
        LD HL,(G_M)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW0),HL
        EX DE,HL
        POP HL
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_TMPW1),HL            ; Lm
        LD DE,(G_SUN_LON)
        OR A
        SBC HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (G_TMPW2),HL            ; D
        LD HL,(G_TMPW1)
        LD DE,(G_N)
        OR A
        SBC HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (G_TMPW3),HL            ; F

        ; longitude correction
        LD HL,0
        LD (G_PSUM),HL
        ; -13 sin(Mm-2D)
        LD HL,(G_TMPW2)
        ADD HL,HL
        EX DE,HL
        LD HL,(G_TMPW0)
        OR A
        SBC HL,DE
        LD DE,-13
        CALL G_ADD_SIN_TERM
        ; +7 sin(2D)
        LD HL,(G_TMPW2)
        ADD HL,HL
        LD DE,7
        CALL G_ADD_SIN_TERM
        ; -2 sin(Msun)
        LD HL,(G_UTC_MIN)
        LD DE,G_SUN_MX100
        CALL G_MINUTE_MDELTA
        EX DE,HL
        LD HL,(AST_SM)
        ADD HL,DE
        CALL ASTRO_NORM3600
        LD (G_SUN_M_CUR),HL
        LD DE,-2
        CALL G_ADD_SIN_TERM
        ; -1 sin(2Mm-2D)
        LD HL,(G_TMPW0)
        ADD HL,HL
        LD DE,(G_TMPW2)
        SLA E
        RL D
        OR A
        SBC HL,DE
        LD DE,-1
        CALL G_ADD_SIN_TERM
        ; -1 sin(Mm-2D+Ms)
        LD HL,(G_TMPW2)
        ADD HL,HL
        EX DE,HL
        LD HL,(G_TMPW0)
        OR A
        SBC HL,DE
        LD DE,(G_SUN_M_CUR)
        ADD HL,DE
        LD DE,-1
        CALL G_ADD_SIN_TERM
        ; +1 sin(Mm+2D)
        LD HL,(G_TMPW2)
        ADD HL,HL
        EX DE,HL
        LD HL,(G_TMPW0)
        ADD HL,DE
        LD DE,1
        CALL G_ADD_SIN_TERM
        ; +1 sin(2D-Ms)
        LD HL,(G_TMPW2)
        ADD HL,HL
        LD DE,(G_SUN_M_CUR)
        OR A
        SBC HL,DE
        LD DE,1
        CALL G_ADD_SIN_TERM
        ; +1 sin(Mm-Ms)
        LD HL,(G_TMPW0)
        LD DE,(G_SUN_M_CUR)
        OR A
        SBC HL,DE
        LD DE,1
        CALL G_ADD_SIN_TERM
        ; Remaining <0.1-degree terms intentionally omitted at 0.1-deg resolution.
        LD HL,(G_LON)
        LD DE,(G_PSUM)
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (G_LON),HL

        ; latitude correction: -2 sin(F-2D) -1 sin(Mm-F-2D)
        LD HL,0
        LD (G_PSUM),HL
        LD HL,(G_TMPW2)
        ADD HL,HL
        EX DE,HL
        LD HL,(G_TMPW3)
        OR A
        SBC HL,DE
        LD DE,-2
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW3)
        LD DE,(G_TMPW2)
        SLA E
        RL D
        ADD HL,DE                 ; F+2D
        EX DE,HL
        LD HL,(G_TMPW0)
        OR A
        SBC HL,DE                 ; Mm-F-2D
        LD DE,-1
        CALL G_ADD_SIN_TERM
        LD HL,(G_LAT)
        LD DE,(G_PSUM)
        ADD HL,DE
        LD (G_LAT),HL
        RET

; ---------------------------------------------------------------------------
; DYNAMIC MOON EVENTS: 10-minute coarse scan + 1-minute refinement.
; ---------------------------------------------------------------------------
G_EVENTS_MOON:
        LD HL,$FFFF
        LD (AST_RISE),HL
        LD (AST_SET),HL
        CALL G_SET_LST0
        ; fixed threshold for normalized lunar vector
        LD HL,16384
        LD DE,G_H0_MOON
        CALL ASTRO_MUL_Q15
        LD (AST_HORIZON_Q),HL
        ; minute 0
        LD HL,0
        CALL G_MOON_UP_AT_MIN
        LD (G_DYN_PREV),HL
        CALL ASTRO_ABOVE_HORIZON
        LD (AST_PREV),A
        LD HL,10
        LD (AST_SCAN_MIN),HL
G_EM_LOOP:
        ; Spread progress dots 2, 3 and 4 across the lunar event scan.
        LD HL,(AST_SCAN_MIN)
        LD DE,360
        OR A
        SBC HL,DE
        JR Z,G_EM_PROGRESS
        LD HL,(AST_SCAN_MIN)
        LD DE,720
        OR A
        SBC HL,DE
        JR Z,G_EM_PROGRESS
        LD HL,(AST_SCAN_MIN)
        LD DE,1080
        OR A
        SBC HL,DE
        JR NZ,G_EM_NO_PROGRESS
G_EM_PROGRESS:
        CALL G_PROGRESS_NEXT
G_EM_NO_PROGRESS:
        LD HL,(AST_SCAN_MIN)
        CALL G_MOON_UP_AT_MIN
        LD (G_CUR_UP),HL
        LD HL,(G_CUR_UP)
        CALL ASTRO_ABOVE_HORIZON
        LD D,A
        LD A,(AST_PREV)
        CP D
        JR Z,G_EM_STATE
        OR A
        JR NZ,G_EM_FOUND_SET
        LD HL,(AST_RISE)
        LD A,H
        CP $FF
        JR NZ,G_EM_STATE
        LD HL,(AST_SCAN_MIN)
        LD (AST_RISE),HL
        JR G_EM_STATE
G_EM_FOUND_SET:
        LD HL,(AST_SET)
        LD A,H
        CP $FF
        JR NZ,G_EM_STATE
        LD HL,(AST_SCAN_MIN)
        LD (AST_SET),HL
G_EM_STATE:
        LD A,D
        LD (AST_PREV),A
        LD HL,(AST_SCAN_MIN)
        LD (G_PREV_MIN),HL
        LD DE,10
        ADD HL,DE
        LD (AST_SCAN_MIN),HL
        LD DE,1440
        OR A
        SBC HL,DE
        JP C,G_EM_LOOP
        ; refine rise/set to one minute; transit is intentionally omitted
        LD HL,(AST_RISE)
        CALL G_REFINE_CROSS
        LD (AST_RISE),HL
        LD HL,(AST_SET)
        CALL G_REFINE_CROSS
        LD (AST_SET),HL
        RET

; Input HL=coarse crossing minute (multiple of 10), FFFF unchanged.
; Returns refined minute by scanning coarse-10..coarse at 1-minute resolution.
G_REFINE_CROSS:
        LD A,H
        CP $FF
        RET Z
        LD DE,10
        OR A
        SBC HL,DE
        JR NC,G_RC_START_OK
        LD HL,0
G_RC_START_OK:
        LD (G_REFINE_MIN),HL
        CALL G_MOON_UP_AT_MIN
        CALL ASTRO_ABOVE_HORIZON
        LD (AST_PREV),A
        LD B,10
G_RC_LOOP:
        LD HL,(G_REFINE_MIN)
        INC HL
        LD (G_REFINE_MIN),HL
        PUSH BC                         ; lunar vector code freely uses B/C
        CALL G_MOON_UP_AT_MIN
        CALL ASTRO_ABOVE_HORIZON
        POP BC                          ; preserve DJNZ refinement count
        LD D,A
        LD A,(AST_PREV)
        CP D
        JR NZ,G_RC_FOUND
        LD A,D
        LD (AST_PREV),A
        DJNZ G_RC_LOOP
        LD HL,(G_REFINE_MIN)
        RET
G_RC_FOUND:
        LD HL,(G_REFINE_MIN)
        RET

; Input HL=local minute, returns signed up coordinate.
; IMPORTANT: lunar vector generation uses G_TMPW0..G_TMPW3 as scratch,
; so preserve the local minute in dedicated RAM instead of a G_TMPW register.
G_MOON_UP_AT_MIN:
        LD (G_MOON_LOCAL_MIN),HL
        CALL G_LOCAL_TO_UTC_MIN
        CALL G_VECTOR_SELECTED
        LD HL,(G_MOON_LOCAL_MIN)
        ; Event detection needs only UP.  Skip EAST/NORTH during all lunar
        ; coarse and one-minute event samples; final current AZ/EL still uses
        ; the complete horizontal calculation elsewhere.
        CALL G_UP_FOR_VECTOR_FAST
        LD HL,(AST_UP)
        RET

; ---------------------------------------------------------------------------
; MOON PHASE from corrected Moon/Sun ecliptic longitude at current vector.
; 0 => NEW, 100 => FULL, 1..99 numeric PHASE.
; ---------------------------------------------------------------------------
G_CALC_MOON_PHASE:
        LD HL,(G_MOON_LON)
        LD DE,(G_SUN_LON)
        OR A
        SBC HL,DE
        CALL ASTRO_NORM3600_SIGNED
        PUSH HL
        LD DE,1800
        OR A
        SBC HL,DE
        LD A,0                       ; 0 = waxing for elongation < 180 deg
        JR C,G_PHASE_DIR_STORE
        INC A                        ; 1 = waning for elongation >= 180 deg
G_PHASE_DIR_STORE:
        LD (G_PHASE_DIR),A
        POP HL
        CALL ASTRO_COS10_SIGNED
        EX DE,HL                   ; DE=cos Q15 signed
        LD HL,32767
        OR A
        SBC HL,DE                  ; 0..65534
        ; divide by 655, quotient 0..100
        LD B,0
        LD DE,655
G_PHASE_DIV:
        OR A
        SBC HL,DE
        JR C,G_PHASE_DONE
        INC B
        JR G_PHASE_DIV
G_PHASE_DONE:
        LD A,B
        CP 101
        JR C,G_PHASE_STORE
        LD A,100
G_PHASE_STORE:
        LD (G_PHASE),A
        RET

; ---------------------------------------------------------------------------
; PLUTO SPECIAL LOW-PRECISION MODEL (Schlyter-style periodic series).
; input uses current G_UTC_MIN. returns through G_ECL_TO_EQ.
; ---------------------------------------------------------------------------
G_VECTOR_PLUTO:
        ; For the 0.1-degree Z80 model, evolve S, P and base longitude using
        ; small linear rates from AST_DAYS; fractional day is negligible here.
        LD HL,500
        LD (G_CALC_BASE),HL
        LD HL,3346
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_TMPW0),HL            ; S
        LD HL,2390
        LD (G_CALC_BASE),HL
        LD HL,397
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_TMPW1),HL            ; P
        LD HL,2390
        LD (G_CALC_BASE),HL
        LD HL,401
        LD (G_CALC_RATE),HL
        CALL G_CALC_SMALL
        LD (G_LON),HL              ; base lon
        ; longitude periodic terms (tenths deg)
        LD HL,0
        LD (G_PSUM),HL
        LD HL,(G_TMPW1)
        LD DE,-198
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        LD DE,198
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        LD DE,9
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        LD DE,-50
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,DE                  ; 3P
        LD DE,6
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,DE
        LD DE,12
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        ADD HL,HL                  ; 4P
        LD DE,-3
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        ADD HL,HL
        LD DE,-2
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE                  ; 5P
        LD DE,1
        CALL G_ADD_SIN_TERM
        LD HL,(G_LON)
        LD DE,(G_PSUM)
        ADD HL,DE
        CALL ASTRO_NORM3600_SIGNED
        LD (G_LON),HL

        ; latitude base -39 tenths + periodic terms
        LD HL,-39
        LD (G_PSUM),HL
        LD HL,(G_TMPW1)
        LD DE,-55
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        LD DE,-150
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        LD DE,35
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        LD DE,17
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,DE
        LD DE,-11
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,DE
        LD DE,3
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        ADD HL,HL
        LD DE,2
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        ADD HL,HL
        LD DE,-3
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        LD DE,1
        CALL G_ADD_COS_TERM
        LD HL,(G_PSUM)
        LD (G_LAT),HL

        ; radius in units of 1/512 AU: base 40.72 AU = 20849
        LD HL,20849
        LD (G_PSUM),HL
        LD HL,(G_TMPW1)
        LD DE,3420
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        LD DE,3533
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        LD DE,-604
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        ADD HL,HL
        LD DE,-15
        CALL G_ADD_COS_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,DE
        LD DE,77
        CALL G_ADD_SIN_TERM
        LD HL,(G_TMPW1)
        LD DE,(G_TMPW1)
        ADD HL,HL
        ADD HL,DE
        LD DE,-72
        CALL G_ADD_COS_TERM
        LD HL,(G_PSUM)
        LD (G_TMPW2),HL            ; r

        ; heliocentric xyz from lon/lat/r
        LD HL,(G_LAT)
        CALL ASTRO_COS10_SIGNED
        LD (G_TMPW3),HL            ; coslat
        LD HL,(G_LON)
        CALL ASTRO_COS10
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_XH),HL
        LD HL,(G_LON)
        CALL ASTRO_SIN10
        LD DE,(G_TMPW3)
        CALL ASTRO_MUL_Q15
        EX DE,HL
        LD HL,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_YH),HL
        LD HL,(G_LAT)
        CALL ASTRO_SIN10_SIGNED
        EX DE,HL
        LD HL,(G_TMPW2)
        CALL ASTRO_MUL_Q15
        LD (G_ZH),HL
        ; geocentric = heliocentric + Sun
        LD HL,(G_XH)
        LD DE,(G_SX)
        ADD HL,DE
        LD (G_XH),HL
        LD HL,(G_YH)
        LD DE,(G_SY)
        ADD HL,DE
        LD (G_YH),HL
        JP G_ECL_TO_EQ

; ---------------------------------------------------------------------------
; PLANET TABLES (30 bytes each)
; N0,NR,I0,IR,W0,WR,M0,MI,MF,MX100,A,AE,B,K1,K2
; Coordinates use 512 units/AU.
; ---------------------------------------------------------------------------
G_PLANET_PTRS:
        DW G_TAB_MERCURY,G_TAB_VENUS,G_TAB_MARS,G_TAB_JUPITER
        DW G_TAB_SATURN,G_TAB_URANUS,G_TAB_NEPTUNE
G_TAB_MERCURY:
        DW 483,3,70,0,291,1,1687,40,9233,4092,198,41,194,118,12
G_TAB_VENUS:
        DW 767,2,34,0,549,1,480,16,213,1602,370,3,370,4,0
G_TAB_MARS:
        DW 496,2,18,0,2865,3,186,5,2402,524,780,73,777,54,2
G_TAB_JUPITER:
        DW 1005,3,13,0,2739,2,199,0,8309,83,2664,129,2661,28,1
G_TAB_SATURN:
        DW 1137,2,25,0,3394,3,3170,0,3344,33,4892,272,4884,32,1
G_TAB_URANUS:
        DW 740,1,8,0,967,3,1426,0,1173,12,9821,465,9810,27,1
G_TAB_NEPTUNE:
        DW 1318,3,18,0,2728,-1,2602,0,600,6,15390,132,15389,5,0


; ============================================================================
; V11 GPS RMC INPUT
; Wait for checksum-valid $GPRMC/$GNRMC status A, capture UTC and site, then
; ask once for the local UTC offset.  * decrements one hour, # increments one
; hour, ENTER accepts.  The selected offset is then applied to the GPS UTC,
; and the resulting local civil time is written to the battery-backed RTC.
; ============================================================================

GPS_STARTUP_WAIT:
        CALL ASTRO_CLOCK_INIT
        LD HL,0
        LD (AST_UTC_OFFSET_MIN),HL
        XOR A
        LD (AST_UTC_OFFSET_HR),A
        LD (GPS_COLLECTING),A
        LD (GPS_INDEX),A
        LD (GPS_FIX_READY),A
        LD HL,GMSG_ACQUIRING_GPS
        CALL DISPLAY_SHOW
GPS_WAIT_LOOP:
        ; Allow ALPHA to restart while waiting for GPS.
        CALL KEY_SCAN
        CP KEY_ALPHA
        JP Z,G_FULL_RESET

        IN A,(DART_B_CTRL)
        AND $01
        JR Z,GPS_WAIT_LOOP
        IN A,(DART_B_DATA)
        CALL GPS_RX_BYTE
        LD A,(GPS_FIX_READY)
        OR A
        JR Z,GPS_WAIT_LOOP

        LD HL,GMSG_GPS_FIX
        CALL DISPLAY_SHOW
        CALL GPS_DELAY_1S
        CALL GPS_SELECT_UTC_OFFSET
        CALL GPS_APPLY_OFFSET_TO_LOCAL
        CALL RTC_WRITE_LOCAL
        LD A,1
        LD (AST_CLOCK_OK),A
        RET

; Select one whole-hour local offset from UTC, once after each fresh GPS fix.
; Starts at UTC+00.  * moves west/down one hour; # moves east/up one hour.
; Range is UTC-12 through UTC+12.  CLEAR resets the choice to UTC+00.
GPS_SELECT_UTC_OFFSET:
        XOR A
        LD (AST_UTC_OFFSET_HR),A
GPS_UTC_OFFSET_DRAW:
        CALL DISPLAY_CLEAR
        LD HL,GMSG_UTC_SELECT
        CALL DISPLAY_PRINT_Z
        LD A,(AST_UTC_OFFSET_HR)
        BIT 7,A
        JR NZ,GPS_UTC_OFFSET_NEG_DRAW
        PUSH AF
        LD A,'+'
        CALL DISPLAY_PUT_ASCII
        POP AF
        JR GPS_UTC_OFFSET_MAG_DRAW
GPS_UTC_OFFSET_NEG_DRAW:
        PUSH AF
        LD A,'-'
        CALL DISPLAY_PUT_ASCII
        POP AF
        CPL
        INC A
GPS_UTC_OFFSET_MAG_DRAW:
        CALL DISPLAY_DEC2
GPS_UTC_OFFSET_KEY:
        CALL KEY_GET
        CP KEY_ALPHA
        JP Z,G_FULL_RESET
        CP KEY_CLEAR
        JR Z,GPS_SELECT_UTC_OFFSET
        CP KEY_ENTER
        JR Z,GPS_UTC_OFFSET_ACCEPT
        CP KEY_UTC_NEG             ; * = one hour more negative
        JR Z,GPS_UTC_OFFSET_DEC
        CP KEY_UTC_POS             ; # = one hour more positive
        JR Z,GPS_UTC_OFFSET_INC
        JR GPS_UTC_OFFSET_KEY
GPS_UTC_OFFSET_DEC:
        LD A,(AST_UTC_OFFSET_HR)
        CP $F4                     ; -12 in 8-bit two's complement
        JR Z,GPS_UTC_OFFSET_DRAW
        DEC A
        LD (AST_UTC_OFFSET_HR),A
        JR GPS_UTC_OFFSET_DRAW
GPS_UTC_OFFSET_INC:
        LD A,(AST_UTC_OFFSET_HR)
        CP 12
        JR Z,GPS_UTC_OFFSET_DRAW
        INC A
        LD (AST_UTC_OFFSET_HR),A
        JR GPS_UTC_OFFSET_DRAW
GPS_UTC_OFFSET_ACCEPT:
        ; Convert signed whole hours to signed minutes for all astronomy math.
        LD A,(AST_UTC_OFFSET_HR)
        LD L,A
        LD H,0
        BIT 7,A
        JR Z,GPS_UTC_OFFSET_EXTENDED
        LD H,$FF
GPS_UTC_OFFSET_EXTENDED:
        PUSH HL                    ; x1
        ADD HL,HL                 ; x2
        ADD HL,HL                 ; x4
        EX DE,HL                  ; DE=x4
        POP HL                    ; HL=x1
        ADD HL,HL                 ; x2
        ADD HL,HL                 ; x4
        ADD HL,HL                 ; x8
        ADD HL,HL                 ; x16
        ADD HL,HL                 ; x32
        ADD HL,HL                 ; x64
        OR A
        SBC HL,DE                 ; x60
        LD (AST_UTC_OFFSET_MIN),HL
        RET

; Convert the just-received GPS UTC date/time to selected local civil time.
; Offset range is only +/-12h, so at most one calendar-day adjustment occurs.
GPS_APPLY_OFFSET_TO_LOCAL:
        LD A,(GPS_UTC_YEAR)
        LD (AST_YEAR),A
        LD A,(GPS_UTC_MONTH)
        LD (AST_MONTH),A
        LD A,(GPS_UTC_DAY)
        LD (AST_DAY),A
        LD A,(GPS_UTC_MINUTE)
        LD (AST_MINUTE),A
        LD A,(GPS_UTC_SECOND)
        LD (AST_SECOND),A

        LD A,(GPS_UTC_HOUR)
        LD L,A
        LD H,0
        LD A,(AST_UTC_OFFSET_HR)
        LD E,A
        LD D,0
        BIT 7,A
        JR Z,GPS_APPLY_OFFSET_EXTENDED
        LD D,$FF
GPS_APPLY_OFFSET_EXTENDED:
        ADD HL,DE
        BIT 7,H
        JR Z,GPS_APPLY_OFFSET_NONNEG
        LD DE,24
        ADD HL,DE
        LD A,L
        LD (AST_HOUR),A
        CALL GPS_LOCAL_PREVIOUS_DAY
        RET
GPS_APPLY_OFFSET_NONNEG:
        LD A,H
        OR A
        JR NZ,GPS_APPLY_OFFSET_NEXT
        LD A,L
        CP 24
        JR NC,GPS_APPLY_OFFSET_NEXT
        LD (AST_HOUR),A
        RET
GPS_APPLY_OFFSET_NEXT:
        LD DE,24
        OR A
        SBC HL,DE
        LD A,L
        LD (AST_HOUR),A
        CALL GPS_LOCAL_NEXT_DAY
        RET

GPS_DELAY_1S:
        LD B,250
GPS_D1_A:
        CALL DELAY_2MS
        DJNZ GPS_D1_A
        LD B,250
GPS_D1_B:
        CALL DELAY_2MS
        DJNZ GPS_D1_B
        RET

; A = received byte. '$' always re-synchronizes. CR/LF terminates a sentence.
GPS_RX_BYTE:
        LD (GPS_RX_SAVED),A
        CP '$'
        JR Z,GPS_RX_DOLLAR
        LD D,A
        LD A,(GPS_COLLECTING)
        OR A
        RET Z
        LD A,D
        CP 13
        JR Z,GPS_RX_END
        CP 10
        JR Z,GPS_RX_END

        LD A,(GPS_INDEX)
        CP 79
        JR NC,GPS_RX_ABORT
        LD E,A
        LD D,0
        LD HL,GPS_BUFFER
        ADD HL,DE
        LD A,(GPS_RX_SAVED)
        LD (HL),A
        LD A,(GPS_INDEX)
        INC A
        LD (GPS_INDEX),A
        RET

GPS_RX_DOLLAR:
        LD A,1
        LD (GPS_COLLECTING),A
        LD A,1
        LD (GPS_INDEX),A
        LD A,'$'
        LD (GPS_BUFFER),A
        RET

GPS_RX_END:
        XOR A
        LD (GPS_COLLECTING),A
        LD A,(GPS_INDEX)
        OR A
        RET Z
        LD E,A
        LD D,0
        LD HL,GPS_BUFFER
        ADD HL,DE
        XOR A
        LD (HL),A
        CALL GPS_PARSE_RMC
        RET

GPS_RX_ABORT:
        XOR A
        LD (GPS_COLLECTING),A
        LD (GPS_INDEX),A
        RET

; ---------------------------------------------------------------------------
; Checksum-valid RMC parser. All required fields are first parsed into
; temporary RAM. Astronomy-visible state is committed only after the complete
; sentence validates, so a malformed sentence cannot partially update time/site.
; ---------------------------------------------------------------------------
GPS_PARSE_RMC:
        CALL GPS_VALIDATE_CHECKSUM
        RET C

        LD HL,GPS_BUFFER+1
        LD A,(HL)
        CP 'G'
        RET NZ
        INC HL
        LD A,(HL)
        CP 'P'
        JR Z,GPS_PR_TALKER_OK
        CP 'N'
        RET NZ
GPS_PR_TALKER_OK:
        INC HL
        LD A,(HL)
        CP 'R'
        RET NZ
        INC HL
        LD A,(HL)
        CP 'M'
        RET NZ
        INC HL
        LD A,(HL)
        CP 'C'
        RET NZ
        INC HL
        LD A,(HL)
        CP ','
        RET NZ
        INC HL

        ; UTC hhmmss[.ss]
        CALL GPS_PARSE_TIME
        RET C

        ; Status must be A and field must be exactly one character.
        LD A,(HL)
        CP 'A'
        RET NZ
        INC HL
        LD A,(HL)
        CP ','
        RET NZ
        INC HL

        ; Latitude ddmm.mmmmm
        CALL GPS_PARSE_LAT_FIELD
        RET C
        LD A,(HL)
        CP 'N'
        JR Z,GPS_LAT_HEMI_OK
        CP 'S'
        RET NZ
GPS_LAT_HEMI_OK:
        LD (GPS_TMP_LAT_HEMI),A
        INC HL
        LD A,(HL)
        CP ','
        RET NZ
        INC HL

        ; Longitude dddmm.mmmmm
        CALL GPS_PARSE_LON_FIELD
        RET C
        LD A,(HL)
        CP 'E'
        JR Z,GPS_LON_HEMI_OK
        CP 'W'
        RET NZ
GPS_LON_HEMI_OK:
        LD (GPS_TMP_LON_HEMI),A
        INC HL
        LD A,(HL)
        CP ','
        RET NZ
        INC HL

        ; Skip speed and course fields.
        CALL GPS_SKIP_FIELD
        RET C
        CALL GPS_SKIP_FIELD
        RET C

        ; Date ddmmyy
        CALL GPS_PARSE_DATE
        RET C

        ; We have a complete, checksum-valid active RMC sentence.
        CALL GPS_COMMIT_FIX
        RET

; A checksum failure returns carry set. Checksum is XOR of bytes after '$'
; through byte before '*', compared to the two ASCII hex digits after '*'.
GPS_VALIDATE_CHECKSUM:
        LD HL,GPS_BUFFER
        LD A,(HL)
        CP '$'
        JR NZ,GPS_CKS_BAD
        INC HL
        LD B,0
GPS_CKS_LOOP:
        LD A,(HL)
        OR A
        JR Z,GPS_CKS_BAD
        CP '*'
        JR Z,GPS_CKS_STAR
        LD C,A
        LD A,B
        XOR C
        LD B,A
        INC HL
        JR GPS_CKS_LOOP
GPS_CKS_STAR:
        INC HL
        LD A,(HL)
        CALL GPS_HEX_NIBBLE
        JR C,GPS_CKS_BAD
        ADD A,A
        ADD A,A
        ADD A,A
        ADD A,A
        LD D,A
        INC HL
        LD A,(HL)
        CALL GPS_HEX_NIBBLE
        JR C,GPS_CKS_BAD
        OR D
        CP B
        JR NZ,GPS_CKS_BAD
        OR A
        RET
GPS_CKS_BAD:
        SCF
        RET

; ASCII hex nibble -> A=0..15, carry on invalid.
GPS_HEX_NIBBLE:
        CP '0'
        JR C,GPS_HEX_BAD
        CP '9'+1
        JR C,GPS_HEX_DEC
        CP 'A'
        JR C,GPS_HEX_LOWER_TEST
        CP 'F'+1
        JR C,GPS_HEX_UPPER
GPS_HEX_LOWER_TEST:
        CP 'a'
        JR C,GPS_HEX_BAD
        CP 'f'+1
        JR NC,GPS_HEX_BAD
        SUB 'a'-10
        OR A
        RET
GPS_HEX_UPPER:
        SUB 'A'-10
        OR A
        RET
GPS_HEX_DEC:
        SUB '0'
        OR A
        RET
GPS_HEX_BAD:
        SCF
        RET

; Parse two decimal digits at (HL), advance HL by two, A=value, carry invalid.
GPS_PARSE_2DIG:
        LD A,(HL)
        CALL GPS_ASCII_DIGIT
        RET C
        LD B,A
        INC HL
        LD A,(HL)
        CALL GPS_ASCII_DIGIT
        RET C
        LD C,A
        INC HL
        LD A,B
        ADD A,A
        LD D,A
        ADD A,A
        ADD A,A
        ADD A,D
        ADD A,C
        OR A
        RET

GPS_ASCII_DIGIT:
        CP '0'
        JR C,GPS_DIG_BAD
        CP '9'+1
        JR NC,GPS_DIG_BAD
        SUB '0'
        OR A
        RET
GPS_DIG_BAD:
        SCF
        RET

GPS_PARSE_TIME:
        CALL GPS_PARSE_2DIG
        RET C
        CP 24
        JR NC,GPS_TIME_BAD
        LD (GPS_TMP_UTC_HOUR),A
        CALL GPS_PARSE_2DIG
        RET C
        CP 60
        JR NC,GPS_TIME_BAD
        LD (GPS_TMP_UTC_MIN),A
        CALL GPS_PARSE_2DIG
        RET C
        CP 60
        JR NC,GPS_TIME_BAD
        LD (GPS_TMP_UTC_SEC),A
        LD A,(HL)
        CP '.'
        JR NZ,GPS_TIME_COMMA
        INC HL
GPS_TIME_FRAC:
        LD A,(HL)
        CP ','
        JR Z,GPS_TIME_DONE
        CALL GPS_ASCII_DIGIT
        RET C
        INC HL
        JR GPS_TIME_FRAC
GPS_TIME_COMMA:
        LD A,(HL)
        CP ','
        JR NZ,GPS_TIME_BAD
GPS_TIME_DONE:
        INC HL
        OR A
        RET
GPS_TIME_BAD:
        SCF
        RET

GPS_PARSE_DATE:
        CALL GPS_PARSE_2DIG
        RET C
        OR A
        JR Z,GPS_DATE_BAD
        CP 32
        JR NC,GPS_DATE_BAD
        LD (GPS_TMP_UTC_DAY),A
        CALL GPS_PARSE_2DIG
        RET C
        OR A
        JR Z,GPS_DATE_BAD
        CP 13
        JR NC,GPS_DATE_BAD
        LD (GPS_TMP_UTC_MONTH),A
        CALL GPS_PARSE_2DIG
        RET C
        LD (GPS_TMP_UTC_YEAR),A
        ; RMC date is followed by comma or '*' depending on optional fields.
        LD A,(HL)
        CP ','
        JR Z,GPS_DATE_RANGE
        CP '*'
        JR NZ,GPS_DATE_BAD
GPS_DATE_RANGE:
        ; Validate day against parsed month/year without touching AST date.
        CALL GPS_TMP_DAYS_IN_MONTH
        LD B,A
        LD A,(GPS_TMP_UTC_DAY)
        CP B
        JR C,GPS_DATE_OK
        JR Z,GPS_DATE_OK
GPS_DATE_BAD:
        SCF
        RET
GPS_DATE_OK:
        OR A
        RET

; HL at field start. Advance through field and comma. Empty fields are allowed.
GPS_SKIP_FIELD:
GPS_SKIP_LOOP:
        LD A,(HL)
        OR A
        JR Z,GPS_SKIP_BAD
        CP ','
        JR Z,GPS_SKIP_DONE
        CP '*'
        JR Z,GPS_SKIP_BAD
        INC HL
        JR GPS_SKIP_LOOP
GPS_SKIP_DONE:
        INC HL
        OR A
        RET
GPS_SKIP_BAD:
        SCF
        RET

; Latitude field: DDMM.m...  Longitude field: DDDMM.m...
; Outputs temporary degree byte, 3-decimal degree fraction, and angle10.
GPS_PARSE_LAT_FIELD:
        CALL GPS_PARSE_2DIG
        RET C
        CP 91
        JP NC,GPS_COORD_BAD             ; V11d10a: was JR at +126, only 1 byte from limit
        LD (GPS_TMP_COORD_DEG),A
        LD (GPS_TMP_COORD_ORIG_DEG),A
        CALL GPS_PARSE_MINUTES
        RET C
        ; 90 degrees is valid only with 00.000 minutes.
        LD A,(GPS_TMP_COORD_ORIG_DEG)
        CP 90
        JR NZ,GPS_LAT_RANGE_OK
        LD HL,(GPS_TMP_MIN_MILLI)
        LD A,H
        OR L
        JR NZ,GPS_COORD_BAD
GPS_LAT_RANGE_OK:
        LD A,(GPS_TMP_COORD_DEG)
        LD (GPS_TMP_LAT_DEG),A
        LD HL,(GPS_TMP_COORD_FRAC3)
        LD (GPS_TMP_LAT_FRAC3),HL
        LD HL,(GPS_TMP_COORD_ANGLE10)
        LD (GPS_TMP_LAT10),HL
        LD HL,(GPS_FIELD_PTR)
        OR A
        RET

GPS_PARSE_LON_FIELD:
        ; Three degree digits, 000..180.
        LD A,(HL)
        CALL GPS_ASCII_DIGIT
        RET C
        PUSH AF                       ; preserve hundreds digit
        INC HL
        CALL GPS_PARSE_2DIG
        JR C,GPS_LON_POP_BAD
        LD C,A                        ; low two degree digits
        POP AF
        OR A
        JR Z,GPS_LON_DEG_HAVE
        ; 1xx only; 2xx is outside longitude range.
        CP 1
        JR NZ,GPS_COORD_BAD
        LD A,C
        ADD A,100
        JR GPS_LON_DEG_STORE
GPS_LON_DEG_HAVE:
        LD A,C
GPS_LON_DEG_STORE:
        CP 181
        JR NC,GPS_COORD_BAD
        LD (GPS_TMP_COORD_DEG),A
        LD (GPS_TMP_COORD_ORIG_DEG),A
        CALL GPS_PARSE_MINUTES
        RET C
        ; 180 degrees is valid only with 00.000 minutes.
        LD A,(GPS_TMP_COORD_ORIG_DEG)
        CP 180
        JR NZ,GPS_LON_RANGE_OK
        LD HL,(GPS_TMP_MIN_MILLI)
        LD A,H
        OR L
        JR NZ,GPS_COORD_BAD
GPS_LON_RANGE_OK:
        LD A,(GPS_TMP_COORD_DEG)
        LD (GPS_TMP_LON_DEG),A
        LD HL,(GPS_TMP_COORD_FRAC3)
        LD (GPS_TMP_LON_FRAC3),HL
        LD HL,(GPS_TMP_COORD_ANGLE10)
        LD (GPS_TMP_LON10),HL
        LD HL,(GPS_FIELD_PTR)
        OR A
        RET
GPS_LON_POP_BAD:
        POP AF
GPS_COORD_BAD:
        SCF
        RET

; Input HL points at MM.m... of a coordinate. Requires at least one
; fractional digit. Returns through GPS_FIELD_PTR with HL after the comma.
; Uses the first three fractional minute digits (zero-padded) for display
; rounding; later digits are syntactically validated and ignored.
GPS_PARSE_MINUTES:
        CALL GPS_PARSE_2DIG
        RET C
        CP 60
        JP NC,GPS_MIN_BAD
        LD (GPS_TMP_MINUTES),A
        LD A,(HL)
        CP '.'
        JP NZ,GPS_MIN_BAD
        INC HL
        XOR A
        LD (GPS_TMP_F1),A
        LD (GPS_TMP_F2),A
        LD (GPS_TMP_F3),A
        LD B,0
GPS_MIN_FRAC_LOOP:
        LD A,(HL)
        CP ','
        JR Z,GPS_MIN_FRAC_DONE
        CALL GPS_ASCII_DIGIT
        JP C,GPS_MIN_BAD
        LD C,A
        LD A,B
        OR A
        JR NZ,GPS_MIN_NOT_F1
        LD A,C
        LD (GPS_TMP_F1),A
        JR GPS_MIN_NEXT
GPS_MIN_NOT_F1:
        CP 1
        JR NZ,GPS_MIN_NOT_F2
        LD A,C
        LD (GPS_TMP_F2),A
        JR GPS_MIN_NEXT
GPS_MIN_NOT_F2:
        CP 2
        JR NZ,GPS_MIN_NEXT
        LD A,C
        LD (GPS_TMP_F3),A
GPS_MIN_NEXT:
        INC B
        INC HL
        JR GPS_MIN_FRAC_LOOP
GPS_MIN_FRAC_DONE:
        LD A,B
        OR A
        JP Z,GPS_MIN_BAD
        INC HL
        LD (GPS_FIELD_PTR),HL

        ; minute_milli = minutes*1000 + first three fractional digits.
        LD A,(GPS_TMP_MINUTES)
        LD L,A
        LD H,0
        CALL GPS_MUL10_HL
        CALL GPS_MUL10_HL
        CALL GPS_MUL10_HL
        PUSH HL
        LD A,(GPS_TMP_F1)
        LD L,A
        LD H,0
        CALL GPS_MUL10_HL
        CALL GPS_MUL10_HL
        LD D,H
        LD E,L
        LD A,(GPS_TMP_F2)
        LD L,A
        LD H,0
        CALL GPS_MUL10_HL
        ADD HL,DE
        LD A,(GPS_TMP_F3)
        LD E,A
        LD D,0
        ADD HL,DE
        EX DE,HL
        POP HL
        ADD HL,DE
        LD (GPS_TMP_MIN_MILLI),HL

        ; angle10 = original degree*10 + round(minute_milli / 6000).
        ; Do this BEFORE display rounding, because 59.999 minutes may carry
        ; the displayed coordinate into the next whole degree.
        LD HL,(GPS_TMP_MIN_MILLI)
        LD DE,3000
        ADD HL,DE
        LD DE,6000
        LD B,0
GPS_DIV6000_LOOP:
        OR A
        SBC HL,DE
        JR C,GPS_DIV6000_DONE
        INC B
        JR GPS_DIV6000_LOOP
GPS_DIV6000_DONE:
        LD A,(GPS_TMP_COORD_DEG)
        LD L,A
        LD H,0
        CALL GPS_MUL10_HL
        LD E,B
        LD D,0
        ADD HL,DE
        LD (GPS_TMP_COORD_ANGLE10),HL

        ; frac3 degrees = round(minute_milli / 60), 0..1000.
        LD HL,(GPS_TMP_MIN_MILLI)
        LD DE,30
        ADD HL,DE
        CALL GPS_DIV60_16
        LD DE,1000
        OR A
        SBC HL,DE
        JR C,GPS_FRAC_LT1000
        ; Rounded 59.999 minutes carries into the displayed next degree.
        LD HL,0
        LD A,(GPS_TMP_COORD_DEG)
        INC A
        LD (GPS_TMP_COORD_DEG),A
        JR GPS_FRAC_STORE
GPS_FRAC_LT1000:
        ADD HL,DE
GPS_FRAC_STORE:
        LD (GPS_TMP_COORD_FRAC3),HL
        LD HL,(GPS_FIELD_PTR)
        OR A
        RET
GPS_MIN_BAD:
        SCF
        RET

; 16-bit unsigned divide by 60 for values <= 60029. HL=quotient.
GPS_DIV60_16:
        LD BC,0
        LD DE,60
GPS_D60_16_LOOP:
        OR A
        SBC HL,DE
        JR C,GPS_D60_16_DONE
        INC BC
        JR GPS_D60_16_LOOP
GPS_D60_16_DONE:
        LD H,B
        LD L,C
        RET

GPS_MUL10_HL:
        ADD HL,HL
        LD D,H
        LD E,L
        ADD HL,HL
        ADD HL,HL
        ADD HL,DE
        RET

; Days in GPS temporary UTC month/year. 2000..2099 leap rule.
GPS_TMP_DAYS_IN_MONTH:
        LD A,(GPS_TMP_UTC_MONTH)
        CP 2
        JR Z,GPS_TDIM_FEB
        CP 4
        JR Z,GPS_TDIM_30
        CP 6
        JR Z,GPS_TDIM_30
        CP 9
        JR Z,GPS_TDIM_30
        CP 11
        JR Z,GPS_TDIM_30
        LD A,31
        RET
GPS_TDIM_30:
        LD A,30
        RET
GPS_TDIM_FEB:
        LD A,(GPS_TMP_UTC_YEAR)
        AND 3
        LD A,28
        RET NZ
        INC A
        RET

GPS_COMMIT_FIX:
        ; Save UTC components exactly as received from RMC.
        LD A,(GPS_TMP_UTC_YEAR)
        LD (GPS_UTC_YEAR),A
        LD A,(GPS_TMP_UTC_MONTH)
        LD (GPS_UTC_MONTH),A
        LD A,(GPS_TMP_UTC_DAY)
        LD (GPS_UTC_DAY),A
        LD A,(GPS_TMP_UTC_HOUR)
        LD (GPS_UTC_HOUR),A
        LD A,(GPS_TMP_UTC_MIN)
        LD (GPS_UTC_MINUTE),A
        LD A,(GPS_TMP_UTC_SEC)
        LD (GPS_UTC_SECOND),A

        ; Save display coordinates and hemispheres.
        LD A,(GPS_TMP_LAT_DEG)
        LD (GPS_SITE_LAT_DEG),A
        LD HL,(GPS_TMP_LAT_FRAC3)
        LD (GPS_SITE_LAT_FRAC3),HL
        LD A,(GPS_TMP_LAT_HEMI)
        LD (GPS_SITE_LAT_HEMI),A
        LD A,(GPS_TMP_LON_DEG)
        LD (GPS_SITE_LON_DEG),A
        LD HL,(GPS_TMP_LON_FRAC3)
        LD (GPS_SITE_LON_FRAC3),HL
        LD A,(GPS_TMP_LON_HEMI)
        LD (GPS_SITE_LON_HEMI),A

        ; Signed latitude angle10.
        LD HL,(GPS_TMP_LAT10)
        LD A,(GPS_TMP_LAT_HEMI)
        CP 'S'
        JR NZ,GPS_LAT10_SIGNED
        CALL ASTRO_NEG_HL
GPS_LAT10_SIGNED:
        LD (G_SITE_LAT10),HL

        ; Signed longitude angle10: west negative, east positive.
        LD HL,(GPS_TMP_LON10)
        LD A,(GPS_TMP_LON_HEMI)
        CP 'W'
        JR NZ,GPS_LON10_SIGNED
        CALL ASTRO_NEG_HL
GPS_LON10_SIGNED:
        LD (G_SITE_LON10),HL

        ; Runtime latitude trig used by every old and new horizontal path.
        LD HL,(G_SITE_LAT10)
        CALL ASTRO_SIN10_SIGNED
        LD (G_SITE_LAT_SIN_Q15),HL
        LD HL,(G_SITE_LAT10)
        CALL ASTRO_COS10_SIGNED
        LD (G_SITE_LAT_COS_Q15),HL

        ; A valid fix only captures GPS UTC/site here.  The startup path now
        ; asks for the local UTC offset exactly once before converting time
        ; or touching the RTC.
        LD A,1
        LD (GPS_FIX_READY),A
        RET

GPS_LOCAL_PREVIOUS_DAY:
        LD A,(AST_DAY)
        DEC A
        JR NZ,GPS_LPD_STORE_DAY
        LD A,(AST_MONTH)
        DEC A
        JR NZ,GPS_LPD_HAVE_MONTH
        LD A,12
        LD (AST_MONTH),A
        LD A,(AST_YEAR)
        DEC A
        CP $FF
        JR NZ,GPS_LPD_STORE_YEAR
        LD A,99
GPS_LPD_STORE_YEAR:
        LD (AST_YEAR),A
        JR GPS_LPD_GET_LAST
GPS_LPD_HAVE_MONTH:
        LD (AST_MONTH),A
GPS_LPD_GET_LAST:
        CALL ASTRO_DAYS_IN_MONTH
GPS_LPD_STORE_DAY:
        LD (AST_DAY),A
        RET


; Advance AST local calendar by one day (2000..2099).
GPS_LOCAL_NEXT_DAY:
        LD A,(AST_DAY)
        INC A
        LD B,A
        CALL ASTRO_DAYS_IN_MONTH
        CP B
        JR NC,GPS_LND_STORE_DAY
        LD A,1
        LD (AST_DAY),A
        LD A,(AST_MONTH)
        INC A
        CP 13
        JR C,GPS_LND_STORE_MONTH
        LD A,1
        LD (AST_MONTH),A
        LD A,(AST_YEAR)
        INC A
        CP 100
        JR C,GPS_LND_STORE_YEAR
        XOR A
GPS_LND_STORE_YEAR:
        LD (AST_YEAR),A
        RET
GPS_LND_STORE_MONTH:
        LD (AST_MONTH),A
        RET
GPS_LND_STORE_DAY:
        LD A,B
        LD (AST_DAY),A
        RET

; ---------------------------------------------------------------------------
; Dynamic result displays.
; ---------------------------------------------------------------------------
G_DRAW_UTC_DATE_TIME:
        ; Refresh local civil time from the battery-backed RTC every time this
        ; result screen is entered, then derive UTC using the one-time offset
        ; selected immediately after GPS acquisition.
        CALL ASTRO_CLOCK_INIT
        CALL G_RTC_LOCAL_TO_UTC
        CALL DISPLAY_CLEAR
        LD A,(GPS_UTC_MONTH)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(GPS_UTC_DAY)
        CALL DISPLAY_DEC2
        LD A,'/'
        CALL DISPLAY_PUT_ASCII
        LD A,(GPS_UTC_YEAR)
        CALL DISPLAY_DEC2
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(GPS_UTC_HOUR)
        CALL DISPLAY_DEC2
        LD A,':'
        CALL DISPLAY_PUT_ASCII
        LD A,(GPS_UTC_MINUTE)
        CALL DISPLAY_DEC2
        LD A,'U'
        JP DISPLAY_PUT_ASCII

; Build dynamic UTC display fields from current RTC local time.
; UTC = local - selected signed whole-hour offset.  Because the supported
; range is +/-12 hours, at most one date rollover is required.
G_RTC_LOCAL_TO_UTC:
        LD A,(AST_YEAR)
        LD (GPS_UTC_YEAR),A
        LD A,(AST_MONTH)
        LD (GPS_UTC_MONTH),A
        LD A,(AST_DAY)
        LD (GPS_UTC_DAY),A
        LD A,(AST_MINUTE)
        LD (GPS_UTC_MINUTE),A
        LD A,(AST_SECOND)
        LD (GPS_UTC_SECOND),A

        LD A,(AST_HOUR)
        LD L,A
        LD H,0
        LD A,(AST_UTC_OFFSET_HR)
        LD E,A
        LD D,0
        BIT 7,A
        JR Z,G_RTC_UTC_OFFSET_EXTENDED
        LD D,$FF
G_RTC_UTC_OFFSET_EXTENDED:
        OR A
        SBC HL,DE                 ; UTC hour = local hour - offset
        BIT 7,H
        JR Z,G_RTC_UTC_NONNEG
        LD DE,24
        ADD HL,DE
        LD A,L
        LD (GPS_UTC_HOUR),A
        CALL G_RTC_UTC_PREVIOUS_DAY
        RET
G_RTC_UTC_NONNEG:
        LD A,H
        OR A
        JR NZ,G_RTC_UTC_NEXT_DAY
        LD A,L
        CP 24
        JR NC,G_RTC_UTC_NEXT_DAY
        LD (GPS_UTC_HOUR),A
        RET
G_RTC_UTC_NEXT_DAY:
        LD DE,24
        OR A
        SBC HL,DE
        LD A,L
        LD (GPS_UTC_HOUR),A
        CALL G_RTC_UTC_ADVANCE_DAY
        RET

G_RTC_UTC_PREVIOUS_DAY:
        LD A,(GPS_UTC_DAY)
        DEC A
        JR NZ,G_RTC_UTC_PREV_STORE_DAY
        LD A,(GPS_UTC_MONTH)
        DEC A
        JR NZ,G_RTC_UTC_PREV_HAVE_MONTH
        LD A,12
        LD (GPS_UTC_MONTH),A
        LD A,(GPS_UTC_YEAR)
        DEC A
        CP $FF
        JR NZ,G_RTC_UTC_PREV_STORE_YEAR
        LD A,99
G_RTC_UTC_PREV_STORE_YEAR:
        LD (GPS_UTC_YEAR),A
        JR G_RTC_UTC_PREV_MONTH_READY
G_RTC_UTC_PREV_HAVE_MONTH:
        LD (GPS_UTC_MONTH),A
G_RTC_UTC_PREV_MONTH_READY:
        CALL G_RTC_UTC_DAYS_IN_MONTH
G_RTC_UTC_PREV_STORE_DAY:
        LD (GPS_UTC_DAY),A
        RET

G_RTC_UTC_ADVANCE_DAY:
        LD A,(GPS_UTC_DAY)
        INC A
        LD B,A
        CALL G_RTC_UTC_DAYS_IN_MONTH
        CP B
        JR NC,G_RTC_UTC_NEXT_STORE_DAY
        LD A,1
        LD (GPS_UTC_DAY),A
        LD A,(GPS_UTC_MONTH)
        INC A
        CP 13
        JR C,G_RTC_UTC_NEXT_STORE_MONTH
        LD A,1
        LD (GPS_UTC_MONTH),A
        LD A,(GPS_UTC_YEAR)
        INC A
        CP 100
        JR C,G_RTC_UTC_NEXT_STORE_YEAR
        XOR A
G_RTC_UTC_NEXT_STORE_YEAR:
        LD (GPS_UTC_YEAR),A
        RET
G_RTC_UTC_NEXT_STORE_MONTH:
        LD (GPS_UTC_MONTH),A
        RET
G_RTC_UTC_NEXT_STORE_DAY:
        LD A,B
        LD (GPS_UTC_DAY),A
        RET

; Month length for GPS_UTC_* display date, 2000..2099 leap rule.
G_RTC_UTC_DAYS_IN_MONTH:
        LD A,(GPS_UTC_MONTH)
        CP 2
        JR Z,G_RTC_UTC_DIM_FEB
        CP 4
        JR Z,G_RTC_UTC_DIM_30
        CP 6
        JR Z,G_RTC_UTC_DIM_30
        CP 9
        JR Z,G_RTC_UTC_DIM_30
        CP 11
        JR Z,G_RTC_UTC_DIM_30
        LD A,31
        RET
G_RTC_UTC_DIM_30:
        LD A,30
        RET
G_RTC_UTC_DIM_FEB:
        LD A,(GPS_UTC_YEAR)
        AND 3
        LD A,28
        RET NZ
        INC A
        RET

G_DRAW_LAT_LON_DYNAMIC:
        CALL DISPLAY_CLEAR
        LD A,(GPS_SITE_LAT_DEG)
        CALL DISPLAY_DEC2
        LD A,'.'
        CALL DISPLAY_PUT_ASCII
        LD HL,(GPS_SITE_LAT_FRAC3)
        CALL GPS_PRINT_3DIG
        LD A,(GPS_SITE_LAT_HEMI)
        CALL DISPLAY_PUT_ASCII
        LD A,' '
        CALL DISPLAY_PUT_ASCII
        LD A,(GPS_SITE_LON_DEG)
        CALL GPS_PRINT_3DIG_A
        LD A,'.'
        CALL DISPLAY_PUT_ASCII
        LD HL,(GPS_SITE_LON_FRAC3)
        CALL GPS_PRINT_3DIG
        LD A,(GPS_SITE_LON_HEMI)
        JP DISPLAY_PUT_ASCII

; Print A as exactly 3 decimal digits, 000..180.
GPS_PRINT_3DIG_A:
        LD B,0
GPS_P3A_HUND:
        CP 100
        JR C,GPS_P3A_TENS
        SUB 100
        INC B
        JR GPS_P3A_HUND
GPS_P3A_TENS:
        LD C,A
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,C
        LD B,0
GPS_P3A_TLOOP:
        CP 10
        JR C,GPS_P3A_ONES
        SUB 10
        INC B
        JR GPS_P3A_TLOOP
GPS_P3A_ONES:
        LD C,A
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,C
        ADD A,'0'
        JP DISPLAY_PUT_ASCII

; Print HL as exactly 3 decimal digits, 000..999.
GPS_PRINT_3DIG:
        LD B,0
        LD DE,100
GPS_P3_HUND:
        OR A
        SBC HL,DE
        JR C,GPS_P3_HDONE
        INC B
        JR GPS_P3_HUND
GPS_P3_HDONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD B,0
        LD DE,10
GPS_P3_TENS:
        OR A
        SBC HL,DE
        JR C,GPS_P3_TDONE
        INC B
        JR GPS_P3_TENS
GPS_P3_TDONE:
        ADD HL,DE
        LD A,B
        ADD A,'0'
        CALL DISPLAY_PUT_ASCII
        LD A,L
        ADD A,'0'
        JP DISPLAY_PUT_ASCII


; ---------------------------------------------------------------------------
; DISPLAY STRINGS
; ---------------------------------------------------------------------------
MSG_PLANET_TRACKER:  DB "Z PLANET TRACKER",0
GMSG_ACQUIRING_GPS:  DB "AQUIRING GPS FIX",0
GMSG_GPS_FIX:        DB "GPS FIX",0
GMSG_OPTION:         DB "OPTION 0 - 9?",0
GMSG_ENTER_SUFFIX:   DB " ENTER",0
GMSG_CALC_SUFFIX:    DB " CALC",0
GMSG_VIS_SUFFIX:     DB " VIS",0
GMSG_NOT_VIS_SUFFIX: DB " NOT VIS",0
GMSG_DATE_TIME:      DB "09/08/26 12:00",0
GMSG_LAT_LON:        DB "30.364N 088.755W",0
GMSG_WAXING:         DB "WAXING",0
GMSG_WANING:         DB "WANING",0
GMSG_NEW_PHASE:      DB "NEW 0%",0
GMSG_FULL_PHASE:     DB "FULL 100%",0
GMSG_PRESS_ENTER: DB "PRESS ENTER",0
GMSG_FIXED_JUPITER: DB "JUPITER",0
GMSG_FIXED_DATE: DB "09/08/2026",0
GMSG_FIXED_TIME: DB "12:00:00 UTC-5",0
GMSG_FIXED_LAT: DB "30.364 N",0
GMSG_FIXED_LON: DB "088.755 W",0
GMSG_SELECT:    DB "SELECT OBJECT 0-9",0
GMSG_OBJECT:    DB "OBJECT ",0
GMSG_CALCULATING: DB "CALCULATING",0
; Exact 16-character PRINT/NOW prompts requested for the TRANZ display.
GMSG_PRINT_NO_HELP:  DB "PRNT? NO * = YES",0
GMSG_PRINT_YES_HELP: DB "PRNT? YES * = NO",0
GMSG_NOW_NO_HELP:    DB "NOW? NO  * = YES",0
GMSG_NOW_YES_HELP:   DB "NOW? YES * = NO",0
GMSG_PRINTING: DB "PRINTING",0
GMSG_PRINT_COMPLETE: DB "PRINT COMPLETE",0
GMSG_ENTER_2_PRINT: DB "ENTER 2 PRINT",0

; Printer report fragments.  Longest completed report line remains <=42 cols.
GPRN_VISIBLE_LOC:     DB " WILL BE VISIBLE FOR LOCATION",0
GPRN_NOT_VISIBLE_LOC: DB " WILL NOT BE VISIBLE FOR LOCATION",0
GPRN_LAT:             DB "LAT: ",0
GPRN_LON:             DB "   LON: ",0
GPRN_ON:              DB "ON ",0
GPRN_AT:              DB " AT ",0
GPRN_UTC:             DB " UTC",0
GPRN_AZ:              DB "ITS AZIMUTH WILL BE ",0
GPRN_EL:              DB "ITS ELEVATION WILL BE ",0
GPRN_DEGREES_OPEN:    DB " DEGREES (",0
GPRN_DEGREES:         DB " DEGREES",0
GPRN_PHASE_LEAD:      DB "IT WILL BE A ",0
GPRN_PHASE_TRAIL:     DB " MOON WITH",0
GPRN_ILLUMINATED:     DB "% ILLUMINATED",0

GPRN_PHASE_NEW:       DB "NEW",0
GPRN_PHASE_WAX_CRES:  DB "WAXING CRESCENT",0
GPRN_PHASE_FIRST:     DB "FIRST QUARTER",0
GPRN_PHASE_WAX_GIB:   DB "WAXING GIBBOUS",0
GPRN_PHASE_FULL:      DB "FULL",0
GPRN_PHASE_WAN_GIB:   DB "WANING GIBBOUS",0
GPRN_PHASE_LAST:      DB "LAST QUARTER",0
GPRN_PHASE_WAN_CRES:  DB "WANING CRESCENT",0
GMSG_CALC_DATE:   DB "CALC DATE",0
GMSG_CALC_ORBIT:  DB "CALC ORBIT",0
GMSG_CALC_PLANET: DB "CALC PLANET",0
GMSG_CALC_EVENTS: DB "CALC EVENTS",0
GMSG_CALC_AZEL:   DB "CALC AZEL",0
GMSG_CALC_PHASE:  DB "CALC PHASE",0
GMSG_VIS:       DB "VIS",0
GMSG_NOVIS:     DB "NOVIS",0
GMSG_UP:        DB "UP",0
GMSG_DN:        DB "DN",0
GMSG_PHASE:     DB " PHASE",0
GMSG_NEW:       DB "NEW",0
GMSG_FULL:      DB "FULL",0
GMSG_RISE:      DB "RISE ",0
GMSG_SET:       DB "SET ",0
GMSG_SUNRISE:   DB "SUNRISE ",0
GMSG_SUNSET:    DB "SUNSET ",0
GMSG_MOONRISE:  DB "MOONRISE ",0
GMSG_MOONSET:   DB "MOONSET ",0
GMSG_AZ:        DB "AZ ",0
GMSG_EL:        DB "EL ",0
GMSG_DEG:       DB " DEG",0
GMSG_NONE:      DB "NONE",0
GMSG_LOCAL:     DB " LOCAL",0

G_OBJECT_PTRS:
        DW GNAME_MERCURY,GNAME_VENUS,GNAME_SUN,GNAME_MARS,GNAME_JUPITER
        DW GNAME_SATURN,GNAME_URANUS,GNAME_NEPTUNE,GNAME_PLUTO,GNAME_MOON
GNAME_MERCURY:  DB "MERCURY",0
GNAME_VENUS:    DB "VENUS",0
GNAME_SUN:      DB "SUN",0
GNAME_MARS:     DB "MARS",0
GNAME_JUPITER:  DB "JUPITER",0
GNAME_SATURN:   DB "SATURN",0
GNAME_URANUS:   DB "URANUS",0
GNAME_NEPTUNE:  DB "NEPTUNE",0
GNAME_PLUTO:    DB "PLUTO",0
GNAME_MOON:     DB "MOON",0

G_MONTH_PTRS:
        DW GM_JAN,GM_FEB,GM_MAR,GM_APR,GM_MAY,GM_JUN
        DW GM_JUL,GM_AUG,GM_SEP,GM_OCT,GM_NOV,GM_DEC
GM_JAN: DB "JAN",0
GM_FEB: DB "FEB",0
GM_MAR: DB "MAR",0
GM_APR: DB "APR",0
GM_MAY: DB "MAY",0
GM_JUN: DB "JUN",0
GM_JUL: DB "JUL",0
GM_AUG: DB "AUG",0
GM_SEP: DB "SEP",0
GM_OCT: DB "OCT",0
GM_NOV: DB "NOV",0
GM_DEC: DB "DEC",0

G_COMPASS_PTRS:
        DW GD_N,GD_NNE,GD_NE,GD_ENE,GD_E,GD_ESE,GD_SE,GD_SSE
        DW GD_S,GD_SSW,GD_SW,GD_WSW,GD_W,GD_WNW,GD_NW,GD_NNW
GD_N:   DB "N",0
GD_NNE: DB "NNE",0
GD_NE:  DB "NE",0
GD_ENE: DB "ENE",0
GD_E:   DB "E",0
GD_ESE: DB "ESE",0
GD_SE:  DB "SE",0
GD_SSE: DB "SSE",0
GD_S:   DB "S",0
GD_SSW: DB "SSW",0
GD_SW:  DB "SW",0
GD_WSW: DB "WSW",0
GD_W:   DB "W",0
GD_WNW: DB "WNW",0
GD_NW:  DB "NW",0
GD_NNW: DB "NNW",0


; ---------------------------------------------------------------------------
; DEBUG TERMINAL STRINGS
; ---------------------------------------------------------------------------
DBG_MSG_HEADER: DB "=== TRANZ330 ASTRO DEBUG ===",0
DBG_FIXED_INPUTS: DB "INPUT UTC-5 30.3642N 88.7548W",0
DBG_MSG_DATE:   DB "DATE MM/DD/YY ",0
DBG_MSG_TIME:   DB "TIME HH:MM:SS ",0
DBG_MSG_ELEMS:  DB "-- PLANET ELEMENTS angle10 --",0
DBG_MSG_EVENTS: DB "-- EVENTS local minutes --",0
DBG_MSG_VECTOR: DB "-- CURRENT VECTOR --",0
DBG_MSG_DONE:   DB "=== END DEBUG ===",0
DBG_L_DAYS:     DB "DAYS=",0
DBG_L_SM:       DB "SUN_M10=",0
DBG_L_SW:       DB "SUN_W10=",0
DBG_L_N:        DB "N10=",0
DBG_L_I:        DB "I10=",0
DBG_L_W:        DB "W10=",0
DBG_L_M:        DB "M10=",0
DBG_L_RISE:     DB "RISE_MIN=",0
DBG_L_TRANS:    DB "TRANS_MIN=",0
DBG_L_SET:      DB "SET_MIN=",0
DBG_L_SX:       DB "SUN_X=",0
DBG_L_SY:       DB "SUN_Y=",0
DBG_L_XH:       DB "HELIO_X=",0
DBG_L_YH:       DB "HELIO_Y=",0
DBG_L_ZH:       DB "HELIO_Z=",0
DBG_L_X:        DB "EQ_X=",0
DBG_L_Y:        DB "EQ_Y=",0
DBG_L_Z:        DB "EQ_Z=",0
DBG_L_SMCUR:    DB "SUN_M_CUR10=",0
DBG_L_SE:       DB "SUN_E10=",0
DBG_L_SLON:     DB "SUN_LON10=",0
DBG_L_PMCUR:    DB "PLAN_M_CUR10=",0
DBG_L_PE:       DB "PLAN_E10=",0
DBG_L_PAQ:      DB "PLAN_AQ=",0
DBG_L_PAEQ:     DB "PLAN_AEQ=",0
DBG_L_HOX:      DB "HELIO_ONLY_X=",0
DBG_L_HOY:      DB "HELIO_ONLY_Y=",0
DBG_L_HOZ:      DB "HELIO_ONLY_Z=",0
DBG_L_GEX:      DB "GEO_ECL_X=",0
DBG_L_GEY:      DB "GEO_ECL_Y=",0
DBG_L_GEZ:      DB "GEO_ECL_Z=",0
DBG_L_RA10:     DB "RA10=",0
DBG_L_DEC10:    DB "DEC10=",0
DBG_L_OBL10:    DB "OBL10=",0
DBG_L_UTC_MIN:  DB "UTC_MIN=",0
DBG_L_SM_NOW:   DB "SUN_M_BASE10=",0
DBG_L_SW_NOW:   DB "SUN_W_BASE10=",0
DBG_L_LON10:    DB "LONGITUDE10=",0
DBG_L_LST0:     DB "LST0_10=",0
DBG_L_LST:      DB "LST_10=",0
DBG_L_EAST:     DB "EAST=",0
DBG_L_NORTH:    DB "NORTH=",0
DBG_L_UP:       DB "UP=",0
DBG_L_AZ:       DB "AZ10=",0
DBG_L_EL:       DB "EL10=",0

    DEFS $8000-$,$FF

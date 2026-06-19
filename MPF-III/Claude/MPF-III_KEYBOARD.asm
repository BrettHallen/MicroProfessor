; ============================================================================
;  Multitech Micro-Professor MPF-III  --  Keyboard Controller Firmware
;  CPU: Intel INS8035N-6 (MCS-48, ROM-less, 64 bytes RAM, 8-bit)
;  EPROM: 2732 (4 KB), label U5, CRC32 = 46D4227A
;
;  Reassemblable source -- reconstructs the 1 KB program image.
;  EPROM mapping: only the upper 2 KB of the 2732 is decoded (A11 strapped
;  high). CPU address 0x000 therefore reads EPROM file offset 0x800. This
;  source uses RUNTIME addresses (ORG 0). The active program lives at runtime
;  0x000-0x3FF (= file 0x800-0xBFF); the rest of the EPROM is erased (0xFF).
;
;  Independently re-disassembled and verified, 19/Jun/2026.
;  Original WIP annotation: Brett Hallen, 25/Jan/2026.
; ============================================================================

; ---- Internal RAM map (bank 0 unless noted) --------------------------------
DEBOUNCE  EQU 020H   ; 020H-02AH  per-row debounced key state (11 rows)
PENDCODE  EQU 02EH   ; last code latched for main-loop special check
BLINKCNT  EQU 02FH   ; LED blink phase counter
REPLO     EQU 030H   ; auto-repeat delay counter (low)
REPHI     EQU 031H   ; auto-repeat delay counter (high)
STRB0     EQU 032H   ; strobe timing counter
STRB1     EQU 033H   ; strobe timing counter
NIBCNT    EQU 034H   ; nibble index (repeat bit scan)
CNT36     EQU 036H   ; general 5-tick counter
PREVCODE  EQU 037H   ; previous key code (repeat compare)
CURCODE   EQU 038H   ; current key code  (038H-03EH = key queue)

          ORG 0

        NOP                     ; NOP (likely padding or unused)
        NOP
        NOP
        DIS I                   ; Disable external interrupt
        JMP INIT                ; Jump to main init
        NOP
        JMP TIMER_ISR           ; Jump to timer/interrupt handler or secondary routine
INIT:
        MOV A,#$FF              ; A = 0xFF (all bits set)
        OUTL BUS,A              ; Output 0xFF to BUS (initialise/clear bus lines for keyboard columns)
        OUTL P2,A               ; Output 0xFF to Port 2 (configure as input/high for row deselect)
        MOV A,#$C7              ; A = 0xC7 (11000111b - set P1.7,6,3-0 high, clear 5,4,2? For control/LEDs)
        OUTL P1,A               ; Output to Port 1 (keyboard matrix control lines/LEDs)
        MOV R0,#$3F             ; R0 = 0x3F (top of internal RAM - 64 bytes)
L012:
        MOV @R0,#$00            ; Clear [R0] = 0
        DJNZ R0,L012            ; Loop to clear RAM 0x00-0x3F (debounce states, buffers, flags)
        MOV A,#$FB              ; A = 0xFB (timer preload for ~10ms interval? For debounce/repeat)
        CALL TIMER_START        ; Call timer enable subroutine
        SEL RB1                 ; Select register bank 1 (for state flags)
        MOV R7,#$01             ; RB1.R7 = 1 (initial state flag)
L01D:
        CALL CLR_FLAGS          ; Clear flags in RB0/RB1 (reset counters/timers)
L01F:
        SEL RB1                 ; RB1
        CALL SCAN_MATRIX        ; Scan keyboard matrix
        CALL CHK_PENDING        ; Check if any keys pending (OR RAM 0x20-0x2A, clear P1.4 if none)
        JMP MAIN_LOOP           ; Main loop: check for repeat/special codes
SCAN_MATRIX:
        MOV R6,#$57             ; R6 = 87 (max key index for 11*8-1)
        MOV R2,#$7F             ; R2 = 01111111b (initial row mask, low bit for select)
        MOV R4,#$0B             ; R4 = 11 (row loop)
SCAN_ROW:
        MOV A,R2                ; A = R2
        RL A                    ; Shift left (next row select)
        MOV R2,A                ; Update R2
        OUTL P2,A               ; Output to P2 (one bit low to select row)
READ_COLS:
        INS A,BUS               ; Read columns (active low)
        CPL A                   ; Invert to active high
        MOV R1,A                ; R1 = current column bits
        MOV A,R4                ; A = R4
        ADD A,#$1F              ; A = R4 + 0x1F = debounce RAM addr (0x2A for R4=11, down to 0x20 for R4=1)
        MOV R0,A                ; R0 = addr
        MOV A,R1                ; A = current
        XRL A,@R0               ; XOR with previous (detect changes)
        JZ ROW_NOCHG            ; No change  next row
        CALL DEBOUNCE_RD        ; Debounce: 5x read + AND
        CALL DEBOUNCE_RD
        CALL DEBOUNCE_RD
        CALL DEBOUNCE_RD
        CALL DEBOUNCE_RD
        MOV R5,A                ; R5 = stable debounced bits
        XRL A,@R0               ; Changes after debounce
        JZ ROW_NOCHG            ; No
        ANL A,R5                ; A = pressed changes (new presses)
        XCH A,R5                ; Swap
        MOV @R0,A               ; Update previous = old current
        MOV A,R5                ; A = new presses
        JZ ROW_NOCHG            ; None  next
        CALL PROC_PRESS         ; Process presses (shift buffer, lookup code)
NEXT_ROW:
        DEC R4                  ; Next row
        MOV A,R4
        JZ SCAN_DONE            ; Done all rows
        ADD A,#$FC              ; R4 -4 (check for extra rows using P1)
        JC SCAN_ROW             ; If R4 >=4, normal P2 loop
        ORL P2,#$FF             ; Deselect P2 rows
        MOV A,R2                ; A = R2
        RL A                    ; Shift for next
        MOV R2,A
        CPL A                   ; Invert for P1 check
        ORL P1,#$07             ; Set P1.0-2 high (default)
        JB0 L06D                ; If bit0 set in inverted A  clear P1.0
        JB1 L069                ; Bit1  clear P1.1
        ANL P1,#$FB             ; Clear P1.2
        JMP READ_COLS           ; Read BUS
L069:
        ANL P1,#$FD             ; Clear P1.1
        JMP READ_COLS
L06D:
        ANL P1,#$FE             ; Clear P1.0
        JMP READ_COLS
ROW_NOCHG:
        MOV A,R6                ; R6 -=8 for next row group
        ADD A,#$F8
        MOV R6,A
        JMP NEXT_ROW            ; Continue
SCAN_DONE:
        ORL P1,#$07             ; Restore P1.0-2 high
        RETR
DEBOUNCE_RD:
        CALL WAIT_TICK          ; Delay (timer flag wait)
        INS A,BUS               ; Read
        CPL A                   ; Invert
        ANL A,R1                ; AND with prior reads (stable bits only)
        MOV R1,A
        RETR
PROC_PRESS:
        ORL P2,#$FF             ; Deselect rows
        ORL P1,#$07             ; Restore P1
        MOV R3,#$08             ; 8 bits (columns)
        MOV A,R5                ; A = presses
L088:
        RLC A                   ; Test MSB (leftmost column?)
        JNC L093                ; No press  next bit
        MOV R5,A                ; Update shifted
        CALL QUEUE_UP           ; Shift key queue up (RAM 0x38-0x3E)
        CALL KEY_HANDLER        ; Lookup/adjust code for R6, store in [0x38]
        CALL CLR_FLAGS          ; Clear flags/counters
        MOV A,R5
L093:
        DEC R6                  ; R6-- (next key index in row)
        DJNZ R3,L088            ; Loop 8 bits
        RETR
CLR_FLAGS:
        SEL RB0                 ; RB0
        MOV A,R6                ; Clear bits 1-2 in RB0.R6
        ANL A,#$F9
        MOV R6,A
        SEL RB1                 ; RB1
        MOV A,R7                ; Clear bit 2 in RB1.R7
        ANL A,#$FB
        MOV R7,A
        MOV R0,#$30             ; Clear repeat counter [0x30]=0
        MOV @R0,#$00
        MOV R0,#$31             ; Clear another counter [0x31]=0
        MOV @R0,#$00
        RETR
REPEAT_CHK:
        MOV A,R7                ; A = RB1.R7
        MOV R0,#$38             ; Current key [0x38]
        JB2 L0B9                ; If bit2 set (repeat active?), compare with previous
        MOV A,@R0               ; A = current
        MOV R0,#$37             ; Copy to previous [0x37]
        MOV @R0,A
        MOV A,R7                ; Set bit2 (enable repeat?)
        ORL A,#$04
        MOV R7,A
        JMP L01F                ; Back
L0B9:
        MOV A,@R0               ; Current
        MOV R0,#$37
        XRL A,@R0               ; XOR previous
        JZ L0C1                 ; Same  check for repeat
        JMP L01D                ; Different  reset
L0C1:
        SEL RB0                 ; RB0
        MOV A,R6                ; RB0.R6
        JB1 L0C7                ; Bit1 set (repeat timer active?)
        JMP L01F                ; No  back
L0C7:
        ANL A,#$FD              ; Clear bit1
        MOV R6,A
        SEL RB1                 ; RB1
        CALL LOAD_KEYCODE       ; Load R6 with [0x38] (key code)
        MOV R0,#$34             ; [0x34]=0 (nibble counter?)
        MOV @R0,#$00
        MOV A,R6                ; A = key code
        SWAP A                  ; Swap nibbles
        CLR C
        RLC A                   ; Shift to check if high nibble odd
        JC L0EF                 ; Yes  inc nibble counter
        XCHD A,@R0              ; Exchange low nibble with [0x34]
L0D8:
        CLR C
        RRC A                   ; Shift right
        SWAP A
        ANL A,#$0F              ; Low nibble value
        MOV R3,A                ; R3 = bit count
        MOV A,@R0               ; A = [0x34]
        ADD A,#$20              ; Offset to RAM buffer 0x20+
        MOV R0,A                ; R0 = addr
        MOV A,@R0               ; A = buffer byte
        INC R3                  ; R3++
L0E4:
        RR A                    ; Rotate right R3 times
        DJNZ R3,L0E4
        JB7 L0EB                ; If MSB set  process repeat
        JMP QUEUE_DOWN          ; Else shift queue down
L0EB:
        CALL KEY_HANDLER        ; Handle repeat (lookup/output)
        JMP L01F
L0EF:
        XCHD A,@R0              ; Inc nibble
        INC @R0
        JMP L0D8
WAIT_TICK:
        SEL RB0
        MOV A,R6                ; Set bit6 in RB0.R6 (timer flag?)
        ORL A,#$40
        MOV R6,A
L0F8:
        JMP L0FA
L0FA:
        MOV A,R6
        JB6 L0F8                ; Loop until bit6 cleared (by interrupt)
        SEL RB1
        RETR
TIMER_START:
        MOV T,A                 ; Load timer
        EN TCNTI                ; Enable timer interrupt
        STRT T                  ; Start timer
        RET                     ; Non-reentrant
TIMER_ISR:
        SEL RB0
        MOV R2,A                ; Save A
        MOV A,#$06              ; Short delay (~6 cycles)
L107:
        DEC A
        JNZ L107
        MOV A,#$FB              ; Reload timer
        CALL TIMER_START        ; Restart timer
        MOV A,R6                ; RB0.R6 flags
        JB5 LED_BLINK           ; Bit5 set  LED blink handler
        JB6 CNT_RESET           ; Bit6  counter reset
        SEL RB0
        MOV A,R6
        JB2 REP_DELAY_LONG      ; Bit2  long repeat delay
        SEL RB1
        MOV A,R7                ; RB1.R7
        SEL RB0
        JB2 REP_CNT_SHORT       ; Bit2 in RB0.R7  short repeat counter
ISR_DISPATCH:
        SEL RB0
        MOV A,R7                ; RB0.R7
        JB0 STROBE_TOG          ; Bit0  strobe toggle
L120:
        MOV A,R2                ; Restore A
        RETR                    ; Return from interrupt
STROBE_TOG:
        MOV R0,#$32             ; [0x32]++ (strobe counter?)
        INC @R0
        MOV A,@R0
        XRL A,#$01              ; ==1?
        JNZ L141                ; No
        MOV @R0,A               ; Clear to 0
        IN A,P1                 ; Read P1
        JB3 L147                ; Bit3 set?  clear
        ORL P1,#$08             ; Set P1.3 (strobe/LED?)
L130:
        INC R0                  ; R0=0x33
        INC @R0                 ; [0x33]++
        MOV A,@R0
        ADD A,#$F0              ; >=16?
        JNC L141                ; No
        MOV A,R7                ; Clear bit0 RB0.R7
        ANL A,#$FE
        MOV R7,A
        SEL RB1
        MOV A,R7                ; RB1.R7
        JB5 L143                ; Bit5 set  set P1.3
        ANL P1,#$F7             ; Clear P1.3
L141:
        JMP L120                ; Back
L143:
        ORL P1,#$08             ; Set P1.3
        JMP L120
L147:
        ANL P1,#$F7             ; Clear P1.3
        JMP L130                ; Inc [0x33]
        NOP                     ; Padding
        NOP
        NOP
        NOP
REP_CNT_SHORT:
        MOV R0,#$30             ; [0x30]++ (repeat delay counter)
        INC @R0
        MOV A,@R0
        JZ L157                 ; Overflow  next counter
        JMP ISR_DISPATCH        ; Back
L157:
        MOV R0,#$31             ; [0x31]++
        INC @R0
        MOV A,@R0
        XRL A,#$04              ; ==4? (short delay ~40ms?)
        JNZ ISR_DISPATCH        ; No
L15F:
        MOV R0,#$30             ; Clear [0x30]
        MOV @R0,#$00
        MOV A,R6                ; Set bits1-2 in RB0.R6 (trigger repeat?)
        ORL A,#$06
        MOV R6,A
        JMP ISR_DISPATCH
REP_DELAY_LONG:
        MOV R0,#$30             ; [0x30]++
        INC @R0
        MOV A,@R0
        XRL A,#$35              ; ==0x35 (~350ms initial delay for auto-repeat)
        JZ L15F                 ; Yes  set flags
        JMP ISR_DISPATCH
CNT_RESET:
        MOV R0,#$36             ; [0x36]++
        MOV A,@R0
        XRL A,#$05              ; ==5?
        JZ L17D                 ; Yes  clear
        INC @R0
        JMP ISR_DISPATCH
L17D:
        MOV @R0,#$00            ; Clear
        MOV A,R6                ; Clear bit6 RB0.R6
        ANL A,#$BF
        MOV R6,A
        JMP ISR_DISPATCH
LED_BLINK:
        MOV R0,#$2F             ; [0x2F] = blink counter
        MOV A,@R0
        JZ L1E5                 ; ==0  pulse low
        XRL A,#$09              ; ==9  set high
        JZ L1B8
        MOV A,@R0
        ADD A,#$F0              ; >=16?  reset
        JC L1BC
        MOV A,@R0
        XRL A,#$0A              ; ==10  toggle P1.6
        JZ L1C4
        MOV A,@R0
        ADD A,#$F6              ; >=10?  pulse high/low
        JC L1B3
        MOV A,R5                ; R5 = saved A from interrupt?
        JB0 L1E1                ; Bit0 set  set P1.7
        ANL P1,#$7F             ; Clear P1.7 (LED?)
L1A2:
        MOV A,R5                ; Rotate R5 right (blink pattern?)
        RR A
        MOV R5,A
        MOV A,#$05              ; Delay 5
L1A7:
        DEC A
        JNZ L1A7
        ORL P1,#$20             ; Set P1.5
        MOV A,#$02              ; Delay 2
L1AE:
        DEC A
        JNZ L1AE
        ANL P1,#$DF             ; Clear P1.5
L1B3:
        MOV R0,#$2F             ; Inc counter
        INC @R0
        JMP ISR_DISPATCH        ; Back
L1B8:
        ORL P1,#$80             ; Set P1.7
        JMP L1B3
L1BC:
        MOV @R0,#$00            ; Reset counter
        MOV A,R6                ; Clear bit5 RB0.R6
        ANL A,#$9F
        MOV R6,A
        JMP ISR_DISPATCH
L1C4:
        SEL RB1
        MOV A,R7                ; RB1.R7
        JB4 L1DA                ; Bit4 set  set P1.6
L1C8:
        SEL RB0
        IN A,P1
        JB6 L1D3                ; P1.6 set  clear then set
        ORL P1,#$40             ; Set P1.6
        NOP                     ; Delay
        ANL P1,#$BF             ; Clear
        JMP L1B3                ; Inc
L1D3:
        ANL P1,#$BF             ; Clear
        NOP
        ORL P1,#$40             ; Set
        JMP L1B3
L1DA:
        ORL P1,#$40             ; Set P1.6
        ANL A,#$EF              ; Clear bit4 R7
        MOV R7,A
        JMP L1B3
L1E1:
        ORL P1,#$80             ; Set P1.7
        JMP L1A2                ; Rotate/delay
L1E5:
        ANL P1,#$7F             ; Clear P1.7
        NOP
        ORL P1,#$10             ; Set P1.4
        MOV A,R7                ; RB0.R7?
        JB1 L1EF                ; Bit1 set?
        JMP L1C8                ; Toggle P1.6
L1EF:
        ORL A,#$01              ; Set bit0
        MOV R7,A
        MOV R0,#$32             ; Clear [0x32-0x33]=0
        MOV @R0,#$00
        INC R0
        MOV @R0,#$00
        JMP L1C8
LOAD_KEYCODE:
        MOV R0,#$38
        MOV A,@R0
        MOV R6,A
        RETR
LOOKUP:
        MOV A,R6                ; A = R6
LOOKUP_A:
        MOVP3 A,@A              ; Base lookup: R0 = [0x0300 + R6]
        MOV R0,A
        JNT0 REMAP_T0           ; T0 low?  special remap
        MOV A,R7                ; R7 flags
        JB0 CTRL_ADJ            ; Bit0 (CTRL) set  CTRL adjust
STORE_CODE:
        MOV A,R0                ; No CTRL
        SEL RB0
        MOV R5,A                ; Temp store in RB0.R5
        SEL RB1
        MOV R0,#$2E             ; Store in [0x2E] (pending code?)
        MOV @R0,A
        SEL RB0
        XRL A,#$10              ; ==0x10? (special?)
        JZ L224
        MOV A,#$7F              ; A = 01111111b
        SEL RB1
        ORL A,R7                ; OR flags
        SEL RB0
        ANL A,R5                ; AND with code (mask bits?)
        MOV R5,A
L21B:
        SEL RB0
        MOV R5,A
        MOV A,R6
        ORL A,#$20              ; Set bit5 RB0.R6
        MOV R6,A
L221:
        MOV A,R6
        JB5 L221                ; Wait for bit5 clear (timer?)
L224:
        RETR
LOOKUP_SHIFT:
        MOV A,R6
        ADD A,#$48
        JMP LOOKUP_A            ; Lookup shifted
CTRL_ADJ:
        MOV A,R0                ; Base code
        ADD A,#$1F              ; +0x1F
        JNC STORE_CODE          ; No carry (<0xE1)  no adjust
        MOV A,R0
        ADD A,#$05              ; +0x5
        JC STORE_CODE           ; Carry  no adjust
        MOV A,R0
        ANL A,#$DF              ; A = code AND 0xDF -> clear bit5 (CTRL maps letters to $81-$9A)
        MOV R0,A
        JMP STORE_CODE
REMAP_T0:
        MOV A,R6
        XRL A,#$28              ; ==0x28?  special handler
        JZ L259
        MOV A,R6
        ADD A,#$C8              ; -0x38 (carry if >=0x38)
        JC STORE_CODE           ; No  normal
        MOV A,R0
        ADD A,#$40              ; +0x40
        JNC L25B                ; No carry
        MOV A,R0
        XRL A,#$E0              ; ==0xE0  normal
        JZ STORE_CODE
        MOV A,R0
        ADD A,#$02              ; +0x2
        JC STORE_CODE           ; Carry  normal
        MOV A,R0
        ANL A,#$9F              ; Clear bits5-6
        MOV R0,A
        JMP STORE_CODE
L259:
        JMP SET_REP_FLAGS       ; Special (set bits0-1 RB0.R7?)
L25B:
        MOV A,R0
        XRL A,#$B6              ; ==0xB6  0x9E
        JZ L267
        MOV A,R0
        XRL A,#$B2              ; ==0xB2  0x80
        JZ L26B
        JMP STORE_CODE
L267:
        MOV R0,#$9E
        JMP STORE_CODE
L26B:
        MOV R0,#$80
        JMP STORE_CODE
KEY_HANDLER:
        SEL RB1
        CALL SET_READY          ; Set R7 bit7 (key ready/strobe)
        MOV A,R6                ; Store raw R6 in [0x38]
        MOV R0,#$38
        MOV @R0,A
        MOV A,R6
        ADD A,#$B8              ; -0x48 (carry if >=0x48  special)
        JC L2B0
        JNI L284                ; INT1 low? (ALT pressed  clear ready)
L27D:
        JNT1 LOOKUP_SHIFT       ; T1 high? (shift not pressed  shifted)
        MOV A,R7
        JB5 L2A9                ; Bit5 (caps) set  shift if applicable
        JMP LOOKUP              ; Normal lookup
L284:
        MOV A,R6
        ADD A,#$D8              ; -0x28 (carry if >=0x28  back)
        JC L27D
        CALL CLR_READY          ; Clear R7 bit7 (no ready?)
        MOV A,R6
        ADD A,#$F6              ; -0x0A (carry if >=0x0A)
        JC L29D
        MOV A,R6                ; Small R6: base +0x4B
        MOVP3 A,@A
        ADD A,#$4B
        JC L2A2                 ; Carry  +0xC6 alt
        MOV A,R6
        MOVP3 A,@A
        ADD A,#$AC              ; +0xAC
        MOV R0,A
        JMP STORE_CODE
L29D:
        MOV A,R6                ; Direct
        MOVP3 A,@A
        MOV R0,A
        JMP STORE_CODE
L2A2:
        MOV A,R6                ; +0xC6
        MOVP3 A,@A
        ADD A,#$C6
        MOV R0,A
        JMP STORE_CODE
L2A9:
        MOV A,R6
        ADD A,#$C5              ; -0x3B (no carry if >=0x3B  shifted)
        JNC LOOKUP
        JMP LOOKUP_SHIFT
L2B0:
        MOV A,R6
        XRL A,#$57              ; ==0x57  CTRL toggle
        JZ L2DE
        MOV A,R6
        XRL A,#$55              ; ==0x55  Caps toggle
        JZ L2EE
        MOV A,R6
        XRL A,#$56              ; ==0x56  no-op
        JZ L2ED
        MOV A,R6
        XRL A,#$54              ; ==0x54  no-op
        JZ L2ED
        MOV A,R6
        ADD A,#$D8              ; -0x28
        JNI L2DA                ; ALT? +0x30
        JNT1 L2D0               ; Shift? +0x18 if T0 high
        JNT0 L2D6               ; T0 high? direct
L2CD:
        MOV R0,A
        JMP STORE_CODE
L2D0:
        ADD A,#$18
        JNT0 L2D6
        JMP L2CD
L2D6:
        ADD A,#$0C
        JMP L2CD
L2DA:
        ADD A,#$30
        JMP L2CD
L2DE:
        MOV A,R7
        JB0 L2E8                ; On  off, clear P1.6
        ORL A,#$11              ; Off  on, set bits0/4
        MOV R7,A
        MOV A,#$10              ; A=0x10 (mask?)
        JMP L21B
L2E8:
        ANL A,#$FE              ; Clear bit0
        ANL P1,#$BF             ; Clear P1.6 (CTRL LED?)
        MOV R7,A
L2ED:
        RETR
L2EE:
        MOV A,R7
        JB5 L2F7                ; On  off
        ORL A,#$20              ; Off  on
        MOV R7,A
        ORL P1,#$08             ; Set P1.3 LED
        RETR
L2F7:
        ANL A,#$DF              ; Clear bit5
        MOV R7,A
        ANL P1,#$F7             ; Clear P1.3
        RETR

; ---- filler (erased EPROM) 2FDH-2FFH ----
        DB  0FFH,0FFH,0FFH

; ============================================================================
; Page-3 key-code lookup table (read by MOVP3 A,@A).  Pure data 300H-38FH.
; Indexed by raw key index R6; modifier routines add offsets before lookup.
; ============================================================================
KEYMAP:
        DB  0B1H,0B2H,0B3H,0B4H,0B5H,0B6H,0B7H,0B8H,0B9H,0B0H,0F0H,0ECH,0EFH,0EBH,0E9H,010H   ; 300
        DB  0EDH,0EAH,0F5H,0EEH,0E8H,0F9H,0E2H,010H,0E7H,0F4H,0F6H,0E6H,0F2H,0E3H,0E4H,010H   ; 310
        DB  0E5H,0F8H,0F3H,0F7H,0FAH,0E1H,0F1H,010H,09BH,089H,0DCH,0A0H,0ACH,0AEH,0BBH,0AFH   ; 320
        DB  0A7H,0DBH,0ADH,0E0H,0DDH,0BDH,0FFH,088H,08DH,093H,083H,08AH,095H,0B5H,088H,08BH   ; 330
        DB  005H,000H,002H,001H,006H,01FH,004H,003H,0A1H,0C0H,0A3H,0A4H,0A5H,0DEH,0A6H,0AAH   ; 340
        DB  0A8H,0A9H,0D0H,0CCH,0CFH,0CBH,0C9H,010H,0CDH,0CAH,0D5H,0CEH,0C8H,0D9H,0C2H,010H   ; 350
        DB  0C7H,0D4H,0D6H,0C6H,0D2H,0C3H,0C4H,010H,0C5H,0D8H,0D3H,0D7H,0DAH,0C1H,0D1H,010H   ; 360
        DB  09BH,089H,0FCH,0A0H,0BCH,0BEH,0BAH,0BFH,0A2H,0FBH,0DFH,0FEH,0FDH,0ABH,0FFH,088H   ; 370
        DB  08DH,093H,083H,0B2H,0B6H,0B5H,0B4H,0B8H,0AEH,0B0H,0B3H,0B1H,0ABH,0ADH,0B9H,0B7H   ; 380

; ============================================================================
; Code continues at 390H (also doubles as MOVP3 lookup data for some ALT keys)
; ============================================================================
CHK_PENDING:
        SEL RB0
        MOV R1,#$20
        MOV R3,#$0B             ; 11 bytes (one per row)
        MOV A,#$00
L397:
        ORL A,@R1               ; OR all
        INC R1
        DJNZ R3,L397
        JNZ L39F                ; Any pending? Skip clear
        ANL P1,#$EF             ; Clear P1.4 (no keys LED?)
L39F:
        RETR
MAIN_LOOP:
        MOV R0,#$2E             ; Pending code [0x2E]
        MOV A,@R0
        ADD A,#$F9              ; -7 (carry if <7)
        JNC L3C9                ; No special
        MOV A,@R0
        XRL A,#$1F              ; ==1F (- LIST no shift)?
        JZ L3C9                 ; Skip repeat
        MOV A,@R0
        XRL A,#$93              ; ==93 (HALT, no repeat)
        JZ L3C9
        MOV A,@R0
        XRL A,#$83              ; ==83 (BREAK, no repeat)
        JZ L3C9
        MOV R0,#$38             ; Current code
        MOV A,@R0
        ADD A,#$AC              ; -0x54 (carry if <54)
        JC L3C9                 ; Low codes no repeat
        JMP REPEAT_CHK          ; To repeat check/handler
SET_READY:
        MOV A,R7
        ORL A,#$80              ; Bit7 set
        MOV R7,A
        RETR
CLR_READY:
        MOV A,R7
        ANL A,#$7F              ; Bit7 clear
        MOV R7,A
        RETR
L3C9:
        JMP L01D                ; Reset to scan
QUEUE_DOWN:
        MOV A,R7
        ANL A,#$FB              ; Clear bit2 R7
        MOV R7,A
        SEL RB0
        MOV R3,#$07             ; 7 bytes
        MOV R1,#$39             ; Shift 0x39-0x33 down (key queue?)
L3D4:
        MOV A,@R1
        DEC R1
        MOV @R1,A
        INC R1
        INC R1
        DJNZ R3,L3D4
        JMP L01F
QUEUE_UP:
        SEL RB0
        MOV R3,#$07
        MOV R1,#$3E             ; Shift 0x3E-0x38 up
L3E2:
        MOV A,@R1
        INC R1
        MOV @R1,A
        DEC R1
        DEC R1
        DJNZ R3,L3E2
        RETR
SET_REP_FLAGS:
        SEL RB0
        MOV A,R7
        JB1 L3F2                ; Bit1 set?
        ORL A,#$03              ; Set bits0-1 (repeat enable)
L3F0:
        MOV R7,A
        RETR
L3F2:
        ANL A,#$FC              ; Clear bits0-1
        JMP L3F0

; ---- filler (erased EPROM) 3F6H-3FFH ----
        DB  0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH

        END

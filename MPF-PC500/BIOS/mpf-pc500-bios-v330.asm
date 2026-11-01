; Multitech MPF-PC/500 BIOS V3.30 (U36, 8 KB, mapped F000:E000-FFFF)
; Disassembly generated from MultiTech_MPF_PC-500_U36_62370F21.ROM
; Re-assembles byte-for-byte with:  nasm -O0 -f bin -o bios.bin mpf-pc500-bios-v330.asm
;   (-O0 matters: it stops NASM shrinking immediates and changes the output)
; Instructions shown as "db ... ; (insn)" are ones NASM would encode differently
; (e.g. 33 C0 vs 31 C0 for xor ax,ax), so the original bytes are kept.
; Labels L_xxxx / sub_xxxx are unnamed jump / call targets; xxxx = offset in F000.
; Names, headers and comments are interpretation - see BIOS-NOTES.md.

        cpu 8086
        bits 16
        org 0xE000


; =====================================================================
;  Return addresses for the two "stackless calls" made before RAM is
;  known to work.  SS=F000 and SP points here, so a RET pops one of these.
; =====================================================================
stackless_ret_table:
        dw 0x9090                               ; E000
        dw 0xE046                               ; E002
        dw 0xE103                               ; E004

; =====================================================================
;  COLD START (reached from the reset vector via POST_start)
;  First thing: look for an 8 KB extension ROM at F4000-F5FFF.  If its last
;  word (F5FFE) holds the 55 AA signature, jump straight into it at F4104
;  before ANY hardware is initialised.  Probably intended for the empty
;  28-pin socket on the CPU card (U43?) - not confirmed.
; =====================================================================
cold_start:
        mov si,0x5ffe                           ; E006
        mov ax,[cs:si]                          ; E009
        cmp ax,0xaa55                           ; E00C
        jnz init_chipset                        ; E00F
        jmp 0xf000:0x4104                       ; E011  extension ROM present: hand over to F000:4104

; ---------------------------------------------------------------------
;  Basic chipset initialisation: PPI, NMI off, video off, DMA off
; ---------------------------------------------------------------------
init_chipset:
        cli                                     ; E016
        mov al,0x99                             ; E017
        out 0x63,al                             ; E019  PPI: A=in, B=out, C=in (IBM PC mode)
        db 0x33, 0xC0                           ; E01B  (xor ax,ax)
        out 0xa0,al                             ; E01D  NMI disabled
        out 0x83,al                             ; E01F  DMA page register = 0
        mov al,0xfd                             ; E021
        out 0x61,al                             ; E023  8255 PPI port B (control)
        mov al,0x1                              ; E025
        mov dx,0x3b8                            ; E027  MDA: video off
        out dx,al                               ; E02A
        dec al                                  ; E02B
        mov dx,0x3d8                            ; E02D  CGA: video off
        out dx,al                               ; E030
        mov ax,0xf000                           ; E031
        mov ss,ax                               ; E034
        mov al,0x4                              ; E036
        out 0x8,al                              ; E038  disable DMA controller
        mov ax,0x8094                           ; E03A  AL=94h ch2 LSB mode 2, AH=80h latch ch2
        mov dx,0x42                             ; E03D
        mov sp,0xe002                           ; E040  SP -> E002: return to E046
        jmp near test_pit_ch2                   ; E043

; ---------------------------------------------------------------------
;  PIT channel 2 passed - start a tone (power-on "chirp"); it is switched
;  off again after the first 64 KB of RAM has been cleared.
; ---------------------------------------------------------------------
after_pit_test:
        jnz L_E07A                              ; E046  PIT ch2 failed -> HLT
        mov al,0xb6                             ; E048
        out 0x43,al                             ; E04A  8253 PIT mode control
        mov al,0x7                              ; E04C
        out 0x42,al                             ; E04E  8253 PIT counter 2 (speaker)
        out 0x42,al                             ; E050  8253 PIT counter 2 (speaker)
        in al,0x61                              ; E052  8255 PPI port B (control)
        or al,0x3                               ; E054
        out 0x61,al                             ; E056  8255 PPI port B (control)
        nop                                     ; E058
        jmp short dma_reg_test                  ; E059
POST_start:
        jmp short cold_start                    ; E05B

; ---------------------------------------------------------------------
;  8237 DMA register test.  QUIRK: the pattern table at E813 starts with
;  0x00, and the loop stops when the pattern is zero, so only 0x00 is
;  ever written/read back - a very weak test.
; ---------------------------------------------------------------------
dma_reg_test:
        mov bx,0xe812                           ; E05D
L_E060:
        inc bx                                  ; E060
        mov al,[cs:bx]                          ; E061
        db 0x8A, 0xE0                           ; E064  (mov ah,al)
        db 0x8B, 0xF0                           ; E066  (mov si,ax)
        mov cx,0x8                              ; E068
L_E06B:
        db 0x8B, 0xD1                           ; E06B  (mov dx,cx)
        dec dx                                  ; E06D
        out dx,al                               ; E06E
        out dx,al                               ; E06F
        db 0x33, 0xC0                           ; E070  (xor ax,ax)
        in al,dx                                ; E072
        xchg ah,al                              ; E073
        in al,dx                                ; E075
        db 0x3B, 0xF0                           ; E076  (cmp si,ax)
        jz L_E07B                               ; E078
L_E07A:
        hlt                                     ; E07A  halt on any POST failure here
L_E07B:
        loop L_E06B                             ; E07B
        db 0x0B, 0xF6                           ; E07D  (or si,si)
        jnz L_E060                              ; E07F

; ---------------------------------------------------------------------
;  DRAM refresh: PIT ch1 mode 2, count 18 (~15 us) driving DMA ch0.
;  Then DMA ch1-3 modes and the 8259 (edge, single, ICW4=buffered, IRQ->INT 8)
; ---------------------------------------------------------------------
init_refresh_dma_pic:
        mov al,0x54                             ; E081
        out 0x43,al                             ; E083  8253 PIT mode control
        mov al,0x12                             ; E085
        out 0x41,al                             ; E087  8253 PIT counter 1 (DRAM refresh)
        out 0xd,al                              ; E089  DMA master clear
        mov al,0xff                             ; E08B
        out 0x1,al                              ; E08D  DMA ch0 count
        out 0x1,al                              ; E08F  DMA ch0 count
        mov al,0x58                             ; E091
        out 0xb,al                              ; E093  DMA mode register
        mov al,0x0                              ; E095
        out 0x8,al                              ; E097  DMA command/status
        out 0xa,al                              ; E099  DMA mask register
        mov cx,0x3                              ; E09B
        mov al,0x41                             ; E09E
L_E0A0:
        out 0xb,al                              ; E0A0  DMA mode register
        inc al                                  ; E0A2
        loop L_E0A0                             ; E0A4
        mov al,0x13                             ; E0A6
        out 0x20,al                             ; E0A8  8259 PIC ICW1/OCW
        mov al,0x8                              ; E0AA
        out 0x21,al                             ; E0AC  8259 PIC IMR/ICW2-4
        inc al                                  ; E0AE
        out 0x21,al                             ; E0B0  8259 PIC IMR/ICW2-4
        mov al,0xff                             ; E0B2
        out 0x21,al                             ; E0B4  8259 PIC IMR/ICW2-4

; ---------------------------------------------------------------------
;  Zero RAM in 64 KB chunks (initialises parity).  The number of chunks is
;  SW1-3/4 (port 60 bits 2-3) + 1, as on the IBM 5150.  The warm-boot flag
;  at 40:72 is saved in SI across the clear.
; ---------------------------------------------------------------------
clear_low_ram:
        mov ax,0x40                             ; E0B6
        mov ds,ax                               ; E0B9
        mov si,[0x72]                           ; E0BB
        db 0x2B, 0xDB                           ; E0BF  (sub bx,bx)
        db 0x33, 0xC0                           ; E0C1  (xor ax,ax)
        in al,0x60                              ; E0C3  SW1 bits 2-3
        shr al,1                                ; E0C5
        shr al,1                                ; E0C7
        and al,0x3                              ; E0C9
        xchg ah,al                              ; E0CB
        inc ah                                  ; E0CD
        cld                                     ; E0CF
L_E0D0:
        mov al,0x0                              ; E0D0
        db 0x2B, 0xFF                           ; E0D2  (sub di,di)
        db 0x33, 0xC9                           ; E0D4  (xor cx,cx)
        mov es,bx                               ; E0D6
L_E0D8:
        stosb                                   ; E0D8
        loop L_E0D8                             ; E0D9
        add bx,0x1000                           ; E0DB
        in al,0x61                              ; E0DF  8255 PPI port B (control)
        and al,0xfd                             ; E0E1  tone off after the first 64 KB
        out 0x61,al                             ; E0E3  8255 PPI port B (control)
        dec ah                                  ; E0E5
        jnz L_E0D0                              ; E0E7
        mov [0x72],si                           ; E0E9
        cmp si,0x1234                           ; E0ED  warm boot (Ctrl+Alt+Del)?
        jz post_with_stack                      ; E0F1
        db 0x33, 0xC0                           ; E0F3  (xor ax,ax)
        mov [0x72],ax                           ; E0F5
        mov ds,ax                               ; E0F8
        mov bp,0x8080                           ; E0FA  64 KB, parity mask 80h
        mov sp,0xe004                           ; E0FD  SP -> E004: return to E103
        jmp near test_ram_stackless             ; E100
after_ram64k_test:
        jc L_E10D                               ; E103  RAM data error -> HLT
        jz post_with_stack                      ; E105
        in al,0x61                              ; E107  8255 PPI port B (control)
        or al,0x3                               ; E109
        out 0x61,al                             ; E10B  8255 PPI port B (control)
L_E10D:
        hlt                                     ; E10D

; ---------------------------------------------------------------------
;  First 64 KB is good: stack at 0030:0100, load interrupt vectors,
;  read SW1 into the equipment word (40:10), initialise video.
; ---------------------------------------------------------------------
post_with_stack:
        in al,0x61                              ; E10E  8255 PPI port B (control)
        or al,0x30                              ; E110
        out 0x61,al                             ; E112  8255 PPI port B (control)
        mov bx,0x30                             ; E114
        mov ss,bx                               ; E117
        mov sp,0x100                            ; E119
        call set_ds_bda                         ; E11C
        db 0x33, 0xFF                           ; E11F  (xor di,di)
        mov cx,0x20                             ; E121
        mov si,0xfea8                           ; E124
        call copy_vectors                       ; E127
        db 0x2B, 0xC0                           ; E12A  (sub ax,ax)
        in al,0x60                              ; E12C  read SW1
        mov [0x10],ax                           ; E12E  equipment word = raw SW1
        and al,0x30                             ; E131  video type bits 4-5
        jnz init_video                          ; E133
no_video:
        push es                                 ; E135
        db 0x33, 0xC9                           ; E136  (xor cx,cx)
        mov es,cx                               ; E138
        mov word [es:0x40],0xff4c               ; E13A  no video: INT 10h -> dummy IRET
        pop es                                  ; E141
        jmp near scan_video_roms                ; E142
init_video:
        xchg ah,al                              ; E145
        inc al                                  ; E147
        cmp ah,0x10                             ; E149
        jz L_E157                               ; E14C
        inc al                                  ; E14E
        cmp ah,0x30                             ; E150
        jz L_E157                               ; E153
        inc al                                  ; E155
L_E157:
        mov [0x49],al                           ; E157
        mov bx,0xb800                           ; E15A
        mov dx,0x3d8                            ; E15D
        mov bp,0x2000                           ; E160
        mov ch,0x0                              ; E163
        cmp ah,0x30                             ; E165
        jnz L_E174                              ; E168
        mov bh,0xb0                             ; E16A
        mov dx,0x3b8                            ; E16C
        mov bp,0x800                            ; E16F
        inc ch                                  ; E172
L_E174:
        db 0x8A, 0xCA                           ; E174  (mov cl,dl)
        sub cl,0x4                              ; E176
        db 0x32, 0xE4                           ; E179  (xor ah,ah)
        int 0x10                                ; E17B
        db 0x8A, 0xC5                           ; E17D  (mov al,ch)
        cmp word [0x72],0x1234                  ; E17F
        jz scan_video_roms                      ; E185
        out dx,al                               ; E187
        mov es,bx                               ; E188
        db 0x2B, 0xFF                           ; E18A  (sub di,di)
        db 0x8B, 0xC7                           ; E18C  (mov ax,di)
        db 0x8B, 0xCD                           ; E18E  (mov cx,bp)
        rep stosw                               ; E190
        push ds                                 ; E192
        mov ds,bx                               ; E193
        call test_ram_stackless                 ; E195  test video RAM
        pop ds                                  ; E198
        jz L_E1A3                               ; E199
        mov dx,0x5                              ; E19B  1 long, 2 short
L_E19E:
        call beep_code                          ; E19E
        jmp short no_video                      ; E1A1
L_E1A3:
        call set_video_mode                     ; E1A3
        mov ax,0x7020                           ; E1A6
        db 0x33, 0xFF                           ; E1A9  (xor di,di)
        mov cx,0x28                             ; E1AB
        rep stosw                               ; E1AE
        mov dl,[0x10]                           ; E1B0
        and dl,0x30                             ; E1B4
        cmp dl,0x30                             ; E1B7
        mov dx,0x3ba                            ; E1BA
        jz L_E1C2                               ; E1BD
        mov dx,0x3da                            ; E1BF
L_E1C2:
        mov bl,0x8                              ; E1C2
L_E1C4:
        db 0x33, 0xC9                           ; E1C4  (xor cx,cx)
L_E1C6:
        in al,dx                                ; E1C6  wait for vertical retrace bit to toggle
        db 0x22, 0xC3                           ; E1C7  (and al,bl)
        jnz L_E1CF                              ; E1C9
        loop L_E1C6                             ; E1CB
        jmp short L_E1E3                        ; E1CD
L_E1CF:
        db 0x33, 0xC9                           ; E1CF  (xor cx,cx)
L_E1D1:
        in al,dx                                ; E1D1
        db 0x22, 0xC3                           ; E1D2  (and al,bl)
        jz L_E1DA                               ; E1D4
        loop L_E1D1                             ; E1D6
        jmp short L_E1E3                        ; E1D8
L_E1DA:
        and bl,0x8                              ; E1DA
        jz L_E1E8                               ; E1DD
        mov bl,0x1                              ; E1DF
        jmp short L_E1C4                        ; E1E1
L_E1E3:
        mov dx,0x7                              ; E1E3  1 long, 3 short
        jmp short L_E19E                        ; E1E6
L_E1E8:
        call set_video_mode                     ; E1E8

; ---------------------------------------------------------------------
;  Scan C000-C7FF for a video option ROM (EGA etc.), then on a cold boot
;  show the RGB colour bars (colour modes only) and "* SELF-TEST *".
; ---------------------------------------------------------------------
scan_video_roms:
        mov dx,0xc000                           ; E1EB
        mov cx,0xc800                           ; E1EE
        call scan_option_roms                   ; E1F1
        cmp word [0x72],0x1234                  ; E1F4
        jz test_8259                            ; E1FA
        mov al,[0x49]                           ; E1FC
        cmp al,0x7                              ; E1FF
        jz L_E22F                               ; E201
        ror al,1                                ; E203
        jnc L_E22F                              ; E205
        mov cx,0x28                             ; E207
        ror al,1                                ; E20A
        jnc show_colour_bars                    ; E20C
        mov cx,0x50                             ; E20E
show_colour_bars:
        mov si,0xe81f                           ; E211
L_E214:
        db 0x33, 0xDB                           ; E214  (xor bx,bx)
        mov ax,[cs:si]                          ; E216
        db 0x0A, 0xC0                           ; E219  (or al,al)
        jz L_E22A                               ; E21B
        db 0x8A, 0xDC                           ; E21D  (mov bl,ah)
        mov ah,0x9                              ; E21F
        int 0x10                                ; E221  write char/attr CX times = full-width colour bar
        call print_crlf                         ; E223
        inc si                                  ; E226
        inc si                                  ; E227
        jmp short L_E214                        ; E228
L_E22A:
        mov cx,0x1                              ; E22A
        jmp short L_E232                        ; E22D
L_E22F:
        mov cx,0x4                              ; E22F
L_E232:
        call print_crlf                         ; E232
        loop L_E232                             ; E235
        mov si,0xff14                           ; E237
        call print_msg_indented                 ; E23A

; ---------------------------------------------------------------------
;  8259 test: IMR read/write, then point IRQ 0-7 at a handler that sets BL;
;  with all IRQs masked, any interrupt that arrives = "8259 Error !"
; ---------------------------------------------------------------------
test_8259:
        cli                                     ; E23D
        mov dx,0x21                             ; E23E
        call test_port_rw                       ; E241
        jnz L_E266                              ; E244
        cld                                     ; E246
        db 0x33, 0xC0                           ; E247  (xor ax,ax)
        mov es,ax                               ; E249
        mov cx,0x8                              ; E24B
        mov di,0x20                             ; E24E
L_E251:
        mov ax,0xe6df                           ; E251  temporary IRQ handler sets BL=1
        stosw                                   ; E254
        mov ax,0xf000                           ; E255
        stosw                                   ; E258
        loop L_E251                             ; E259
        db 0x32, 0xDB                           ; E25B  (xor bl,bl)
        sti                                     ; E25D
        db 0x33, 0xC9                           ; E25E  (xor cx,cx)
L_E260:
        loop L_E260                             ; E260
        db 0x0A, 0xDB                           ; E262  (or bl,bl)
        jz test_keyboard                        ; E264
L_E266:
        mov si,0xfefc                           ; E266
        call print_error                        ; E269
test_keyboard:
        call init_pit0                          ; E26C
        call reset_keyboard                     ; E26F
        jcxz L_E27D                             ; E272
        mov al,0x4d                             ; E274  keyboard clock/enable back to normal
        out 0x61,al                             ; E276  8255 PPI port B (control)
        cmp ah,0xaa                             ; E278  AAh = keyboard self-test OK
        jz ram_prompt                           ; E27B
L_E27D:
        mov si,0xff0a                           ; E27D
        call print_error                        ; E280

; ---------------------------------------------------------------------
;  "RAM TEST (Y/N) ?"  - Y does a full 3-pattern test of every byte,
;  anything else (or no key) just probes one byte per KB.  Memory is
;  counted upward from 64 KB in 1 KB steps up to 640 KB.
;  "WARNING: RAM" if the size is not a multiple of 64 KB, or if RAM is
;  found again after the first failing bank (a hole).
; ---------------------------------------------------------------------
ram_prompt:
        mov si,0xe2d4                           ; E283
        call print_msg_indented                 ; E286
        call ask_ram_test                       ; E289
        call size_ram                           ; E28C
        db 0x8B, 0xF8                           ; E28F  (mov di,ax)
        cmp di,0x280                            ; E291  640 KB?
        jnc ram_done                            ; E295
        db 0x33, 0xD2                           ; E297  (xor dx,dx)
        mov cx,0x40                             ; E299
        div cx                                  ; E29C  multiple of 64 KB?
        cmp dx,byte +0x0                        ; E29E
        jz L_E2AF                               ; E2A1
L_E2A3:
        call print_crlf                         ; E2A3
        mov si,0xe2f9                           ; E2A6
        call print_error                        ; E2A9
        jmp short ram_done                      ; E2AC
        db 0x90                                 ; E2AE
L_E2AF:
        add di,byte +0x40                       ; E2AF
        cmp di,0x280                            ; E2B2
        jnc ram_done                            ; E2B6
        add bx,0x1000                           ; E2B8  probe the next 64 KB bank
        mov ax,0x1                              ; E2BC
        call test_ram_block                     ; E2BF
        jnc L_E2A3                              ; E2C2
        jmp short L_E2AF                        ; E2C4
ram_done:
        cmp word [0x72],0x1234                  ; E2C6
        jz L_E2D1                               ; E2CC
        call zero_ram_above_64k                 ; E2CE
L_E2D1:
        jmp near init_bda                       ; E2D1
msg_ram_test:
        db 'RAM TEST (Y/N) ? ', 0x00            ; E2D4
msg_ram_size:
        db 'RAM SIZE (K)  ', 0x00               ; E2E6
msg_yes:
        db 'Y', 0x00                            ; E2F5
msg_no:
        db 'N', 0x00                            ; E2F7
msg_ram_warning:
        db 'WARNING: RAM', 0x00                 ; E2F9

; ---------------------------------------------------------------------
;  Wait briefly for a key, polling the keyboard port directly with IRQ1
;  masked.  Scan code 15h ('Y') -> DX=FFh, any other key or time-out -> 0.
; ---------------------------------------------------------------------
ask_ram_test:
        cli                                     ; E306
        in al,0x61                              ; E307  8255 PPI port B (control)
        and al,0xfa                             ; E309
        db 0x8A, 0xF8                           ; E30B  (mov bh,al)
        mov al,0x4d                             ; E30D
        out 0x61,al                             ; E30F  8255 PPI port B (control)
        mov di,0x1                              ; E311
L_E314:
        mov cx,0x150                            ; E314
L_E317:
        mov si,0x100                            ; E317
L_E31A:
        cli                                     ; E31A
        mov al,0xfd                             ; E31B
        out 0x21,al                             ; E31D  8259 PIC IMR/ICW2-4
        in al,0x61                              ; E31F  8255 PPI port B (control)
        mov al,0x4d                             ; E321
        out 0x61,al                             ; E323  8255 PPI port B (control)
        in al,0x60                              ; E325  8255 PPI port A (keyboard / SW1)
        db 0x8A, 0xD8                           ; E327  (mov bl,al)
        cmp bl,0x15                             ; E329  scan code 15h = Y
        jz L_E346                               ; E32C
        dec si                                  ; E32E
        jnz L_E31A                              ; E32F
        cmp bl,0x1                              ; E331
        jc L_E33E                               ; E334
        cmp bl,0x55                             ; E336
        ja L_E33E                               ; E339
        jmp short L_E34F                        ; E33B
        db 0x90                                 ; E33D
L_E33E:
        loop L_E317                             ; E33E
        dec di                                  ; E340
        jnz L_E314                              ; E341
        jmp short L_E34F                        ; E343
        db 0x90                                 ; E345
L_E346:
        mov dx,0xff                             ; E346
        mov si,0xe2f5                           ; E349
        jmp short L_E355                        ; E34C
        db 0x90                                 ; E34E
L_E34F:
        mov dx,0x0                              ; E34F
        mov si,0xe2f7                           ; E352
L_E355:
        push dx                                 ; E355
        in al,0x61                              ; E356  8255 PPI port B (control)
        db 0x8A, 0xE0                           ; E358  (mov ah,al)
        or al,0x80                              ; E35A
        out 0x61,al                             ; E35C  8255 PPI port B (control)
        db 0x8A, 0xC4                           ; E35E  (mov al,ah)
        out 0x61,al                             ; E360  8255 PPI port B (control)
        mov al,0x20                             ; E362
        out 0x20,al                             ; E364  8259 PIC ICW1/OCW
        call print_string                       ; E366
        db 0x8A, 0xC7                           ; E369  (mov al,bh)
        out 0x61,al                             ; E36B  8255 PPI port B (control)
        cli                                     ; E36D
        mov al,0xff                             ; E36E
        out 0x21,al                             ; E370  8259 PIC IMR/ICW2-4
        pop dx                                  ; E372
        ret                                     ; E373
print_kb_count:
        push ax                                 ; E374
        push bx                                 ; E375
        call set_ds_bda                         ; E376
        push di                                 ; E379
        mov cx,0x4                              ; E37A
        mov di,0x67                             ; E37D
        call bin_to_dec                         ; E380
        mov si,0x67                             ; E383
        pop di                                  ; E386
        mov byte [0x50],0x1c                    ; E387
        mov cx,0x4                              ; E38C
L_E38F:
        mov al,[si]                             ; E38F
        mov ah,0xe                              ; E391
        mov bl,0x0                              ; E393
        int 0x10                                ; E395
        inc si                                  ; E397
        loop L_E38F                             ; E398
        pop bx                                  ; E39A
        pop ax                                  ; E39B
        ret                                     ; E39C
size_ram:
        push dx                                 ; E39D
        call print_crlf                         ; E39E
        call set_ds_bda                         ; E3A1
        mov word [0x13],0x40                    ; E3A4
        mov si,0xe2e6                           ; E3AA
        call print_msg_indented                 ; E3AD
        mov ax,0x40                             ; E3B0
        call print_kb_count                     ; E3B3
        mov bx,0x1000                           ; E3B6
        pop dx                                  ; E3B9
        cmp dx,byte +0x0                        ; E3BA
        jz L_E3C5                               ; E3BD
        mov ax,0x400                            ; E3BF  Y: test all 1024 bytes of each KB
        jmp short L_E3C8                        ; E3C2
        db 0x90                                 ; E3C4
L_E3C5:
        mov ax,0x1                              ; E3C5  N: probe one byte per KB
L_E3C8:
        push ax                                 ; E3C8
        call test_ram_block                     ; E3C9
        jc L_E3E3                               ; E3CC
        inc word [0x13]                         ; E3CE
        mov ax,[0x13]                           ; E3D2
        call print_kb_count                     ; E3D5
        cmp ax,0x280                            ; E3D8  stop at 640 KB
        jnc L_E3E3                              ; E3DB
        add bx,byte +0x40                       ; E3DD
        pop ax                                  ; E3E0
        jmp short L_E3C8                        ; E3E1
L_E3E3:
        pop ax                                  ; E3E3
        mov ax,[0x13]                           ; E3E4
        ret                                     ; E3E7
zero_ram_above_64k:
        cli                                     ; E3E8
        mov di,ss                               ; E3E9
        db 0x8B, 0xF4                           ; E3EB  (mov si,sp)
        mov dx,[0x13]                           ; E3ED
        sub dx,byte +0x40                       ; E3F1
        jz L_E40D                               ; E3F4
        mov ax,0x0                              ; E3F6
        mov bx,0x1000                           ; E3F9
L_E3FC:
        mov cx,0x200                            ; E3FC
        mov ss,bx                               ; E3FF
        mov sp,0x400                            ; E401
L_E404:
        push ax                                 ; E404
        loop L_E404                             ; E405
        add bx,byte +0x40                       ; E407
        dec dx                                  ; E40A
        jnz L_E3FC                              ; E40B
L_E40D:
        db 0x8B, 0xE6                           ; E40D  (mov sp,si)
        mov ss,di                               ; E40F
        ret                                     ; E411
bin_to_dec:
        push dx                                 ; E412
        call set_ds_bda                         ; E413
        dec di                                  ; E416
        db 0x03, 0xF9                           ; E417  (add di,cx)
L_E419:
        mov bx,0xa                              ; E419
        db 0x33, 0xD2                           ; E41C  (xor dx,dx)
        div bx                                  ; E41E
        add dl,0x30                             ; E420
        mov [di],dl                             ; E423
        dec di                                  ; E425
        db 0x0B, 0xC0                           ; E426  (or ax,ax)
        loopne L_E419                           ; E428
        jcxz L_E432                             ; E42A
L_E42C:
        mov byte [di],0x30                      ; E42C
        dec di                                  ; E42F
        loop L_E42C                             ; E430
L_E432:
        pop dx                                  ; E432
        ret                                     ; E433
test_ram_block:
        push di                                 ; E434
        push ds                                 ; E435
        push dx                                 ; E436
        push cx                                 ; E437
        push bx                                 ; E438
        db 0x8B, 0xC8                           ; E439  (mov cx,ax)
        mov ds,bx                               ; E43B
        mov dx,0x40                             ; E43D
        mov es,dx                               ; E440
        call test_ram_bytes                     ; E442
        pop bx                                  ; E445
        pop cx                                  ; E446
        pop dx                                  ; E447
        pop ds                                  ; E448
        pop di                                  ; E449
        ret                                     ; E44A

; ---------------------------------------------------------------------
;  Test CX bytes at DS:0 with the three patterns at E491 (55h, ABh, 00h),
;  also failing on a parity / I/O-check bit in port 62h.  On a warm boot
;  the original byte is restored.  CF=1 on failure.
; ---------------------------------------------------------------------
test_ram_bytes:
        in al,0x61                              ; E44B  8255 PPI port B (control)
        or al,0x30                              ; E44D
        out 0x61,al                             ; E44F  8255 PPI port B (control)
        and al,0xcf                             ; E451
        out 0x61,al                             ; E453  8255 PPI port B (control)
        db 0x33, 0xF6                           ; E455  (xor si,si)
L_E457:
        db 0x8B, 0xD1                           ; E457  (mov dx,cx)
        cld                                     ; E459
        mov di,0xe491                           ; E45A
        cmp word [es:0x472],0x1234              ; E45D
        jnz L_E468                              ; E464
        mov bh,[si]                             ; E466
L_E468:
        mov cx,0x3                              ; E468
L_E46B:
        mov ah,[cs:di]                          ; E46B
        mov [si],ah                             ; E46E
        xor ah,[si]                             ; E470
        jnz L_E48F                              ; E472
        in al,0x62                              ; E474  parity / I/O channel check bits
        and al,0xc0                             ; E476
        jnz L_E48F                              ; E478
        inc di                                  ; E47A
        loop L_E46B                             ; E47B
        cmp word [es:0x472],0x1234              ; E47D
        jnz L_E488                              ; E484
        mov [si],bh                             ; E486
L_E488:
        db 0x8B, 0xCA                           ; E488  (mov cx,dx)
        inc si                                  ; E48A
        loop L_E457                             ; E48B
        clc                                     ; E48D
        ret                                     ; E48E
L_E48F:
        stc                                     ; E48F
        ret                                     ; E490
ram_test_patterns:
        db 0x55, 0xAB, 0x00                     ; E491

; ---------------------------------------------------------------------
;  Option ROM scan from segment DX to CX in 2 KB steps.  A ROM is any
;  block starting 55 AA; it is called at offset 3 and skipped by
;  (byte 2 x 512).  NOTE: unlike IBM, no checksum is verified.
; ---------------------------------------------------------------------
scan_option_roms:
        push ds                                 ; E494
L_E495:
        mov ds,dx                               ; E495
        db 0x33, 0xDB                           ; E497  (xor bx,bx)
        mov ax,[bx]                             ; E499
        cmp ax,0xaa55                           ; E49B  option ROM signature
        jnz L_E4C7                              ; E49E
        push cx                                 ; E4A0
        mov bl,[bx+0x2]                         ; E4A1
        db 0x32, 0xFF                           ; E4A4  (xor bh,bh)
        mov cl,0x5                              ; E4A6
        shl bx,cl                               ; E4A8
        db 0x03, 0xD3                           ; E4AA  (add dx,bx)
        mov bx,0x40                             ; E4AC
        push dx                                 ; E4AF
        mov es,bx                               ; E4B0
        mov word [es:0x467],0x3                 ; E4B2
        mov [es:0x469],ds                       ; E4B9
        call far [es:0x467]                     ; E4BE  far call ROM:0003
        pop dx                                  ; E4C3
        pop cx                                  ; E4C4
        jmp short L_E4CB                        ; E4C5
L_E4C7:
        add dx,0x80                             ; E4C7
L_E4CB:
        db 0x3B, 0xD1                           ; E4CB  (cmp dx,cx)
        jc L_E495                               ; E4CD
        pop ds                                  ; E4CF
        ret                                     ; E4D0

; ---------------------------------------------------------------------
;  BIOS data area: keyboard buffer (40:1A/1C/80/82), printer and serial
;  time-outs (40:78-7F), real IRQ vectors, then the printer port at 378h.
; ---------------------------------------------------------------------
init_bda:
        mov di,0x1e                             ; E4D1
        mov [0x1a],di                           ; E4D4
        mov [0x1c],di                           ; E4D8
        mov [0x80],di                           ; E4DC
        add di,byte +0x20                       ; E4E0
        mov [0x82],di                           ; E4E3
        push ds                                 ; E4E7
        pop es                                  ; E4E8
        mov di,0x78                             ; E4E9
        mov ax,0x1414                           ; E4EC  printer time-outs 20
        stosw                                   ; E4EF
        stosw                                   ; E4F0
        mov ax,0x101                            ; E4F1  serial time-outs 1
        stosw                                   ; E4F4
        stosw                                   ; E4F5
        mov cx,0x8                              ; E4F6
        mov di,0x20                             ; E4F9
        mov si,0xfeb8                           ; E4FC
        call copy_vectors                       ; E4FF
        mov dx,0x378                            ; E502
        call test_port_rw                       ; E505
        jnz L_E516                              ; E508
        mov dx,0x37a                            ; E50A  printer port found: init it
        mov al,0x8                              ; E50D
        out dx,al                               ; E50F
        mov al,0xc                              ; E510
        out dx,al                               ; E512
        jmp short test_floppy                   ; E513
        db 0x90                                 ; E515
L_E516:
        mov si,0xff01                           ; E516
        call print_msg_indented                 ; E519

; ---------------------------------------------------------------------
;  Unmask IRQ 0,1,6.  If SW1-1 says diskettes are fitted: reset the
;  controller, start drive A's motor and seek to track 39.
; ---------------------------------------------------------------------
test_floppy:
        mov al,0xbc                             ; E51C
        out 0x21,al                             ; E51E  unmask IRQ 0, 1, 6
        mov al,[0x10]                           ; E520  SW1-1: diskettes fitted?
        and al,0x1                              ; E523
        jnz L_E52A                              ; E525
        jmp short detect_ports                  ; E527
        db 0x90                                 ; E529
L_E52A:
        mov ah,0x0                              ; E52A
        db 0x8A, 0xD4                           ; E52C  (mov dl,ah)
        and byte [0x40],0x0                     ; E52E
        or byte [0x3f],0x1c                     ; E533
        int 0x13                                ; E538
        test ah,0xff                            ; E53A
        jnz L_E55F                              ; E53D
        mov dx,0x3f2                            ; E53F
        mov al,0x1c                             ; E542
        out dx,al                               ; E544
        db 0x33, 0xC9                           ; E545  (xor cx,cx)
L_E547:
        loop L_E547                             ; E547
L_E549:
        loop L_E549                             ; E549
        db 0x33, 0xD2                           ; E54B  (xor dx,dx)
        mov ch,0x27                             ; E54D  seek drive A to track 39
        mov [0x3e],dl                           ; E54F
        or byte [0x3f],0x11                     ; E553
        push ds                                 ; E558
        call sub_F825                           ; E559
        pop ds                                  ; E55C
        jnc L_E565                              ; E55D
L_E55F:
        mov si,0xff0f                           ; E55F
        call print_error                        ; E562
L_E565:
        mov al,0xc                              ; E565
        mov dx,0x3f2                            ; E567
        out dx,al                               ; E56A

; ---------------------------------------------------------------------
;  Hardware detection for the equipment word: printers at 3BC/378/278,
;  game port at 201h, serial ports at 3F8/2F8 (via the IIR register).
;  Then enable NMI; with no diskettes, go straight to INT 18h.
; ---------------------------------------------------------------------
detect_ports:
        mov bp,0xe817                           ; E56B
        db 0x33, 0xDB                           ; E56E  (xor bx,bx)
L_E570:
        mov dx,[cs:bp+0x0]                      ; E570
        db 0x0B, 0xD2                           ; E574  (or dx,dx)
        jz L_E588                               ; E576
        call test_port_rw                       ; E578
        jnz L_E584                              ; E57B
        db 0x89, 0x97, 0x08, 0x00               ; E57D  (mov [bx+0x8],dx)
        add bl,0x2                              ; E581
L_E584:
        inc bp                                  ; E584
        inc bp                                  ; E585
        jmp short L_E570                        ; E586
L_E588:
        ror bl,1                                ; E588
        ror bl,1                                ; E58A
        ror bl,1                                ; E58C
        or [0x11],bl                            ; E58E
        mov dx,0x201                            ; E592  game port
        in al,dx                                ; E595
        test al,0xf                             ; E596
        jnz L_E5A2                              ; E598
        mov al,0x0                              ; E59A
        out dx,al                               ; E59C
        or byte [0x11],0x10                     ; E59D
L_E5A2:
        db 0x33, 0xDB                           ; E5A2  (xor bx,bx)
        mov cx,0x2                              ; E5A4
        mov dx,0x3fa                            ; E5A7  COM1 IIR; next pass 2FAh
L_E5AA:
        in al,dx                                ; E5AA
        sub dl,0x2                              ; E5AB
        test al,0xf8                            ; E5AE
        jnz L_E5B9                              ; E5B0
        db 0x89, 0x97, 0x00, 0x00               ; E5B2  (mov [bx+0x0],dx)
        add bl,0x2                              ; E5B6
L_E5B9:
        sub dx,0xfe                             ; E5B9
        loop L_E5AA                             ; E5BD
        or [0x11],bl                            ; E5BF
        mov al,0x80                             ; E5C3
        out 0xa0,al                             ; E5C5  enable NMI
        mov al,[0x10]                           ; E5C7
        and al,0x1                              ; E5CA
        jnz post_finish                         ; E5CC
        int 0x18                                ; E5CE  no diskettes: ROM BASIC / no system

; ---------------------------------------------------------------------
;  End of POST: clear the screen, "BIOS Version 3.30", scan C800-F5FF for
;  option ROMs, unmask timer/keyboard, set the beep pitch, INT 19h.
; ---------------------------------------------------------------------
post_finish:
        call set_video_mode                     ; E5D0
        mov si,0xff33                           ; E5D3
        call print_string                       ; E5D6
        mov dx,0xc800                           ; E5D9
        mov cx,0xf600                           ; E5DC
        call scan_option_roms                   ; E5DF
        in al,0x21                              ; E5E2  8259 PIC IMR/ICW2-4
        and al,0xfc                             ; E5E4
        out 0x21,al                             ; E5E6  8259 PIC IMR/ICW2-4
        mov al,0xb6                             ; E5E8
        out 0x43,al                             ; E5EA  8253 PIT mode control
        mov al,0x4                              ; E5EC  beep pitch for later beeps
        out 0x42,al                             ; E5EE  8253 PIT counter 2 (speaker)
        out 0x42,al                             ; E5F0  8253 PIT counter 2 (speaker)
        int 0x19                                ; E5F2  boot
set_video_mode:
        mov ah,0x0                              ; E5F4
        mov al,[0x49]                           ; E5F6
        int 0x10                                ; E5F9
        ret                                     ; E5FB

; =====================================================================
;  INT 19h - BOOTSTRAP.  Three tries to read drive A sector 1 to 0:7C00.
;  Success: point INT 18h at F600:0000, two short beeps, jump to 0:7C00.
;  Failure: INT 18h; if that returns, "* No-System *" and wait for a key.
;  NOTE: not at the IBM address E6F2.
; =====================================================================
int19_bootstrap:
        sti                                     ; E5FC
        call set_ds_bda                         ; E5FD
        mov bp,0x3                              ; E600
L_E603:
        db 0x33, 0xC0                           ; E603  (xor ax,ax)
        int 0x13                                ; E605
        jc L_E61A                               ; E607
        db 0x33, 0xD2                           ; E609  (xor dx,dx)
        mov es,dx                               ; E60B
        mov bx,0x7c00                           ; E60D
        mov cx,0x1                              ; E610
        mov ax,0x201                            ; E613
        int 0x13                                ; E616
        jnc L_E62B                              ; E618
L_E61A:
        dec bp                                  ; E61A
        jnz L_E603                              ; E61B
        int 0x18                                ; E61D
        mov si,0xf725                           ; E61F
        call print_string                       ; E622
        mov ah,0x0                              ; E625
        int 0x16                                ; E627
        jmp short int19_bootstrap               ; E629
L_E62B:
        call set_int18_basic                    ; E62B
        mov dx,0x4                              ; E62E  two short beeps
        call beep_code                          ; E631
        db 0x33, 0xD2                           ; E634  (xor dx,dx)
        jmp 0x0:0x7c00                          ; E636  jump to the boot sector

; =====================================================================
;  INT 18h - ROM BASIC.  Looks for IBM-style cassette BASIC at F6000
;  (first byte E9h, four good 8 KB checksums).  If present, point INT 18h
;  at F600:0000 and call it; otherwise just return (-> "No-System").
; =====================================================================
int18_rom_basic:
        sti                                     ; E63B
        mov bh,0x4                              ; E63C
        mov dx,0xf600                           ; E63E
        push dx                                 ; E641
        pop es                                  ; E642
        db 0x33, 0xF6                           ; E643  (xor si,si)
        cmp byte [es:si],0xe9                   ; E645  BASIC starts with a JMP
        jnz L_E65F                              ; E649
L_E64B:
        db 0x33, 0xF6                           ; E64B  (xor si,si)
        call rom_checksum_8k                    ; E64D  checksum each 8 KB of F6000-FDFFF
        jnz L_E65F                              ; E650
        add dx,0x200                            ; E652
        dec bh                                  ; E656
        jnz L_E64B                              ; E658
        call set_int18_basic                    ; E65A
        int 0x18                                ; E65D
L_E65F:
        iret                                    ; E65F
set_int18_basic:
        db 0x33, 0xC0                           ; E660  (xor ax,ax)
        mov es,ax                               ; E662
        mov word [es:0x60],0x0                  ; E664
        mov word [es:0x62],0xf600               ; E66B
        ret                                     ; E672
print_msg_indented:
        push cx                                 ; E673
        push si                                 ; E674
        call print_crlf                         ; E675
        mov cx,0xa                              ; E678
L_E67B:
        mov si,0xff24                           ; E67B
        call print_string                       ; E67E
        loop L_E67B                             ; E681
        pop si                                  ; E683
        call print_string                       ; E684
        pop cx                                  ; E687
        ret                                     ; E688
print_error:
        call print_msg_indented                 ; E689
        call print_error_suffix                 ; E68C
        ret                                     ; E68F
print_string:
        push bx                                 ; E690
        push ds                                 ; E691
        call set_ds_bda                         ; E692
        mov al,[0x10]                           ; E695
        and al,0x30                             ; E698
        jz L_E6AC                               ; E69A
L_E69C:
        mov ah,0xe                              ; E69C
        db 0x33, 0xDB                           ; E69E  (xor bx,bx)
        mov al,[cs:si]                          ; E6A0
        db 0x0A, 0xC0                           ; E6A3  (or al,al)
        jz L_E6AC                               ; E6A5
        int 0x10                                ; E6A7
        inc si                                  ; E6A9
        jmp short L_E69C                        ; E6AA
L_E6AC:
        pop ds                                  ; E6AC
        pop bx                                  ; E6AD
        ret                                     ; E6AE
print_error_suffix:
        push si                                 ; E6AF
        mov si,0xff2a                           ; E6B0
        call print_string                       ; E6B3
        pop si                                  ; E6B6
        ret                                     ; E6B7
print_crlf:
        push si                                 ; E6B8
        mov si,0xff21                           ; E6B9
        call print_string                       ; E6BC
        pop si                                  ; E6BF
        ret                                     ; E6C0
init_pit0:
        mov al,0x36                             ; E6C1
        out 0x43,al                             ; E6C3  8253 PIT mode control
        mov al,0x0                              ; E6C5
        out 0x40,al                             ; E6C7  8253 PIT counter 0
        out 0x40,al                             ; E6C9  8253 PIT counter 0
        mov al,0xff                             ; E6CB
        out 0x21,al                             ; E6CD  8259 PIC IMR/ICW2-4
        ret                                     ; E6CF
copy_vectors:
        push ds                                 ; E6D0
        db 0x33, 0xC0                           ; E6D1  (xor ax,ax)
        mov es,ax                               ; E6D3
        push cs                                 ; E6D5
        pop ax                                  ; E6D6
        mov ds,ax                               ; E6D7
L_E6D9:
        movsw                                   ; E6D9
        stosw                                   ; E6DA
        loop L_E6D9                             ; E6DB
        pop ds                                  ; E6DD
        ret                                     ; E6DE
irq_test_handler:
        mov bl,0x1                              ; E6DF
        mov al,0xff                             ; E6E1
        out 0x21,al                             ; E6E3  8259 PIC IMR/ICW2-4
        mov al,0x20                             ; E6E5
        out 0x20,al                             ; E6E7  8259 PIC ICW1/OCW
        iret                                    ; E6E9

; =====================================================================
;  INT 02h - NMI: parity error (port 62 bit 7) or I/O channel check (bit 6)
;  -> "P-CK Error !", 10 x (1 long + 5 short) beeps, then HLT.
; =====================================================================
int02_nmi:
        push ax                                 ; E6EA
        in al,0x62                              ; E6EB  8255 PPI port C (status / SW2)
        test al,0x80                            ; E6ED
        jz L_E6F6                               ; E6EF
        mov si,0xff26                           ; E6F1
        jmp short L_E6FD                        ; E6F4
L_E6F6:
        test al,0x40                            ; E6F6
        jz L_E70F                               ; E6F8
        mov si,0xff26                           ; E6FA
L_E6FD:
        call print_string                       ; E6FD
        cli                                     ; E700
        mov cx,0xa                              ; E701
L_E704:
        push cx                                 ; E704
        mov dx,0xb                              ; E705
        call beep_code                          ; E708
        pop cx                                  ; E70B
        loop L_E704                             ; E70C
        hlt                                     ; E70E
L_E70F:
        pop ax                                  ; E70F
        iret                                    ; E710

; ---------------------------------------------------------------------
;  Beep code.  DL odd -> one long beep first; then DL/2 short beeps.
;    DX=4 : 2 short          (boot sector loaded OK)
;    DX=5 : 1 long, 2 short  (video RAM failed)
;    DX=7 : 1 long, 3 short  (no video retrace)
;    DX=B : 1 long, 5 short  (NMI parity / I/O check, repeated 10x)
; ---------------------------------------------------------------------
beep_code:
        push bx                                 ; E711
        push cx                                 ; E712
        push dx                                 ; E713
        db 0x2B, 0xC9                           ; E714  (sub cx,cx)
        db 0x8A, 0xEE                           ; E716  (mov ch,dh)
        pushf                                   ; E718
        cli                                     ; E719
        shr dl,1                                ; E71A
        jnc L_E725                              ; E71C
        mov bl,0x5                              ; E71E
        call beep                               ; E720
L_E723:
        loop L_E723                             ; E723
L_E725:
        mov bl,0x1                              ; E725
L_E727:
        db 0x8A, 0xEE                           ; E727  (mov ch,dh)
        call beep                               ; E729
L_E72C:
        loop L_E72C                             ; E72C
        dec dl                                  ; E72E
        jnz L_E727                              ; E730
        popf                                    ; E732
        pop dx                                  ; E733
        pop cx                                  ; E734
        pop bx                                  ; E735
        ret                                     ; E736
beep:
        push cx                                 ; E737
        push bx                                 ; E738
        push ax                                 ; E739
        db 0x8A, 0xE5                           ; E73A  (mov ah,ch)
        in al,0x61                              ; E73C  8255 PPI port B (control)
        db 0x8A, 0xF8                           ; E73E  (mov bh,al)
        or al,0x3                               ; E740
        out 0x61,al                             ; E742  8255 PPI port B (control)
L_E744:
        db 0x8A, 0xEC                           ; E744  (mov ch,ah)
L_E746:
        loop L_E746                             ; E746
        dec bl                                  ; E748
        jnz L_E744                              ; E74A
        db 0x8A, 0xC7                           ; E74C  (mov al,bh)
        out 0x61,al                             ; E74E  8255 PPI port B (control)
        pop ax                                  ; E750
        pop bx                                  ; E751
        pop cx                                  ; E752
        ret                                     ; E753

; ---------------------------------------------------------------------
;  Keyboard reset: hold the keyboard clock low, release it, wait for IRQ1.
;  Returns the scan code in AH (AAh = keyboard self-test passed).
; ---------------------------------------------------------------------
reset_keyboard:
        mov al,0xc                              ; E754
        out 0x61,al                             ; E756  8255 PPI port B (control)
        mov cx,0x2968                           ; E758
L_E75B:
        loop L_E75B                             ; E75B
        mov al,0x4c                             ; E75D
        out 0x61,al                             ; E75F  8255 PPI port B (control)
        mov dx,0x61                             ; E761
        mov al,0xcc                             ; E764
        out dx,al                               ; E766
        mov al,0x4c                             ; E767
        out dx,al                               ; E769
        mov al,0xfd                             ; E76A
        out 0x21,al                             ; E76C  8259 PIC IMR/ICW2-4
        sti                                     ; E76E
        db 0x32, 0xDB                           ; E76F  (xor bl,bl)
        db 0x33, 0xC9                           ; E771  (xor cx,cx)
L_E773:
        test bl,0xff                            ; E773
        jnz L_E77A                              ; E776
        loop L_E773                             ; E778
L_E77A:
        dec dx                                  ; E77A
        in al,dx                                ; E77B
        db 0x8A, 0xE0                           ; E77C  (mov ah,al)
        mov al,0xcc                             ; E77E
        inc dx                                  ; E780
        out dx,al                               ; E781
        ret                                     ; E782

; ---------------------------------------------------------------------
;  Write 00, 01, FF to port DX and read each back.  ZF=1 = port present.
;  Used for the 8259 IMR, the printer ports and port detection.
; ---------------------------------------------------------------------
test_port_rw:
        push bx                                 ; E783
        push ax                                 ; E784
        mov bx,0xe813                           ; E785
L_E788:
        mov ah,[cs:bx]                          ; E788
        db 0x8A, 0xC4                           ; E78B  (mov al,ah)
        out dx,al                               ; E78D
        nop                                     ; E78E
        nop                                     ; E78F
        db 0x32, 0xC0                           ; E790  (xor al,al)
        in al,dx                                ; E792
        db 0x32, 0xC4                           ; E793  (xor al,ah)
        jnz L_E79E                              ; E795
        inc bx                                  ; E797
        inc ah                                  ; E798
        db 0x0A, 0xE4                           ; E79A  (or ah,ah)
        jnz L_E788                              ; E79C
L_E79E:
        pop ax                                  ; E79E
        pop bx                                  ; E79F
        ret                                     ; E7A0

; ---------------------------------------------------------------------
;  Stackless: PIT channel 2 test.  Latches/reads the count until every
;  bit has been seen 1 and then 0.  Returns via the table at E002.
; ---------------------------------------------------------------------
test_pit_ch2:
        db 0x2B, 0xC9                           ; E7A1  (sub cx,cx)
        out 0x43,al                             ; E7A3  8253 PIT mode control
        db 0x8A, 0xF9                           ; E7A5  (mov bh,cl)
        db 0x8A, 0xC1                           ; E7A7  (mov al,cl)
        out dx,al                               ; E7A9
L_E7AA:
        db 0x8A, 0xC4                           ; E7AA  (mov al,ah)
        out 0x43,al                             ; E7AC  8253 PIT mode control
        in al,dx                                ; E7AE
        db 0x0A, 0xF8                           ; E7AF  (or bh,al)
        cmp bh,0xff                             ; E7B1
        jz L_E7BB                               ; E7B4
        loop L_E7AA                             ; E7B6
        jmp short L_E7CB                        ; E7B8
        db 0x90                                 ; E7BA
L_E7BB:
        db 0x8A, 0xC7                           ; E7BB  (mov al,bh)
        db 0x2B, 0xC9                           ; E7BD  (sub cx,cx)
        out dx,al                               ; E7BF
L_E7C0:
        db 0x8A, 0xC4                           ; E7C0  (mov al,ah)
        out 0x43,al                             ; E7C2  8253 PIT mode control
        in al,dx                                ; E7C4
        db 0x22, 0xF8                           ; E7C5  (and bh,al)
        jz L_E7CD                               ; E7C7
        loop L_E7C0                             ; E7C9
L_E7CB:
        stc                                     ; E7CB
        ret                                     ; E7CC
L_E7CD:
        clc                                     ; E7CD
        ret                                     ; E7CE

; ---------------------------------------------------------------------
;  Stackless RAM test using PUSH/POP with SS=DS (no RAM needed for a stack).
;  BP high byte = word count / 256, BP low byte = port 62 parity mask.
;  Passes: expect 00 write 01, expect 01 write FF, expect FF write 00.
;    BP=8080h : first 64 KB of main RAM, parity checked
;    BP=2000h : 16 KB CGA RAM;  BP=0800h : 4 KB MDA RAM
; ---------------------------------------------------------------------
test_ram_stackless:
        mov si,ss                               ; E7CF
        xchg sp,di                              ; E7D1
        mov bx,ds                               ; E7D3
        mov ss,bx                               ; E7D5
        in al,0x61                              ; E7D7  8255 PPI port B (control)
        and al,0xcf                             ; E7D9
        out 0x61,al                             ; E7DB  8255 PPI port B (control)
        mov bx,0xe812                           ; E7DD
L_E7E0:
        db 0x33, 0xE4                           ; E7E0  (xor sp,sp)
        db 0x8B, 0xCD                           ; E7E2  (mov cx,bp)
        mov cl,0x0                              ; E7E4
        inc bx                                  ; E7E6
        mov dx,[cs:bx]                          ; E7E7
L_E7EA:
        pop ax                                  ; E7EA
        db 0x32, 0xC2                           ; E7EB  (xor al,dl)
        jnz L_E810                              ; E7ED
        db 0x32, 0xE2                           ; E7EF  (xor ah,dl)
        jnz L_E810                              ; E7F1
        xchg bp,dx                              ; E7F3
        in al,0x62                              ; E7F5  8255 PPI port C (status / SW2)
        db 0x22, 0xC2                           ; E7F7  (and al,dl)
        xchg bp,dx                              ; E7F9
        jnz L_E810                              ; E7FB
        db 0x8A, 0xC6                           ; E7FD  (mov al,dh)
        db 0x8A, 0xE6                           ; E7FF  (mov ah,dh)
        push ax                                 ; E801
        inc sp                                  ; E802
        inc sp                                  ; E803
        loop L_E7EA                             ; E804
        db 0x0A, 0xF6                           ; E806  (or dh,dh)
        jnz L_E7E0                              ; E808
        clc                                     ; E80A
L_E80B:
        mov ss,si                               ; E80B
        xchg sp,di                              ; E80D
        ret                                     ; E80F
L_E810:
        stc                                     ; E810
        jmp short L_E80B                        ; E811

; ---------------------------------------------------------------------
;  Shared data: test patterns (E813: 00 01 FF 00), printer port list
;  (E817: 3BC 378 278 0), colour bar chars/attributes (E81F: R G B)
; ---------------------------------------------------------------------
test_patterns:
        db 0x00, 0x01, 0xFF, 0x00               ; E813
lpt_port_list:
        db 0xBC, 0x03, 0x78, 0x03               ; E817
        db 0x78, 0x02, 0x00, 0x00               ; E81B
colour_bar_table:
        db 0x52, 0x40, 0x47, 0xAE               ; E81F
        db 0x42, 0x10, 0x00, 0x00               ; E823
        db 0x00, 0x00, 0x00, 0x00               ; E827
        db 0x00, 0x00, 0x00                     ; E82B
int16_entry:
        jmp near int16_keyboard                 ; E82E

; =====================================================================
;  INT 14h - SERIAL (functions 0-3).  NOTE: not at the IBM address E739.
; =====================================================================
int14_serial:
        sti                                     ; E831
        push ds                                 ; E832
        push dx                                 ; E833
        push si                                 ; E834
        push di                                 ; E835
        push cx                                 ; E836
        db 0x8B, 0xF2                           ; E837  (mov si,dx)
        shl si,1                                ; E839
        call set_ds_bda                         ; E83B
        db 0x8B, 0x94, 0x00, 0x00               ; E83E  (mov dx,[si+0x0])
        db 0x0B, 0xD2                           ; E842  (or dx,dx)
        jnz L_E849                              ; E844
        jmp near L_E906                         ; E846
L_E849:
        push bx                                 ; E849
        db 0x8B, 0xD8                           ; E84A  (mov bx,ax)
        cmp ah,0x3                              ; E84C
        ja L_E881                               ; E84F
        jz L_E884                               ; E851
        dec ah                                  ; E853
        js L_E888                               ; E855
        dec ah                                  ; E857
        js L_E88B                               ; E859
        add dx,byte +0x4                        ; E85B
        mov al,0x1                              ; E85E
        out dx,al                               ; E860
        inc dx                                  ; E861
        inc dx                                  ; E862
        mov bh,0x20                             ; E863
        call serial_wait_status                 ; E865
        jnc L_E870                              ; E868
L_E86A:
        or ah,0x80                              ; E86A
        jmp near L_E905                         ; E86D
L_E870:
        dec dx                                  ; E870
        mov bh,0x1                              ; E871
        call serial_wait_status                 ; E873
        jnc L_E87A                              ; E876
        jmp short L_E86A                        ; E878
L_E87A:
        and ah,0x1e                             ; E87A
        sub dx,byte +0x5                        ; E87D
        in al,dx                                ; E880
L_E881:
        jmp near L_E905                         ; E881
L_E884:
        inc dx                                  ; E884
        jmp short L_E8F3                        ; E885
        db 0x90                                 ; E887
L_E888:
        jmp short L_E8C2                        ; E888
        db 0x90                                 ; E88A
L_E88B:
        mov al,0x3                              ; E88B
        add dx,byte +0x4                        ; E88D
        out dx,al                               ; E890
        inc dx                                  ; E891
        inc dx                                  ; E892
        mov bh,0x30                             ; E893
        call serial_wait_status                 ; E895
        jnc L_E8A2                              ; E898
L_E89A:
        sub dx,byte +0x5                        ; E89A
        mov ch,0x80                             ; E89D
        jmp short L_E8F5                        ; E89F
        db 0x90                                 ; E8A1
L_E8A2:
        dec dx                                  ; E8A2
        mov bh,0x20                             ; E8A3
        call serial_wait_status                 ; E8A5
        jnc L_E8AD                              ; E8A8
        inc dx                                  ; E8AA
        jmp short L_E89A                        ; E8AB
L_E8AD:
        db 0x8A, 0xC3                           ; E8AD  (mov al,bl)
        sub dx,byte +0x5                        ; E8AF
        out dx,al                               ; E8B2
        jmp short L_E905                        ; E8B3
        db 0x90                                 ; E8B5
serial_wait_status:
        push bx                                 ; E8B6
        push bp                                 ; E8B7
        db 0x8A, 0xAC, 0x7C, 0x00               ; E8B8  (mov ch,[si+0x7c])
        call wait_status_bits                   ; E8BC
        pop bp                                  ; E8BF
        pop bx                                  ; E8C0
        ret                                     ; E8C1
L_E8C2:
        and al,0xe0                             ; E8C2
        mov cl,0x5                              ; E8C4
        shr al,cl                               ; E8C6
        db 0x8A, 0xC8                           ; E8C8  (mov cl,al)
        mov ax,0x417                            ; E8CA
        db 0x0A, 0xC9                           ; E8CD  (or cl,cl)
        jz L_E8D6                               ; E8CF
        mov ax,0x600                            ; E8D1
        shr ax,cl                               ; E8D4
L_E8D6:
        db 0x8B, 0xC8                           ; E8D6  (mov cx,ax)
        push dx                                 ; E8D8
        mov al,0x80                             ; E8D9
        add dx,byte +0x3                        ; E8DB
        out dx,al                               ; E8DE
        pop dx                                  ; E8DF
        db 0x8A, 0xC1                           ; E8E0  (mov al,cl)
        out dx,al                               ; E8E2
        inc dx                                  ; E8E3
        db 0x8A, 0xC5                           ; E8E4  (mov al,ch)
        out dx,al                               ; E8E6
        db 0x8A, 0xC3                           ; E8E7  (mov al,bl)
        and al,0x1f                             ; E8E9
        inc dx                                  ; E8EB
        inc dx                                  ; E8EC
        out dx,al                               ; E8ED
        dec dx                                  ; E8EE
        dec dx                                  ; E8EF
        db 0x32, 0xC0                           ; E8F0  (xor al,al)
        out dx,al                               ; E8F2
L_E8F3:
        mov ch,0x0                              ; E8F3
L_E8F5:
        add dx,byte +0x4                        ; E8F5
        in al,dx                                ; E8F8
        db 0x0A, 0xC5                           ; E8F9  (or al,ch)
        db 0x8A, 0xE0                           ; E8FB  (mov ah,al)
        db 0x0A, 0xED                           ; E8FD  (or ch,ch)
        db 0x8A, 0xC3                           ; E8FF  (mov al,bl)
        jnz L_E905                              ; E901
        inc dx                                  ; E903
        in al,dx                                ; E904
L_E905:
        pop bx                                  ; E905
L_E906:
        pop cx                                  ; E906
        pop di                                  ; E907
        pop si                                  ; E908
        pop dx                                  ; E909
        pop ds                                  ; E90A
        iret                                    ; E90B
wait_status_bits:
        db 0x33, 0xED                           ; E90C  (xor bp,bp)
L_E90E:
        in al,dx                                ; E90E
        db 0x8A, 0xE0                           ; E90F  (mov ah,al)
        db 0x22, 0xC7                           ; E911  (and al,bh)
        db 0x3A, 0xC7                           ; E913  (cmp al,bh)
        jz L_E921                               ; E915
        dec bp                                  ; E917
        jnz L_E90E                              ; E918
        dec ch                                  ; E91A
        jnz wait_status_bits                    ; E91C
        stc                                     ; E91E
        jmp short L_E922                        ; E91F
L_E921:
        clc                                     ; E921
L_E922:
        ret                                     ; E922

; =====================================================================
;  INT 15h - CASSETTE: not supported, returns AH=86h, CF=1
; =====================================================================
int15_cassette:
        mov ah,0x86                             ; E923
        stc                                     ; E925
        retf 0x2                                ; E926

; =====================================================================
;  INT 16h - KEYBOARD (functions 0-2)
; =====================================================================
int16_keyboard:
        sti                                     ; E929
        cmp ah,0x3                              ; E92A
        jnc L_E94D                              ; E92D
        push bx                                 ; E92F
        push si                                 ; E930
        push ds                                 ; E931
        call set_ds_bda                         ; E932
        mov bx,0x1a                             ; E935
        cmp ah,0x0                              ; E938
        ja L_E958                               ; E93B
L_E93D:
        sti                                     ; E93D
        db 0x0B, 0xC9                           ; E93E  (or cx,cx)
        call sub_FA44                           ; E940
        jz L_E93D                               ; E943
        call kbd_buf_next                       ; E945
        mov [bx],si                             ; E948
L_E94A:
        pop ds                                  ; E94A
        pop si                                  ; E94B
        pop bx                                  ; E94C
L_E94D:
        iret                                    ; E94D
L_E94E:
        call sub_FA44                           ; E94E
        sti                                     ; E951
        pop ds                                  ; E952
        pop si                                  ; E953
        pop bx                                  ; E954
        retf 0x2                                ; E955
L_E958:
        cmp ah,0x2                              ; E958
        jnz L_E94E                              ; E95B
        mov bx,0x17                             ; E95D
        mov al,[bx]                             ; E960
        jmp short L_E94A                        ; E962
kbd_buf_next:
        add si,byte +0x2                        ; E964
        cmp si,[0x82]                           ; E967
        jnz L_E971                              ; E96B
        mov si,[0x80]                           ; E96D
L_E971:
        ret                                     ; E971
shift_key_scans:
        db 0x36, 0x2A, 0x1D, 0x38, 0x46, 0x45, 0x3A, 0x52 ; E972
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; E97A
        db 0x00, 0x00, 0x00, 0x00, 0x00         ; E982
int09_entry:
        jmp near int09_keyboard                 ; E987
kbd_xlat_table:
        db 0x1B, 0x1B, 0x21, 0x31, 0x40, 0x32, 0x23, 0x33, 0x24, 0x34, 0x25, 0x35, 0x5E, 0x36, 0x26, 0x37 ; E98A
        db 0x2A, 0x38, 0x28, 0x39, 0x29, 0x30, 0x5F, 0x2D, 0x2B, 0x3D, 0x08, 0x08, 0x00, 0x09, 0x51, 0x71 ; E99A
        db 0x57, 0x77, 0x45, 0x65, 0x52, 0x72, 0x54, 0x74, 0x59, 0x79, 0x55, 0x75, 0x49, 0x69, 0x4F, 0x6F ; E9AA
        db 0x50, 0x70, 0x7B, 0x5B, 0x7D, 0x5D, 0x0D, 0x0D, 0xFF, 0xFF, 0x41, 0x61, 0x53, 0x73, 0x44, 0x64 ; E9BA
        db 0x46, 0x66, 0x47, 0x67, 0x48, 0x68, 0x4A, 0x6A, 0x4B, 0x6B, 0x4C, 0x6C, 0x3A, 0x3B, 0x22, 0x27 ; E9CA
        db 0x7E, 0x60, 0xFF, 0xFF, 0x7C, 0x5C, 0x5A, 0x7A, 0x58, 0x78, 0x43, 0x63, 0x56, 0x76, 0x42, 0x62 ; E9DA
        db 0x4E, 0x6E, 0x4D, 0x6D, 0x3C, 0x2C, 0x3E, 0x2E, 0x3F, 0x2F, 0xFF, 0xFF, 0x00, 0x2A, 0x1B, 0xFF ; E9EA
        db 0x00, 0xFF, 0xFF, 0xFF, 0x1E, 0xFF, 0xFF, 0xFF, 0xFF, 0x1F, 0xFF, 0x7F, 0xFF, 0x11, 0x17, 0x05 ; E9FA
        db 0x12, 0x14, 0x19, 0x15, 0x09, 0x0F, 0x10, 0x1B, 0x1D, 0x0A, 0xFF, 0x01, 0x13, 0x04, 0x06, 0x07 ; EA0A
        db 0x08, 0x0A, 0x0B, 0x0C, 0xFF, 0xFF, 0xFF, 0xFF, 0x1C, 0x1A, 0x18, 0x03, 0x16, 0x02, 0x0E, 0x0D ; EA1A
        db 0x07, 0x08, 0x09, 0xFF, 0x04, 0x05, 0x06, 0xFF, 0x01, 0x02, 0x03, 0x00, 0xFF, 0x77, 0x84, 0x73 ; EA2A
        db 0x74, 0x75, 0x76, 0xFF               ; EA3A

; =====================================================================
;  INT 09h - KEYBOARD IRQ.  Multitech's own code (not an IBM copy).
;  Extras: Ctrl+Alt+Keypad-plus writes to I/O port F0h; Ctrl+Alt+Del
;  sets 40:72=1234h and jumps to POST.  Buffer full -> click/beep.
; =====================================================================
int09_keyboard:
        sti                                     ; EA3E
        call save_regs                          ; EA3F
        push ax                                 ; EA42
        mov dx,0x60                             ; EA43
        in al,dx                                ; EA46
        push ax                                 ; EA47
        inc dx                                  ; EA48
        in al,dx                                ; EA49
        db 0x8A, 0xE0                           ; EA4A  (mov ah,al)
        or al,0x80                              ; EA4C
        out dx,al                               ; EA4E
        xchg ah,al                              ; EA4F
        out dx,al                               ; EA51
        pop ax                                  ; EA52
        cmp al,0xd5                             ; EA53
        jna L_EA59                              ; EA55
        jmp short L_EAD5                        ; EA57
L_EA59:
        call set_ds_bda                         ; EA59
        mov dl,[0x17]                           ; EA5C
        mov dh,[0x18]                           ; EA60
        cld                                     ; EA64
        test al,0x80                            ; EA65
        jz L_EAAE                               ; EA67
        and al,0x7f                             ; EA69
        call is_shift_key                       ; EA6B
        db 0x0A, 0xDB                           ; EA6E  (or bl,bl)
        jz L_EA7F                               ; EA70
        test bl,0xf                             ; EA72
        not bl                                  ; EA75
        jnz L_EA81                              ; EA77
        db 0x22, 0xF3                           ; EA79  (and dh,bl)
        mov [0x18],dh                           ; EA7B
L_EA7F:
        jmp short L_EAFF                        ; EA7F
L_EA81:
        db 0x22, 0xD3                           ; EA81  (and dl,bl)
        mov [0x17],dl                           ; EA83
        cmp al,0x38                             ; EA87
        jnz L_EAFF                              ; EA89
        db 0x33, 0xC0                           ; EA8B  (xor ax,ax)
        mov al,[0x19]                           ; EA8D
        db 0x0A, 0xC0                           ; EA90  (or al,al)
        jz L_EA7F                               ; EA92
        mov byte [0x19],0x0                     ; EA94
        cmp al,0x40                             ; EA99
        jna L_EAC4                              ; EA9B
        cmp al,0x5b                             ; EA9D
        jnc L_EAC4                              ; EA9F
        and al,0xdf                             ; EAA1
        mov ch,0x40                             ; EAA3
        call sub_ED1B                           ; EAA5
        jc L_EAC4                               ; EAA8
        xor al,0x20                             ; EAAA
        jmp short L_EAC4                        ; EAAC
L_EAAE:
        db 0x8A, 0xE0                           ; EAAE  (mov ah,al)
        call is_shift_key                       ; EAB0
        db 0x0A, 0xDB                           ; EAB3  (or bl,bl)
        jz L_EB20                               ; EAB5
        test bl,0xf                             ; EAB7
        jz L_EB08                               ; EABA
        db 0x0A, 0xD3                           ; EABC  (or dl,bl)
        mov [0x17],dl                           ; EABE
        jmp short L_EAFF                        ; EAC2
L_EAC4:
        mov si,[0x1c]                           ; EAC4
        db 0x8B, 0xFE                           ; EAC8  (mov di,si)
        call kbd_buf_next                       ; EACA
        cmp si,[0x1a]                           ; EACD
        jnz L_EAF9                              ; EAD1
        mov ch,0x80                             ; EAD3
L_EAD5:
        mov al,0x20                             ; EAD5
        out 0x20,al                             ; EAD7  8259 PIC ICW1/OCW
        mov bx,0x10                             ; EAD9
        in al,0x61                              ; EADC  8255 PPI port B (control)
        push ax                                 ; EADE
L_EADF:
        and al,0xfc                             ; EADF
        out 0x61,al                             ; EAE1  8255 PPI port B (control)
        mov cx,0x48                             ; EAE3
L_EAE6:
        loop L_EAE6                             ; EAE6
        or al,0x2                               ; EAE8
        out 0x61,al                             ; EAEA  8255 PPI port B (control)
        mov cx,0x48                             ; EAEC
L_EAEF:
        loop L_EAEF                             ; EAEF
        dec bx                                  ; EAF1
        jnz L_EADF                              ; EAF2
        pop ax                                  ; EAF4
        out 0x61,al                             ; EAF5  8255 PPI port B (control)
        jmp short L_EB03                        ; EAF7
L_EAF9:
        mov [di],ax                             ; EAF9
        mov [0x1c],si                           ; EAFB
L_EAFF:
        cli                                     ; EAFF
        call send_eoi                           ; EB00
L_EB03:
        pop ax                                  ; EB03
        call restore_regs                       ; EB04
        iret                                    ; EB07
L_EB08:
        test dl,0x4                             ; EB08
        jz L_EB27                               ; EB0B
L_EB0D:
        test dh,0x8                             ; EB0D
        jz L_EB56                               ; EB10
        test bl,0x20                            ; EB12
        jnz L_EAFF                              ; EB15
L_EB17:
        and dh,0xf7                             ; EB17
        mov [0x18],dh                           ; EB1A
        jmp short L_EAFF                        ; EB1E
L_EB20:
        test dh,0x8                             ; EB20
        jnz L_EB17                              ; EB23
        jmp short L_EB56                        ; EB25
L_EB27:
        test bl,0x80                            ; EB27
        jnz L_EB46                              ; EB2A
L_EB2C:
        test bl,dh                              ; EB2C
        jnz L_EAFF                              ; EB2E
        db 0x32, 0xD3                           ; EB30  (xor dl,bl)
        db 0x0A, 0xF3                           ; EB32  (or dh,bl)
        mov [0x17],dl                           ; EB34
        mov [0x18],dh                           ; EB38
        test bl,0x80                            ; EB3C
        jz L_EAFF                               ; EB3F
        db 0x32, 0xC0                           ; EB41  (xor al,al)
L_EB43:
        jmp near L_EAC4                         ; EB43
L_EB46:
        test dl,0x8                             ; EB46
        jnz L_EB0D                              ; EB49
        mov ch,0x20                             ; EB4B
        call sub_ED1B                           ; EB4D
        jnc L_EB2C                              ; EB50
        mov al,0x30                             ; EB52
        jmp short L_EB43                        ; EB54
L_EB56:
        cmp al,0x3a                             ; EB56
        ja L_EBA6                               ; EB58
        cmp al,0x37                             ; EB5A
        jna L_EB71                              ; EB5C
        cmp al,0x39                             ; EB5E
        jnz L_EAFF                              ; EB60
        sub al,0x19                             ; EB62
        jmp short L_EB43                        ; EB64
L_EB66:
        call sub_ED34                           ; EB66
        db 0x32, 0xC0                           ; EB69  (xor al,al)
        db 0x0A, 0xED                           ; EB6B  (or ch,ch)
        jz L_EBD0                               ; EB6D
        jmp short L_EAFF                        ; EB6F
L_EB71:
        test dl,0x8                             ; EB71
        jz L_EB8C                               ; EB74
        mov byte [0x19],0x0                     ; EB76
        cmp ah,0xd                              ; EB7B
        ja L_EB66                               ; EB7E
        cmp ah,0x1                              ; EB80
        jna L_EB66                              ; EB83
        db 0x32, 0xC0                           ; EB85  (xor al,al)
        add ah,0x76                             ; EB87
        jmp short L_EBD0                        ; EB8A
L_EB8C:
        test dl,0x4                             ; EB8C
        jnz L_EBDF                              ; EB8F
        test dl,0x3                             ; EB91
        jnz L_EBB6                              ; EB94
        call sub_ED34                           ; EB96
        db 0x0A, 0xED                           ; EB99  (or ch,ch)
        jnz L_EBCD                              ; EB9B
        test dl,0x40                            ; EB9D
        jnz L_EBCD                              ; EBA0
        inc ch                                  ; EBA2
        jmp short L_EBCD                        ; EBA4
L_EBA6:
        cmp al,0x54                             ; EBA6
        jnc L_EBB1                              ; EBA8
        cmp al,0x45                             ; EBAA
        jc L_EBF9                               ; EBAC
        jmp near kbd_keypad_keys                ; EBAE
L_EBB1:
        add ah,0x31                             ; EBB1
        jmp short L_EBF9                        ; EBB4
L_EBB6:
        cmp al,0x37                             ; EBB6
        jz L_EBD7                               ; EBB8
        cmp al,0xf                              ; EBBA
        jz L_EBD3                               ; EBBC
        call sub_ED34                           ; EBBE
        db 0x0A, 0xED                           ; EBC1  (or ch,ch)
        jnz L_EBCA                              ; EBC3
        test dl,0x40                            ; EBC5
        jz L_EBCD                               ; EBC8
L_EBCA:
        xor ch,0x1                              ; EBCA
L_EBCD:
        call sub_F715                           ; EBCD
L_EBD0:
        jmp near L_EAC4                         ; EBD0
L_EBD3:
        db 0x32, 0xC0                           ; EBD3  (xor al,al)
        jmp short L_EBD0                        ; EBD5
L_EBD7:
        call send_eoi                           ; EBD7
        int 0x5                                 ; EBDA
        jmp near L_EB03                         ; EBDC
L_EBDF:
        cmp al,0x32                             ; EBDF
        ja L_EBED                               ; EBE1
        dec al                                  ; EBE3
        mov bx,0xe9f8                           ; EBE5
        cs xlatb                                ; EBE8
        jmp near L_ECB5                         ; EBEA
L_EBED:
        cmp al,0x37                             ; EBED
        jz L_EBF4                               ; EBEF
        jmp near L_EC74                         ; EBF1
L_EBF4:
        add ax,0x3ac9                           ; EBF4
        jmp short L_EBD0                        ; EBF7
L_EBF9:
        db 0x32, 0xC0                           ; EBF9  (xor al,al)
        mov [0x19],al                           ; EBFB
        test dl,0xf                             ; EBFE
        jz L_EBD0                               ; EC01
        test dl,0x8                             ; EC03
        jz L_EC17                               ; EC06
        test ah,0x80                            ; EC08
        jz L_EC12                               ; EC0B
        add ah,0x6                              ; EC0D
        jmp short L_EBD0                        ; EC10
L_EC12:
        add ah,0x2d                             ; EC12
        jmp short L_EBD0                        ; EC15
L_EC17:
        test dl,0x4                             ; EC17
        jz L_EC2B                               ; EC1A
        test ah,0x80                            ; EC1C
        jz L_EC26                               ; EC1F
        add ah,0x4                              ; EC21
        jmp short L_EBD0                        ; EC24
L_EC26:
        add ah,0x23                             ; EC26
        jmp short L_EC9A                        ; EC29
L_EC2B:
        test ah,0x80                            ; EC2B
        jz L_EC5C                               ; EC2E
        add ah,0x2                              ; EC30
        jmp short L_EBD0                        ; EC33
kbd_keypad_keys:
        sub al,0x47                             ; EC35
        db 0x8A, 0xEA                           ; EC37  (mov ch,dl)
        and ch,0xc                              ; EC39
        sub ch,0xc                              ; EC3C
        jnz L_EC61                              ; EC3F
        cmp al,0x7                              ; EC41
        jnz L_EC48                              ; EC43
ctrl_alt_kp_plus:
        call port_f0_write                      ; EC45  Ctrl+Alt+Keypad-plus
L_EC48:
        cmp al,0xc                              ; EC48
        jnz L_EC61                              ; EC4A
ctrl_alt_del:
        mov word [0x72],0x1234                  ; EC4C  Ctrl+Alt+Del: warm boot
        jmp 0xf000:0xe05b                       ; EC52
        db 0x00, 0x00                           ; EC57
int13_entry:
        jmp near int13_diskette                 ; EC59
L_EC5C:
        add ah,0x19                             ; EC5C
        jmp short L_EC9A                        ; EC5F
L_EC61:
        test dl,0x8                             ; EC61
        jz L_EC87                               ; EC64
        mov bx,0xea2a                           ; EC66
        cs xlatb                                ; EC69
        cmp al,0xff                             ; EC6B
        jnz L_EC77                              ; EC6D
        mov byte [0x19],0x0                     ; EC6F
L_EC74:
        jmp near L_EAFF                         ; EC74
L_EC77:
        db 0x8A, 0xC8                           ; EC77  (mov cl,al)
        mov ah,0xa                              ; EC79
        mov al,[0x19]                           ; EC7B
        mul ah                                  ; EC7E
        db 0x02, 0xC1                           ; EC80  (add al,cl)
        mov [0x19],al                           ; EC82
L_EC85:
        jmp short L_EC74                        ; EC85
L_EC87:
        test dl,0x4                             ; EC87
        jnz L_ECEC                              ; EC8A
        cmp al,0x3                              ; EC8C
        jnz L_EC94                              ; EC8E
        mov al,0x2d                             ; EC90
        jmp short L_EC9A                        ; EC92
L_EC94:
        cmp al,0x7                              ; EC94
        jnz L_EC9D                              ; EC96
        mov al,0x2b                             ; EC98
L_EC9A:
        jmp near L_EAC4                         ; EC9A
L_EC9D:
        mov ch,0x20                             ; EC9D
        call sub_ED1B                           ; EC9F
        jc L_ECA8                               ; ECA2
        db 0x32, 0xC0                           ; ECA4  (xor al,al)
        jmp short L_EC9A                        ; ECA6
L_ECA8:
        cmp al,0xc                              ; ECA8
        jnz L_ECB0                              ; ECAA
        mov al,0x2e                             ; ECAC
        jmp short L_EC9A                        ; ECAE
L_ECB0:
        mov bx,0xea2a                           ; ECB0
        cs xlatb                                ; ECB3
L_ECB5:
        db 0x0A, 0xC0                           ; ECB5  (or al,al)
        js L_EC74                               ; ECB7
        test dl,0x4                             ; ECB9
        jnz L_EC9A                              ; ECBC
        add al,0x30                             ; ECBE
        jmp short L_EC9A                        ; ECC0
L_ECC2:
        mov byte [0x71],0x80                    ; ECC2
        int 0x1b                                ; ECC7
        db 0x33, 0xC0                           ; ECC9  (xor ax,ax)
        mov si,[0x1a]                           ; ECCB
        mov [0x1c],si                           ; ECCF
        jmp short L_EC9A                        ; ECD3
L_ECD5:
        add dh,0x8                              ; ECD5
        mov [0x18],dh                           ; ECD8
        call send_eoi                           ; ECDC
        call sub_F068                           ; ECDF
L_ECE2:
        test byte [0x18],0x8                    ; ECE2
        jnz L_ECE2                              ; ECE7
        jmp near L_EB03                         ; ECE9
L_ECEC:
        cmp al,0xfe                             ; ECEC
        jz L_ECD5                               ; ECEE
        cmp al,0xff                             ; ECF0
        jz L_ECC2                               ; ECF2
        shr al,1                                ; ECF4
        jc L_EC85                               ; ECF6
        mov bx,0xea37                           ; ECF8
        cs xlatb                                ; ECFB
        db 0x8A, 0xE0                           ; ECFD  (mov ah,al)
        db 0x32, 0xC0                           ; ECFF  (xor al,al)
        jmp short L_ECB5                        ; ED01
send_eoi:
        mov al,0x20                             ; ED03
        out 0x20,al                             ; ED05  8259 PIC ICW1/OCW
        ret                                     ; ED07
is_shift_key:
        mov bl,0x1                              ; ED08
        mov si,0xe972                           ; ED0A
        mov cx,0x8                              ; ED0D
L_ED10:
        cmp al,[cs:si]                          ; ED10
        jz L_ED1A                               ; ED13
        shl bl,1                                ; ED15
        inc si                                  ; ED17
        loop L_ED10                             ; ED18
L_ED1A:
        ret                                     ; ED1A
sub_ED1B:
        clc                                     ; ED1B
        db 0x8A, 0xCA                           ; ED1C  (mov cl,dl)
        db 0x0A, 0xC9                           ; ED1E  (or cl,cl)
        jz L_ED33                               ; ED20
        db 0x22, 0xCD                           ; ED22  (and cl,ch)
        jz L_ED2D                               ; ED24
        test dl,0x3                             ; ED26
        jnz L_ED33                              ; ED29
        jmp short L_ED32                        ; ED2B
L_ED2D:
        test dl,0x3                             ; ED2D
        jz L_ED33                               ; ED30
L_ED32:
        stc                                     ; ED32
L_ED33:
        ret                                     ; ED33
sub_ED34:
        mov bx,0xe98a                           ; ED34
        db 0x32, 0xED                           ; ED37  (xor ch,ch)
        cmp al,0xf                              ; ED39
        jna L_ED51                              ; ED3B
        cmp al,0x32                             ; ED3D
        ja L_ED51                               ; ED3F
        cmp al,0x1a                             ; ED41
        jc L_ED53                               ; ED43
        cmp al,0x2c                             ; ED45
        jnc L_ED53                              ; ED47
        cmp al,0x1e                             ; ED49
        jc L_ED51                               ; ED4B
        cmp al,0x26                             ; ED4D
        jna L_ED53                              ; ED4F
L_ED51:
        inc ch                                  ; ED51
L_ED53:
        ret                                     ; ED53

; =====================================================================
;  INT 10h - VIDEO, functions 00-0Fh dispatched through the table at ED98
; =====================================================================
int10_video:
        sti                                     ; ED54
        cmp ah,0xf                              ; ED55
        jna L_ED5B                              ; ED58
        iret                                    ; ED5A
L_ED5B:
        call save_regs                          ; ED5B
        db 0x8B, 0xF8                           ; ED5E  (mov di,ax)
        mov si,0xed98                           ; ED60
        call set_ds_bda                         ; ED63
        push cx                                 ; ED66
        mov cl,[0x49]                           ; ED67
        mov ch,0x1                              ; ED6B
        shl ch,cl                               ; ED6D
        mov [0xca],ch                           ; ED6F
        db 0x32, 0xC9                           ; ED73  (xor cl,cl)
        mov ch,0xb8                             ; ED75
        mov bp,[0x10]                           ; ED77
        and bp,0x30                             ; ED7B
        cmp bp,byte +0x30                       ; ED7F
        jnz L_ED86                              ; ED82
        mov ch,0xb0                             ; ED84
L_ED86:
        push cx                                 ; ED86
        pop es                                  ; ED87
        mov cl,0x7                              ; ED88
        shr ax,cl                               ; ED8A
        and ax,0x1fe                            ; ED8C
        db 0x8B, 0xE8                           ; ED8F  (mov bp,ax)
        db 0x8B, 0xC7                           ; ED91  (mov ax,di)
        pop cx                                  ; ED93
        cld                                     ; ED94
        jmp [cs:bp+si]                          ; ED95
int10_table:
        dw 0xF0DB                               ; ED98
        dw 0xF30D                               ; ED9A
        dw 0xF34C                               ; ED9C
        dw 0xF337                               ; ED9E
        dw 0xF413                               ; EDA0
        dw 0xF2E5                               ; EDA2
        dw 0xF243                               ; EDA4
        dw 0xF24E                               ; EDA6
        dw 0xF371                               ; EDA8
        dw 0xEFD2                               ; EDAA
        dw 0xEFDC                               ; EDAC
        dw 0xF4C3                               ; EDAE
        dw 0xF39F                               ; EDB0
        dw 0xF39C                               ; EDB2
        dw 0xF1C4                               ; EDB4
        dw 0xF4EE                               ; EDB6

; ---------------------------------------------------------------------
;  INT 1Dh video parameter table (CRTC values).  NOTE: IBM keeps it at F0A4.
; ---------------------------------------------------------------------
video_params:
        db 0x38, 0x28, 0x2D, 0x0A, 0x1F, 0x06, 0x19, 0x1C, 0x02, 0x07, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00 ; EDB8
        db 0x71, 0x50, 0x5A, 0x0A, 0x1F, 0x06, 0x19, 0x1C, 0x02, 0x07, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00 ; EDC8
        db 0x38, 0x28, 0x2D, 0x0A, 0x7F, 0x06, 0x64, 0x70, 0x02, 0x01, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00 ; EDD8
        db 0x61, 0x50, 0x52, 0x0F, 0x19, 0x06, 0x19, 0x19, 0x02, 0x0D, 0x0B, 0x0C, 0x00, 0x00, 0x00, 0x00 ; EDE8
        db 0x2C, 0x28, 0x2D, 0x29, 0x2A, 0x2E, 0x1E, 0x29 ; EDF8
L_EE00:
        db 0x33, 0xED                           ; EE00  (xor bp,bp)
        db 0x8B, 0xF5                           ; EE02  (mov si,bp)
        popf                                    ; EE04
        pushf                                   ; EE05
        jc L_EE0C                               ; EE06
        inc bp                                  ; EE08
        mov si,0xf0                             ; EE09
L_EE0C:
        test byte [0xca],0x40                   ; EE0C
        jnz L_EE17                              ; EE11
        db 0x02, 0xD2                           ; EE13  (add dl,dl)
        db 0x03, 0xFD                           ; EE15  (add di,bp)
L_EE17:
        db 0x03, 0xFE                           ; EE17  (add di,si)
        mov bp,0x50                             ; EE19
        popf                                    ; EE1C
        jc L_EE21                               ; EE1D
        neg bp                                  ; EE1F
L_EE21:
        mov ax,es                               ; EE21
        mov ds,ax                               ; EE23
        db 0x32, 0xED                           ; EE25  (xor ch,ch)
        pop ax                                  ; EE27
        xchg bh,bl                              ; EE28
        push bx                                 ; EE2A
        db 0x02, 0xC0                           ; EE2B  (add al,al)
        db 0x02, 0xC0                           ; EE2D  (add al,al)
        push ax                                 ; EE2F
        db 0x8B, 0xDD                           ; EE30  (mov bx,bp)
        imul bl                                 ; EE32
        push di                                 ; EE34
        pop si                                  ; EE35
        db 0x03, 0xF0                           ; EE36  (add si,ax)
        pop ax                                  ; EE38
        db 0x02, 0xF6                           ; EE39  (add dh,dh)
        db 0x02, 0xF6                           ; EE3B  (add dh,dh)
        test al,0xff                            ; EE3D
        jz L_EE51                               ; EE3F
        db 0x2A, 0xF0                           ; EE41  (sub dh,al)
        xchg al,dh                              ; EE43
        jz L_EE51                               ; EE45
L_EE47:
        stc                                     ; EE47
        call sub_F0A9                           ; EE48
        db 0x03, 0xF5                           ; EE4B  (add si,bp)
        dec al                                  ; EE4D
        jg L_EE47                               ; EE4F
L_EE51:
        pop ax                                  ; EE51
L_EE52:
        clc                                     ; EE52
        call sub_F0A9                           ; EE53
        dec dh                                  ; EE56
        jg L_EE52                               ; EE58
        jmp near L_F1C0                         ; EE5A
L_EE5D:
        push si                                 ; EE5D
        db 0x8A, 0xEB                           ; EE5E  (mov ch,bl)
        db 0x8B, 0xD8                           ; EE60  (mov bx,ax)
        cmp bl,0x0                              ; EE62
        jl L_EE6E                               ; EE65
        mov si,0xfa6e                           ; EE67
        mov bp,cs                               ; EE6A
        jmp short L_EE7E                        ; EE6C
L_EE6E:
        and bl,0x7f                             ; EE6E
        db 0x33, 0xD2                           ; EE71  (xor dx,dx)
        push dx                                 ; EE73
        pop ds                                  ; EE74
        lds si,[0x7c]                           ; EE75
        mov bp,ds                               ; EE79
        call set_ds_bda                         ; EE7B
L_EE7E:
        db 0x32, 0xE4                           ; EE7E  (xor ah,ah)
        mov ax,[0x50]                           ; EE80
        call sub_F02D                           ; EE83
        mov cl,0x3                              ; EE86
        db 0x32, 0xFF                           ; EE88  (xor bh,bh)
        shl bx,cl                               ; EE8A
        db 0x8B, 0xF8                           ; EE8C  (mov di,ax)
        db 0x03, 0xF3                           ; EE8E  (add si,bx)
        test byte [0xca],0x40                   ; EE90
        mov ds,bp                               ; EE95
        mov bp,0x2000                           ; EE97
        db 0x8A, 0xDD                           ; EE9A  (mov bl,ch)
        mov cx,0x4                              ; EE9C
        db 0x8B, 0xD7                           ; EE9F  (mov dx,di)
        jnz L_EEDF                              ; EEA1
        db 0x8A, 0xEB                           ; EEA3  (mov ch,bl)
        db 0x33, 0xC0                           ; EEA5  (xor ax,ax)
        shr bl,1                                ; EEA7
        jnc L_EEAE                              ; EEA9
        or ax,0x5555                            ; EEAB
L_EEAE:
        shr bl,1                                ; EEAE
        jnc L_EEB5                              ; EEB0
        or ax,0xaaaa                            ; EEB2
L_EEB5:
        db 0x8B, 0xD8                           ; EEB5  (mov bx,ax)
L_EEB7:
        call sub_EF1B                           ; EEB7
        db 0x03, 0xFD                           ; EEBA  (add di,bp)
        inc si                                  ; EEBC
        call sub_EF1B                           ; EEBD
        db 0x2B, 0xFD                           ; EEC0  (sub di,bp)
        dec si                                  ; EEC2
        call sub_EF10                           ; EEC3
        dec cl                                  ; EEC6
        jnz L_EEB7                              ; EEC8
        pop cx                                  ; EECA
        dec cx                                  ; EECB
        ja L_EED1                               ; EECC
        jmp near L_F1C0                         ; EECE
L_EED1:
        call sub_EF0A                           ; EED1
        add di,byte +0x1                        ; EED4
        call sub_EF17                           ; EED7
        push cx                                 ; EEDA
        mov cl,0x4                              ; EEDB
        jmp short L_EEB7                        ; EEDD
L_EEDF:
        mov ax,[si]                             ; EEDF
        cmp bl,0x0                              ; EEE1
        jnl L_EEEC                              ; EEE4
        xor al,[es:di]                          ; EEE6
        xor ah,[es:bp+di]                       ; EEE9
L_EEEC:
        mov [es:di],al                          ; EEEC
        mov [es:bp+di],ah                       ; EEEF
        call sub_EF10                           ; EEF2
        loop L_EEDF                             ; EEF5
        pop cx                                  ; EEF7
        dec cx                                  ; EEF8
        ja L_EEFE                               ; EEF9
        jmp near L_F1C0                         ; EEFB
L_EEFE:
        push cx                                 ; EEFE
        mov cx,0x4                              ; EEFF
        call sub_EF0A                           ; EF02
        call sub_EF17                           ; EF05
        jmp short L_EEDF                        ; EF08
sub_EF0A:
        sub si,byte +0x8                        ; EF0A
        db 0x8B, 0xFA                           ; EF0D  (mov di,dx)
        ret                                     ; EF0F
sub_EF10:
        add si,byte +0x2                        ; EF10
        add di,byte +0x50                       ; EF13
        ret                                     ; EF16
sub_EF17:
        inc di                                  ; EF17
        db 0x8B, 0xD7                           ; EF18  (mov dx,di)
        ret                                     ; EF1A
sub_EF1B:
        push bp                                 ; EF1B
        push bx                                 ; EF1C
        mov al,[si]                             ; EF1D
        mov bx,0x3                              ; EF1F
        db 0x33, 0xED                           ; EF22  (xor bp,bp)
L_EF24:
        test al,0xff                            ; EF24
        jz L_EF34                               ; EF26
        shr al,1                                ; EF28
        jnc L_EF2E                              ; EF2A
        db 0x0B, 0xEB                           ; EF2C  (or bp,bx)
L_EF2E:
        shl bx,1                                ; EF2E
        shl bx,1                                ; EF30
        jmp short L_EF24                        ; EF32
L_EF34:
        db 0x8B, 0xC5                           ; EF34  (mov ax,bp)
        pop bx                                  ; EF36
        pop bp                                  ; EF37
        db 0x23, 0xC3                           ; EF38  (and ax,bx)
        xchg ah,al                              ; EF3A
        cmp ch,0x0                              ; EF3C
        jnl L_EF44                              ; EF3F
        xor ax,[es:di]                          ; EF41
L_EF44:
        mov [es:di],ax                          ; EF44
        ret                                     ; EF47
L_EF48:
        mov ax,[0x50]                           ; EF48
        call sub_F02D                           ; EF4B
        mov dx,es                               ; EF4E
        mov bx,0x30                             ; EF50
        mov es,bx                               ; EF53
        db 0x33, 0xF6                           ; EF55  (xor si,si)
        mov cx,0x4                              ; EF57
        mov bp,0x2000                           ; EF5A
        test byte [0xca],0x40                   ; EF5D
        mov ds,dx                               ; EF62
        db 0x8B, 0xF8                           ; EF64  (mov di,ax)
        jnz L_EF77                              ; EF66
L_EF68:
        db 0x33, 0xED                           ; EF68  (xor bp,bp)
        call sub_FA1E                           ; EF6A
        call sub_FA1E                           ; EF6D
        add di,byte +0x50                       ; EF70
        loop L_EF68                             ; EF73
        jmp short L_EF84                        ; EF75
L_EF77:
        mov al,[di]                             ; EF77
        mov ah,[ds:bp+di]                       ; EF79
        mov [es:si],ax                          ; EF7C
        call sub_EF10                           ; EF7F
        loop L_EF77                             ; EF82
L_EF84:
        mov bx,cs                               ; EF84
        mov ds,bx                               ; EF86
        mov di,0xfa6e                           ; EF88
        sub di,byte +0x8                        ; EF8B
        mov al,0x0                              ; EF8E
        db 0x33, 0xF6                           ; EF90  (xor si,si)
L_EF92:
        add di,byte +0x8                        ; EF92
L_EF95:
        db 0x33, 0xDB                           ; EF95  (xor bx,bx)
        mov ah,0x8                              ; EF97
L_EF99:
        mov dl,[es:bx+si]                       ; EF99
        cmp dl,[bx+di]                          ; EF9C
        jnz L_EFA8                              ; EF9E
        inc bx                                  ; EFA0
        dec ah                                  ; EFA1
        jnz L_EF99                              ; EFA3
L_EFA5:
        jmp near L_F1C0                         ; EFA5
L_EFA8:
        inc al                                  ; EFA8
        cmp al,0x0                              ; EFAA
        jz L_EFA5                               ; EFAC
        jg L_EF92                               ; EFAE
        test al,0x7f                            ; EFB0
        jnz L_EF92                              ; EFB2
        mov ds,si                               ; EFB4
        lds di,[0x7c]                           ; EFB6
        mov dx,ds                               ; EFBA
        db 0x0B, 0xD7                           ; EFBC  (or dx,di)
        jnz L_EF95                              ; EFBE
        db 0x32, 0xC0                           ; EFC0  (xor al,al)
        jmp short L_EFA5                        ; EFC2
        db 0x00, 0x00, 0x00                     ; EFC4

; ---------------------------------------------------------------------
;  INT 1Eh diskette parameter table (same address as IBM)
; ---------------------------------------------------------------------
diskette_params:
        db 0xDF, 0x02, 0x24, 0x02, 0x08, 0x2A, 0xFF, 0x50, 0xF6, 0x0F, 0x03 ; EFC7
        jcxz L_F020                             ; EFD2
        db 0x8A, 0xE3                           ; EFD4  (mov ah,bl)
        push cx                                 ; EFD6
        mov cx,0x101                            ; EFD7
        jmp short L_EFE2                        ; EFDA
        jcxz L_F020                             ; EFDC
        push cx                                 ; EFDE
        mov cx,0x1                              ; EFDF
L_EFE2:
        pop si                                  ; EFE2
        test byte [0xca],0x70                   ; EFE3
        jz L_EFED                               ; EFE8
        jmp near L_EE5D                         ; EFEA
L_EFED:
        call sub_F077                           ; EFED
        db 0x8B, 0xFB                           ; EFF0  (mov di,bx)
        db 0x8A, 0xD8                           ; EFF2  (mov bl,al)
        call sub_F023                           ; EFF4
L_EFF7:
        db 0x22, 0xE9                           ; EFF7  (and ch,cl)
        jz L_F00B                               ; EFF9
L_EFFB:
        in al,dx                                ; EFFB
        db 0x22, 0xC1                           ; EFFC  (and al,cl)
        jnz L_EFFB                              ; EFFE
        cli                                     ; F000
L_F001:
        in al,dx                                ; F001
        db 0x22, 0xC1                           ; F002  (and al,cl)
        jz L_F001                               ; F004
        db 0x8A, 0xC3                           ; F006  (mov al,bl)
        stosw                                   ; F008
        jmp short L_F01C                        ; F009
L_F00B:
        in al,dx                                ; F00B
        db 0x22, 0xC1                           ; F00C  (and al,cl)
        jnz L_F00B                              ; F00E
        cli                                     ; F010
L_F011:
        in al,dx                                ; F011
        db 0x22, 0xC1                           ; F012  (and al,cl)
        jz L_F011                               ; F014
        db 0x8A, 0xC3                           ; F016  (mov al,bl)
        stosb                                   ; F018
        add di,byte +0x1                        ; F019
L_F01C:
        sti                                     ; F01C
        dec si                                  ; F01D
        jg L_EFF7                               ; F01E
L_F020:
        jmp near L_F1C0                         ; F020
sub_F023:
        mov dh,0x3                              ; F023
        mov dl,[0x63]                           ; F025
        add dl,0x6                              ; F029
        ret                                     ; F02C
sub_F02D:
        push cx                                 ; F02D
        db 0x33, 0xC9                           ; F02E  (xor cx,cx)
        test byte [0xca],0x70                   ; F030
        jz L_F048                               ; F035
        shl ah,1                                ; F037
        test byte [0xca],0x40                   ; F039
        jz L_F046                               ; F03E
        shl ah,1                                ; F040
        db 0x8A, 0xC8                           ; F042  (mov cl,al)
        jmp short L_F04E                        ; F044
L_F046:
        shl ah,1                                ; F046
L_F048:
        shl ah,1                                ; F048
        db 0x8A, 0xC8                           ; F04A  (mov cl,al)
        shl cx,1                                ; F04C
L_F04E:
        add cx,[0x4e]                           ; F04E
        xchg ah,al                              ; F052
        mul byte [0x4a]                         ; F054
        db 0x03, 0xC1                           ; F058  (add ax,cx)
        pop cx                                  ; F05A
        ret                                     ; F05B
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; F05C

; INT 10h at the IBM-compatible address F065
int10_entry:
        jmp near int10_thunk                    ; F065
sub_F068:
        test byte [0xca],0xc                    ; F068
        jz L_F076                               ; F06D
        mov al,[0x65]                           ; F06F
        mov dx,0x3d8                            ; F072
        out dx,al                               ; F075
L_F076:
        ret                                     ; F076
sub_F077:
        push ax                                 ; F077
        call sub_F363                           ; F078
        mov ax,[di]                             ; F07B
        call sub_F02D                           ; F07D
        cmp bh,[0x62]                           ; F080
        jnz L_F08A                              ; F084
        db 0x33, 0xDB                           ; F086  (xor bx,bx)
        jmp short L_F091                        ; F088
L_F08A:
        sub ax,[0x4e]                           ; F08A
        call sub_F095                           ; F08E
L_F091:
        db 0x03, 0xD8                           ; F091  (add bx,ax)
        pop ax                                  ; F093
        ret                                     ; F094
sub_F095:
        push cx                                 ; F095
        db 0x33, 0xC9                           ; F096  (xor cx,cx)
        cmp bh,0x0                              ; F098
        jz L_F0A5                               ; F09B
L_F09D:
        add cx,[0x4c]                           ; F09D
        dec bh                                  ; F0A1
        jnz L_F09D                              ; F0A3
L_F0A5:
        db 0x8B, 0xD9                           ; F0A5  (mov bx,cx)
        pop cx                                  ; F0A7
        ret                                     ; F0A8
sub_F0A9:
        db 0x8A, 0xCA                           ; F0A9  (mov cl,dl)
        push bx                                 ; F0AB
        push bp                                 ; F0AC
        mov bx,0x2000                           ; F0AD
        db 0x8B, 0xEF                           ; F0B0  (mov bp,di)
        jc L_F0C1                               ; F0B2
L_F0B4:
        rep stosb                               ; F0B4
        jc L_F0D4                               ; F0B6
        db 0x8B, 0xFD                           ; F0B8  (mov di,bp)
        db 0x03, 0xFB                           ; F0BA  (add di,bx)
        db 0x8A, 0xCA                           ; F0BC  (mov cl,dl)
        stc                                     ; F0BE
        jmp short L_F0B4                        ; F0BF
L_F0C1:
        push si                                 ; F0C1
        push si                                 ; F0C2
L_F0C3:
        rep movsb                               ; F0C3
        jnc L_F0D3                              ; F0C5
        pop si                                  ; F0C7
        db 0x8B, 0xFD                           ; F0C8  (mov di,bp)
        db 0x03, 0xFB                           ; F0CA  (add di,bx)
        db 0x03, 0xF3                           ; F0CC  (add si,bx)
        db 0x8A, 0xCA                           ; F0CE  (mov cl,dl)
        clc                                     ; F0D0
        jmp short L_F0C3                        ; F0D1
L_F0D3:
        pop si                                  ; F0D3
L_F0D4:
        db 0x8B, 0xFD                           ; F0D4  (mov di,bp)
        pop bp                                  ; F0D6
        pop bx                                  ; F0D7
        db 0x03, 0xFD                           ; F0D8  (add di,bp)
        ret                                     ; F0DA
        mov di,0x67                             ; F0DB
        mov cx,0x1e                             ; F0DE
L_F0E1:
        dec di                                  ; F0E1
        mov byte [di],0x0                       ; F0E2
        loop L_F0E1                             ; F0E5
        mov word [di+0x17],0x607                ; F0E7
        mov dx,[0x10]                           ; F0EC
        and dx,0x30                             ; F0F0
        cmp dx,byte +0x30                       ; F0F4
        jnz L_F0FE                              ; F0F7
        mov dl,0xb4                             ; F0F9
        jmp short L_F100                        ; F0FB
        db 0x90                                 ; F0FD
L_F0FE:
        mov dl,0xd4                             ; F0FE
L_F100:
        mov dh,0x3                              ; F100
        test dl,0x20                            ; F102
        jz L_F10C                               ; F105
        mov ax,0x107                            ; F107
        jmp short L_F115                        ; F10A
L_F10C:
        db 0x32, 0xE4                           ; F10C  (xor ah,ah)
        cmp al,0x6                              ; F10E
        jna L_F115                              ; F110
        jmp near L_F1C0                         ; F112
L_F115:
        mov [di+0x1a],dx                        ; F115
        mov [di],al                             ; F118
        xchg ah,al                              ; F11A
        push dx                                 ; F11C
        add dx,byte +0x4                        ; F11D
        out dx,al                               ; F120
        mov ch,0x1                              ; F121
        db 0x8A, 0xCC                           ; F123  (mov cl,ah)
        shl ch,cl                               ; F125
        mov [0xca],ch                           ; F127
        mov dx,0x28                             ; F12B
        test ch,0x33                            ; F12E
        jnz L_F136                              ; F131
        add dl,0x28                             ; F133
L_F136:
        mov [di+0x1],dx                         ; F136
        db 0x33, 0xDB                           ; F139  (xor bx,bx)
        mov cx,0x2000                           ; F13B
        mov si,0x720                            ; F13E
        mov dx,0x800                            ; F141
        test byte [0xca],0x3                    ; F144
        jnz L_F172                              ; F149
        add bx,byte +0x10                       ; F14B
        shl dx,1                                ; F14E
        test byte [0xca],0xc                    ; F150
        jnz L_F172                              ; F155
        add bx,byte +0x10                       ; F157
        shl dx,1                                ; F15A
        shl dx,1                                ; F15C
        mov si,0x0                              ; F15E
        test byte [0xca],0x70                   ; F161
        jnz L_F172                              ; F166
        add bx,byte +0x10                       ; F168
        sub cx,0x1800                           ; F16B
        mov si,0x720                            ; F16F
L_F172:
        mov [di+0x3],dx                         ; F172
        pop dx                                  ; F175
        push ds                                 ; F176
        mov bp,0x0                              ; F177
        push bp                                 ; F17A
        pop ds                                  ; F17B
L_F17C:
        mov [es:bp+0x0],si                      ; F17C
        add bp,byte +0x2                        ; F180
        loop L_F17C                             ; F183
        lds bp,[0x74]                           ; F185
        db 0x03, 0xEB                           ; F189  (add bp,bx)
        mov cx,0x10                             ; F18B
        db 0x32, 0xC0                           ; F18E  (xor al,al)
L_F190:
        mov bl,[ds:bp+0x0]                      ; F190
        call sub_F304                           ; F194
        inc bp                                  ; F197
        inc al                                  ; F198
        loop L_F190                             ; F19A
        pop ds                                  ; F19C
        xchg ah,al                              ; F19D
        db 0x32, 0xE4                           ; F19F  (xor ah,ah)
        add dx,byte +0x4                        ; F1A1
        mov si,0xedf8                           ; F1A4
        db 0x03, 0xF0                           ; F1A7  (add si,ax)
        mov al,[cs:si]                          ; F1A9
        out dx,al                               ; F1AC
        mov [di+0x1c],al                        ; F1AD
        inc dx                                  ; F1B0
        mov al,0x1f                             ; F1B1
        test byte [0xca],0x40                   ; F1B3
        jnz L_F1BC                              ; F1B8
        add al,0x11                             ; F1BA
L_F1BC:
        out dx,al                               ; F1BC
        mov [di+0x1d],al                        ; F1BD
L_F1C0:
        call restore_regs                       ; F1C0
        iret                                    ; F1C3
        mov bh,[0x62]                           ; F1C4
        db 0x8B, 0xE8                           ; F1C8  (mov bp,ax)
        call sub_F363                           ; F1CA
        mov dx,[di]                             ; F1CD
        mov cl,[0x4a]                           ; F1CF
        mov ch,0x18                             ; F1D3
        db 0x8B, 0xF1                           ; F1D5  (mov si,cx)
        mov ah,0xa                              ; F1D7
        cmp al,0xd                              ; F1D9
        jnz L_F1E1                              ; F1DB
        db 0x32, 0xD2                           ; F1DD  (xor dl,dl)
        jmp short L_F1FD                        ; F1DF
L_F1E1:
        cmp al,0xa                              ; F1E1
        jnz L_F1EE                              ; F1E3
L_F1E5:
        db 0x3A, 0xF5                           ; F1E5  (cmp dh,ch)
        jz L_F222                               ; F1E7
        add dh,0x1                              ; F1E9
        jmp short L_F1FD                        ; F1EC
L_F1EE:
        mov cx,0x2                              ; F1EE
        cmp al,0x8                              ; F1F1
        jnz L_F204                              ; F1F3
        test dl,0xff                            ; F1F5
        jz L_F1FD                               ; F1F8
        sub dl,0x1                              ; F1FA
L_F1FD:
        call sub_F352                           ; F1FD
L_F200:
        db 0x8B, 0xC5                           ; F200  (mov ax,bp)
        jmp short L_F1C0                        ; F202
L_F204:
        cmp al,0x7                              ; F204
        jnz L_F212                              ; F206
        mov cx,0x0                              ; F208
        mov bl,0x3                              ; F20B
        call beep                               ; F20D
        jmp short L_F200                        ; F210
L_F212:
        dec cx                                  ; F212
        int 0x10                                ; F213
        db 0x8B, 0xCE                           ; F215  (mov cx,si)
        add dl,0x1                              ; F217
        db 0x3A, 0xD1                           ; F21A  (cmp dl,cl)
        jc L_F1FD                               ; F21C
        db 0x32, 0xD2                           ; F21E  (xor dl,dl)
        jmp short L_F1E5                        ; F220
L_F222:
        call sub_F352                           ; F222
        db 0x32, 0xFF                           ; F225  (xor bh,bh)
        test byte [0xca],0x8f                   ; F227
        jz L_F235                               ; F22C
        push ds                                 ; F22E
        call sub_F381                           ; F22F
        pop ds                                  ; F232
        db 0x8A, 0xFC                           ; F233  (mov bh,ah)
L_F235:
        sub si,byte +0x1                        ; F235
        mov ax,0x601                            ; F238
        db 0x8B, 0xD6                           ; F23B  (mov dx,si)
        db 0x33, 0xC9                           ; F23D  (xor cx,cx)
        int 0x10                                ; F23F
        jmp short L_F200                        ; F241
        stc                                     ; F243
        push ax                                 ; F244
        db 0x8B, 0xC1                           ; F245  (mov ax,cx)
        jmp short L_F253                        ; F247
L_F249:
        popf                                    ; F249
        pop ax                                  ; F24A
        jmp near L_F1C0                         ; F24B
        std                                     ; F24E
        clc                                     ; F24F
        push ax                                 ; F250
        db 0x8B, 0xC2                           ; F251  (mov ax,dx)
L_F253:
        pushf                                   ; F253
        db 0x2A, 0xF5                           ; F254  (sub dh,ch)
        jc L_F249                               ; F256
        db 0x2A, 0xD1                           ; F258  (sub dl,cl)
        jna L_F249                              ; F25A
        add dx,0x101                            ; F25C
        call sub_F02D                           ; F260
        push ax                                 ; F263
        pop di                                  ; F264
        test byte [0xca],0x70                   ; F265
        jz L_F26F                               ; F26A
        jmp near L_EE00                         ; F26C
L_F26F:
        push ax                                 ; F26F
        pop si                                  ; F270
        popf                                    ; F271
        pop ax                                  ; F272
        mov bl,0x20                             ; F273
        db 0x8B, 0xEB                           ; F275  (mov bp,bx)
        push ax                                 ; F277
        pushf                                   ; F278
        shl al,1                                ; F279
        mov bx,[0x4a]                           ; F27B
        mul bl                                  ; F27F
        shl bx,1                                ; F281
        popf                                    ; F283
        jc L_F28A                               ; F284
        neg ax                                  ; F286
        neg bx                                  ; F288
L_F28A:
        db 0x03, 0xF0                           ; F28A  (add si,ax)
        call sub_F2CD                           ; F28C
        pop ax                                  ; F28F
        push ds                                 ; F290
        mov cx,es                               ; F291
        mov ds,cx                               ; F293
        db 0x2A, 0xED                           ; F295  (sub ch,ch)
        test al,0xff                            ; F297
        jz L_F2AB                               ; F299
        db 0x2A, 0xF0                           ; F29B  (sub dh,al)
        xchg al,dh                              ; F29D
        jz L_F2AB                               ; F29F
L_F2A1:
        stc                                     ; F2A1
        call sub_F2BC                           ; F2A2
        db 0x03, 0xF3                           ; F2A5  (add si,bx)
        dec al                                  ; F2A7
        jg L_F2A1                               ; F2A9
L_F2AB:
        db 0x8B, 0xC5                           ; F2AB  (mov ax,bp)
L_F2AD:
        clc                                     ; F2AD
        call sub_F2BC                           ; F2AE
        dec dh                                  ; F2B1
        jg L_F2AD                               ; F2B3
        pop ds                                  ; F2B5
        call sub_F068                           ; F2B6
        jmp near L_F1C0                         ; F2B9
sub_F2BC:
        db 0x8A, 0xCA                           ; F2BC  (mov cl,dl)
        push di                                 ; F2BE
        push si                                 ; F2BF
        jc L_F2C6                               ; F2C0
        rep stosw                               ; F2C2
        jmp short L_F2C8                        ; F2C4
L_F2C6:
        rep movsw                               ; F2C6
L_F2C8:
        pop si                                  ; F2C8
        pop di                                  ; F2C9
        db 0x03, 0xFB                           ; F2CA  (add di,bx)
        ret                                     ; F2CC
sub_F2CD:
        test byte [0xca],0xc                    ; F2CD
        jz L_F2E4                               ; F2D2
        push dx                                 ; F2D4
        mov dx,0x3da                            ; F2D5
L_F2D8:
        in al,dx                                ; F2D8
        and al,0x8                              ; F2D9
        jz L_F2D8                               ; F2DB
        sub dl,0x2                              ; F2DD
        mov al,0x21                             ; F2E0
        out dx,al                               ; F2E2
        pop dx                                  ; F2E3
L_F2E4:
        ret                                     ; F2E4
        db 0x8A, 0xF8                           ; F2E5  (mov bh,al)
        call sub_F363                           ; F2E7
        mov [0x62],bh                           ; F2EA
        call sub_F095                           ; F2EE
        mov [0x4e],bx                           ; F2F1
        shr bx,1                                ; F2F5
        mov al,0xc                              ; F2F7
        call sub_F324                           ; F2F9
        mov ax,[di]                             ; F2FC
        call sub_F31B                           ; F2FE
        jmp near L_F1C0                         ; F301
sub_F304:
        push ax                                 ; F304
        out dx,al                               ; F305
        inc dx                                  ; F306
        db 0x8A, 0xC3                           ; F307  (mov al,bl)
        out dx,al                               ; F309
        dec dx                                  ; F30A
        pop ax                                  ; F30B
        ret                                     ; F30C
        db 0x8B, 0xD9                           ; F30D  (mov bx,cx)
        mov [0x60],bx                           ; F30F
        mov al,0xa                              ; F313
        call sub_F324                           ; F315
        jmp near L_F1C0                         ; F318
sub_F31B:
        call sub_F02D                           ; F31B
        db 0x8B, 0xD8                           ; F31E  (mov bx,ax)
        sar bx,1                                ; F320
        mov al,0xe                              ; F322
sub_F324:
        push dx                                 ; F324
        mov dx,[0x63]                           ; F325
        xchg bh,bl                              ; F329
        call sub_F304                           ; F32B
        inc al                                  ; F32E
        xchg bh,bl                              ; F330
        call sub_F304                           ; F332
        pop dx                                  ; F335
        ret                                     ; F336
        call sub_F363                           ; F337
        mov ax,[di]                             ; F33A
        mov cx,[0x60]                           ; F33C
        db 0x8B, 0xFC                           ; F340  (mov di,sp)
        mov [ss:di+0xc],cx                      ; F342
        call restore_regs                       ; F346
        db 0x8B, 0xD0                           ; F349  (mov dx,ax)
        iret                                    ; F34B
        call sub_F352                           ; F34C
        jmp near L_F1C0                         ; F34F
sub_F352:
        call sub_F363                           ; F352
        mov [di],dx                             ; F355
        cmp [0x62],bh                           ; F357
        jnz L_F362                              ; F35B
        db 0x8B, 0xC2                           ; F35D  (mov ax,dx)
        call sub_F31B                           ; F35F
L_F362:
        ret                                     ; F362
sub_F363:
        push bx                                 ; F363
        xchg bh,bl                              ; F364
        db 0x32, 0xFF                           ; F366  (xor bh,bh)
        shl bx,1                                ; F368
        mov di,0x50                             ; F36A
        db 0x03, 0xFB                           ; F36D  (add di,bx)
        pop bx                                  ; F36F
        ret                                     ; F370
        test byte [0xca],0x70                   ; F371
        jz L_F37B                               ; F376
        jmp near L_EF48                         ; F378
L_F37B:
        call sub_F381                           ; F37B
        jmp near L_F1C0                         ; F37E
sub_F381:
        call sub_F077                           ; F381
        call sub_F023                           ; F384
        mov cx,es                               ; F387
        mov ds,cx                               ; F389
        mov cl,0x1                              ; F38B
        cli                                     ; F38D
L_F38E:
        in al,dx                                ; F38E
        db 0x22, 0xC1                           ; F38F  (and al,cl)
        jnz L_F38E                              ; F391
L_F393:
        in al,dx                                ; F393
        db 0x22, 0xC1                           ; F394  (and al,cl)
        jz L_F393                               ; F396
        mov ax,[bx]                             ; F398
        sti                                     ; F39A
        ret                                     ; F39B
        stc                                     ; F39C
        jmp short L_F3A0                        ; F39D
        clc                                     ; F39F
L_F3A0:
        pushf                                   ; F3A0
        db 0x8B, 0xE8                           ; F3A1  (mov bp,ax)
        db 0x8A, 0xC2                           ; F3A3  (mov al,dl)
        shr al,1                                ; F3A5
        mov ah,0x50                             ; F3A7
        mul ah                                  ; F3A9
        db 0x8B, 0xF8                           ; F3AB  (mov di,ax)
        ror dl,1                                ; F3AD
        jnc L_F3B5                              ; F3AF
        add di,0x2000                           ; F3B1
L_F3B5:
        db 0x8B, 0xD1                           ; F3B5  (mov dx,cx)
        mov bx,0x302                            ; F3B7
        and cl,0x7                              ; F3BA
        shr dx,1                                ; F3BD
        shr dx,1                                ; F3BF
        test byte [0xca],0x40                   ; F3C1
        jz L_F3D0                               ; F3C6
        shr dx,1                                ; F3C8
        sub bx,0x201                            ; F3CA
        jmp short L_F3D3                        ; F3CE
L_F3D0:
        and cl,0xf3                             ; F3D0
L_F3D3:
        db 0x03, 0xFA                           ; F3D3  (add di,dx)
        test byte [0xca],0x40                   ; F3D5
        jnz L_F3E0                              ; F3DA
        shl cl,1                                ; F3DC
        inc cl                                  ; F3DE
L_F3E0:
        xor cl,0x7                              ; F3E0
        shl bh,cl                               ; F3E3
        popf                                    ; F3E5
        jnc L_F3F2                              ; F3E6
        mov al,[es:di]                          ; F3E8
        db 0x22, 0xC7                           ; F3EB  (and al,bh)
        shr al,cl                               ; F3ED
        jmp near L_F1C0                         ; F3EF
L_F3F2:
        db 0x8B, 0xC5                           ; F3F2  (mov ax,bp)
        shl al,cl                               ; F3F4
        db 0x22, 0xC7                           ; F3F6  (and al,bh)
        db 0x8A, 0xC8                           ; F3F8  (mov cl,al)
        mov bl,[es:di]                          ; F3FA
        db 0x8B, 0xC5                           ; F3FD  (mov ax,bp)
        test al,0x80                            ; F3FF
        jz L_F407                               ; F401
        db 0x32, 0xCB                           ; F403  (xor cl,bl)
        jmp short L_F40D                        ; F405
L_F407:
        not bh                                  ; F407
        db 0x22, 0xDF                           ; F409  (and bl,bh)
        db 0x0A, 0xCB                           ; F40B  (or cl,bl)
L_F40D:
        mov [es:di],cl                          ; F40D
        jmp near L_F1C0                         ; F410
        mov dx,0x3da                            ; F413
        db 0x8B, 0xF2                           ; F416  (mov si,dx)
        db 0x32, 0xE4                           ; F418  (xor ah,ah)
        in al,dx                                ; F41A
        and al,0x6                              ; F41B
        jnz L_F422                              ; F41D
        jmp near L_F4AB                         ; F41F
L_F422:
        cmp al,0x2                              ; F422
        jz L_F429                               ; F424
        jmp near L_F4AB                         ; F426
L_F429:
        mov cx,0x1011                           ; F429
        mov bl,0xd5                             ; F42C
        sub dx,byte +0x6                        ; F42E
        db 0x8A, 0xC5                           ; F431  (mov al,ch)
        out dx,al                               ; F433
        xchg dl,bl                              ; F434
        in al,dx                                ; F436
        db 0x8A, 0xF8                           ; F437  (mov bh,al)
        xchg dl,bl                              ; F439
        db 0x8A, 0xC1                           ; F43B  (mov al,cl)
        out dx,al                               ; F43D
        xchg dl,bl                              ; F43E
        in al,dx                                ; F440
        db 0x8A, 0xD8                           ; F441  (mov bl,al)
        mov dx,[0x4e]                           ; F443
        add dx,byte +0x2                        ; F447
        test byte [0xca],0x73                   ; F44A
        jnz L_F454                              ; F44F
        add dx,byte +0x2                        ; F451
L_F454:
        db 0x2B, 0xDA                           ; F454  (sub bx,dx)
        jns L_F45A                              ; F456
        db 0x33, 0xDB                           ; F458  (xor bx,bx)
L_F45A:
        mov cx,0x2803                           ; F45A
        xchg ax,bx                              ; F45D
        test byte [0xca],0x70                   ; F45E
        jz L_F48E                               ; F463
        div ch                                  ; F465
        db 0x8A, 0xE8                           ; F467  (mov ch,al)
        db 0x02, 0xED                           ; F469  (add ch,ch)
        db 0x8A, 0xD4                           ; F46B  (mov dl,ah)
        db 0x8A, 0xF0                           ; F46D  (mov dh,al)
        xchg al,ah                              ; F46F
        db 0x32, 0xE4                           ; F471  (xor ah,ah)
        shl ax,cl                               ; F473
        push ax                                 ; F475
        db 0x8A, 0xC6                           ; F476  (mov al,dh)
        inc cl                                  ; F478
        div cl                                  ; F47A
        db 0x8A, 0xF0                           ; F47C  (mov dh,al)
        pop ax                                  ; F47E
        test byte [0xca],0x40                   ; F47F
        jz L_F48A                               ; F484
        shl dl,1                                ; F486
        shl ax,1                                ; F488
L_F48A:
        db 0x8B, 0xD8                           ; F48A  (mov bx,ax)
        jmp short L_F4A9                        ; F48C
L_F48E:
        test byte [0xca],0x3                    ; F48E
        jnz L_F497                              ; F493
        shl ch,1                                ; F495
L_F497:
        div ch                                  ; F497
        db 0x8B, 0xD0                           ; F499  (mov dx,ax)
        xchg dh,dl                              ; F49B
        xchg ah,al                              ; F49D
        db 0x32, 0xE4                           ; F49F  (xor ah,ah)
        shl ax,cl                               ; F4A1
        db 0x8B, 0xD8                           ; F4A3  (mov bx,ax)
        db 0x8A, 0xEE                           ; F4A5  (mov ch,dh)
        shl ch,cl                               ; F4A7
L_F4A9:
        mov ah,0x1                              ; F4A9
L_F4AB:
        xchg si,dx                              ; F4AB
        inc dx                                  ; F4AD
        out dx,al                               ; F4AE
        xchg si,dx                              ; F4AF
        db 0x8B, 0xFC                           ; F4B1  (mov di,sp)
        mov [ss:di+0xe],bx                      ; F4B3
        mov [ss:di+0xc],cx                      ; F4B7
        mov [ss:di+0xa],dx                      ; F4BB
        call restore_regs                       ; F4BF
        iret                                    ; F4C2
        mov cl,[0x66]                           ; F4C3
        call sub_F023                           ; F4C7
        dec dx                                  ; F4CA
        db 0x22, 0xFF                           ; F4CB  (and bh,bh)
        jz L_F4DC                               ; F4CD
        and cl,0x1f                             ; F4CF
        and bl,0x1                              ; F4D2
        jz L_F4E4                               ; F4D5
        or cl,0x20                              ; F4D7
        jmp short L_F4E4                        ; F4DA
L_F4DC:
        and bl,0xdf                             ; F4DC
        and cl,0x20                             ; F4DF
        db 0x0A, 0xCB                           ; F4E2  (or cl,bl)
L_F4E4:
        db 0x8A, 0xC1                           ; F4E4  (mov al,cl)
        out dx,al                               ; F4E6
        mov [0x66],cl                           ; F4E7
        jmp near L_F1C0                         ; F4EB
        call restore_regs                       ; F4EE
        push ds                                 ; F4F1
        call set_ds_bda                         ; F4F2
        mov al,[0x49]                           ; F4F5
        mov ah,[0x4a]                           ; F4F8
        mov bh,[0x62]                           ; F4FC
        pop ds                                  ; F500
        iret                                    ; F501

; =====================================================================
;  INT 17h - PRINTER (functions 0-2).  NOTE: not at the IBM address EFD2.
; =====================================================================
int17_printer:
        sti                                     ; F502
        call save_regs                          ; F503
        push ax                                 ; F506
        call set_ds_bda                         ; F507
        db 0x8B, 0xFA                           ; F50A  (mov di,dx)
        db 0x8A, 0x9D, 0x78, 0x00               ; F50C  (mov bl,[di+0x78])
        shl di,1                                ; F510
        db 0x8B, 0x95, 0x08, 0x00               ; F512  (mov dx,[di+0x8])
        cmp dx,byte +0x0                        ; F516
        jz L_F538                               ; F519
        cmp ah,0x0                              ; F51B
        jnz L_F525                              ; F51E
        call sub_F55B                           ; F520
        jmp short L_F538                        ; F523
L_F525:
        cmp ah,0x1                              ; F525
        jnz L_F52F                              ; F528
        call sub_F53F                           ; F52A
        jmp short L_F538                        ; F52D
L_F52F:
        cmp ah,0x2                              ; F52F
        jnz L_F538                              ; F532
        inc dx                                  ; F534
        call sub_F551                           ; F535
L_F538:
        pop ax                                  ; F538
        db 0x8A, 0xE5                           ; F539  (mov ah,ch)
        call restore_regs                       ; F53B
        iret                                    ; F53E
sub_F53F:
        add dx,byte +0x2                        ; F53F
        mov al,0x8                              ; F542
        out dx,al                               ; F544
L_F545:
        loop L_F545                             ; F545
L_F547:
        loop L_F547                             ; F547
        mov al,0xc                              ; F549
        out dx,al                               ; F54B
        dec dx                                  ; F54C
        call sub_F551                           ; F54D
        ret                                     ; F550
sub_F551:
        in al,dx                                ; F551
        db 0x8A, 0xE8                           ; F552  (mov ch,al)
        and ch,0xf8                             ; F554
        xor ch,0x48                             ; F557
        ret                                     ; F55A
sub_F55B:
        out dx,al                               ; F55B
        inc dx                                  ; F55C
L_F55D:
        db 0x33, 0xC9                           ; F55D  (xor cx,cx)
L_F55F:
        push cx                                 ; F55F
        in al,dx                                ; F560
        db 0x8A, 0xE8                           ; F561  (mov ch,al)
        cmp al,0x80                             ; F563
        pop cx                                  ; F565
        jnc L_F573                              ; F566
        loop L_F55F                             ; F568
        dec bl                                  ; F56A
        jnz L_F55D                              ; F56C
        call sub_F577                           ; F56E
        jmp short L_F576                        ; F571
L_F573:
        call sub_F581                           ; F573
L_F576:
        ret                                     ; F576
sub_F577:
        and ch,0xf9                             ; F577
        or ch,0x1                               ; F57A
        xor ch,0x48                             ; F57D
        ret                                     ; F580
sub_F581:
        inc dx                                  ; F581
        mov al,0xd                              ; F582
        out dx,al                               ; F584
        mov al,0xc                              ; F585
        out dx,al                               ; F587
        dec dx                                  ; F588
        call sub_F551                           ; F589
        ret                                     ; F58C

; =====================================================================
;  INT 13h - DISKETTE.  Uses private scratch bytes at 40:C3-40:CF and
;  builds 765 FDC commands on the stack.
; =====================================================================
int13_diskette:
        sti                                     ; F58D
        call save_regs                          ; F58E
        mov di,0x40                             ; F591
        mov ds,di                               ; F594
        mov [0xc3],dl                           ; F596
        mov [0xc4],dh                           ; F59A
        mov [0xc5],ch                           ; F59E
        mov [0xc6],cl                           ; F5A2
        mov [0xc7],al                           ; F5A6
        or byte [0x3f],0xc                      ; F5A9
        db 0x2A, 0xC0                           ; F5AE  (sub al,al)
        mov dx,0x3f2                            ; F5B0
        cmp ah,0x0                              ; F5B3
        jnz L_F601                              ; F5B6
        cli                                     ; F5B8
        add al,[0x3f]                           ; F5B9
        and al,0xfb                             ; F5BD
        out dx,al                               ; F5BF
        and byte [0x3e],0x0                     ; F5C0
        and byte [0x41],0x0                     ; F5C5
        add al,0x4                              ; F5CA
        mov byte [0xcf],0x2                     ; F5CC
        out dx,al                               ; F5D1
        sti                                     ; F5D2
        call sub_F90C                           ; F5D3
        jnc L_F5DB                              ; F5D6
        jmp near L_F6AE                         ; F5D8
L_F5DB:
        cmp byte [0x42],0xc0                    ; F5DB
        jnz L_F5F9                              ; F5E0
        call get_diskette_params                ; F5E2
        mov al,[es:di+0x1]                      ; F5E5
        push ax                                 ; F5E9
        mov al,[es:di]                          ; F5EA
        push ax                                 ; F5ED
        mov ax,0x3                              ; F5EE
        push ax                                 ; F5F1
        push ax                                 ; F5F2
        call sub_F80D                           ; F5F3
        jmp near L_F6AE                         ; F5F6
L_F5F9:
        add byte [0x41],0x20                    ; F5F9
        jmp near L_F6AE                         ; F5FE
L_F601:
        cmp ah,0x1                              ; F601
        jnz L_F60D                              ; F604
        add al,[0x41]                           ; F606
        jmp near L_F6AE                         ; F60A
L_F60D:
        db 0x8A, 0xC4                           ; F60D  (mov al,ah)
        mov byte [0xcd],0x46                    ; F60F
        mov ah,0x66                             ; F614
        and byte [0x41],0x0                     ; F616
        test byte [0xc3],0xfc                   ; F61B
        jnz L_F651                              ; F620
        cmp al,0x2                              ; F622
        jnz L_F629                              ; F624
        jmp short L_F659                        ; F626
        db 0x90                                 ; F628
L_F629:
        cmp al,0x4                              ; F629
        jnz L_F635                              ; F62B
        sub byte [0xcd],0x4                     ; F62D
        jmp short L_F659                        ; F632
        db 0x90                                 ; F634
L_F635:
        cmp al,0x3                              ; F635
        jnz L_F643                              ; F637
        add byte [0xcd],0x4                     ; F639
        sub ah,0x21                             ; F63E
        jmp short L_F659                        ; F641
L_F643:
        cmp al,0x5                              ; F643
        jnz L_F651                              ; F645
        add byte [0xcd],0x4                     ; F647
        sub ah,0x19                             ; F64C
        jmp short L_F659                        ; F64F
L_F651:
        add byte [0x41],0x1                     ; F651
        jmp short L_F6AE                        ; F656
        db 0x90                                 ; F658
L_F659:
        push ax                                 ; F659
        and byte [0x40],0x0                     ; F65A
        mov cl,[0xc3]                           ; F65F
        mov al,0x10                             ; F663
        shl al,cl                               ; F665
        or al,[0xc3]                            ; F667
        or al,0xc                               ; F66B
        out dx,al                               ; F66D
        cmp al,[0x3f]                           ; F66E
        jz L_F698                               ; F672
        mov [0x3f],al                           ; F674
        cmp ah,0x45                             ; F677
        jz L_F681                               ; F67A
        cmp ah,0x4d                             ; F67C
        jnz L_F698                              ; F67F
L_F681:
        push es                                 ; F681
        call get_diskette_params                ; F682
        mov ah,[es:di+0xa]                      ; F685
        pop es                                  ; F689
        db 0x22, 0xE4                           ; F68A  (and ah,ah)
        jz L_F698                               ; F68C
L_F68E:
        call sub_F9B9                           ; F68E
        cmp byte [0xce],0xf5                    ; F691
        jnz L_F68E                              ; F696
L_F698:
        call sub_F8B4                           ; F698
        jc L_F6A8                               ; F69B
        mov dl,[0xc3]                           ; F69D
        mov ch,[0xc5]                           ; F6A1
        call sub_F825                           ; F6A5
L_F6A8:
        pop ax                                  ; F6A8
        jc L_F6AE                               ; F6A9
        call sub_F6DC                           ; F6AB
L_F6AE:
        call get_diskette_params                ; F6AE
        mov ah,[es:di+0x2]                      ; F6B1
        mov [0x40],ah                           ; F6B5
        and byte [0xcf],0x0                     ; F6B9
        mov ah,[0x41]                           ; F6BE
        and byte [0x3f],0xf3                    ; F6C2
        test ah,0xff                            ; F6C7
        jz L_F6D8                               ; F6CA
        mov byte [0x3e],0x0                     ; F6CC
        stc                                     ; F6D1
L_F6D2:
        call restore_regs                       ; F6D2
        retf 0x2                                ; F6D5
L_F6D8:
        db 0x32, 0xC0                           ; F6D8  (xor al,al)
        jmp short L_F6D2                        ; F6DA
sub_F6DC:
        mov byte [0xcf],0x7                     ; F6DC
        db 0x8A, 0xC4                           ; F6E1  (mov al,ah)
        mov cl,[0xc3]                           ; F6E3
        test byte [0xc4],0x1                    ; F6E7
        jz L_F6F1                               ; F6EC
        or cl,0x4                               ; F6EE
L_F6F1:
        sub ah,0x4d                             ; F6F1
        call get_diskette_params                ; F6F4
        jz L_F6FC                               ; F6F7
        jmp near L_F787                         ; F6F9
L_F6FC:
        mov bl,[es:di+0x8]                      ; F6FC
        push bx                                 ; F700
        jmp short L_F770                        ; F701
rom_checksum_8k:
        push ds                                 ; F703
        mov ds,dx                               ; F704
        mov cx,0x2000                           ; F706
        db 0x33, 0xC0                           ; F709  (xor ax,ax)
L_F70B:
        lodsb                                   ; F70B
        db 0x02, 0xE0                           ; F70C  (add ah,al)
        loop L_F70B                             ; F70E
        cmp ah,0x0                              ; F710
        pop ds                                  ; F713
        ret                                     ; F714
sub_F715:
        dec al                                  ; F715
        shl al,1                                ; F717
        db 0x02, 0xC5                           ; F719  (add al,ch)
        cs xlatb                                ; F71B
        ret                                     ; F71D
port_f0_write:
        push ax                                 ; F71E
        mov al,0x0                              ; F71F  write 00 to port F0h (purpose unknown - speed switch?)
        out 0xf0,al                             ; F721
        pop ax                                  ; F723
        ret                                     ; F724
msg_no_system:
        db 0x0D, 0x0A, '* No-System *', 0x0D, 0x0A, '*Insert system disk and' ; F725
        db ' strike any key', 0x0D, 0x0A, 0x00  ; F74D
        db 0x00                                 ; F75F
        db 0x00                                 ; F760
        db 0x00                                 ; F761
        db 0x00                                 ; F762
        db 0x00                                 ; F763
        db 0x00                                 ; F764
        db 0x00                                 ; F765
        db 0x00                                 ; F766
        db 0x00                                 ; F767
columbia_signature:
        db 'Columbia'                           ; F768
L_F770:
        mov bl,[es:di+0x7]                      ; F770
        push bx                                 ; F774
        mov bl,[es:di+0x4]                      ; F775
        push bx                                 ; F779
        mov bl,[es:di+0x3]                      ; F77A
        push bx                                 ; F77E
        push cx                                 ; F77F
        push ax                                 ; F780
        mov ax,0x6                              ; F781
        push ax                                 ; F784
        jmp short L_F7B9                        ; F785
L_F787:
        mov bl,[0xc6]                           ; F787
        push bx                                 ; F78B
        mov bl,[0xc4]                           ; F78C
        push bx                                 ; F790
        mov bl,[0xc5]                           ; F791
        push bx                                 ; F795
        push cx                                 ; F796
        push ax                                 ; F797
        mov bx,0x5                              ; F798
        push bx                                 ; F79B
        call sub_F80D                           ; F79C
        jc L_F7C7                               ; F79F
        mov bl,[es:di+0x6]                      ; F7A1
        push bx                                 ; F7A5
        mov bl,[es:di+0x5]                      ; F7A6
        push bx                                 ; F7AA
        mov bl,[es:di+0x4]                      ; F7AB
        push bx                                 ; F7AF
        mov bl,[es:di+0x3]                      ; F7B0
        push bx                                 ; F7B4
        mov bx,0x4                              ; F7B5
        push bx                                 ; F7B8
L_F7B9:
        call sub_F80D                           ; F7B9
        jc L_F7C7                               ; F7BC
        call sub_F90C                           ; F7BE
        jnc L_F7C4                              ; F7C1
        ret                                     ; F7C3
L_F7C4:
        call sub_F7C8                           ; F7C4
L_F7C7:
        ret                                     ; F7C7
sub_F7C8:
        mov ah,[0x42]                           ; F7C8
        test ah,0xc0                            ; F7CC
        jz L_F7F0                               ; F7CF
        and ah,0x80                             ; F7D1
        jnz L_F7EA                              ; F7D4
        mov al,[0x43]                           ; F7D6
        mov si,0xf9d2                           ; F7D9
        mov cl,0x8                              ; F7DC
L_F7DE:
        shl al,1                                ; F7DE
        jc L_F7E5                               ; F7E0
        inc si                                  ; F7E2
        loop L_F7DE                             ; F7E3
L_F7E5:
        mov ah,[cs:si]                          ; F7E5
        jmp short L_F7EC                        ; F7E8
L_F7EA:
        mov ah,0x20                             ; F7EA
L_F7EC:
        add [0x41],ah                           ; F7EC
L_F7F0:
        call get_diskette_params                ; F7F0
        mov al,[es:di+0x4]                      ; F7F3
        add al,0x1                              ; F7F7
        mov si,0x47                             ; F7F9
        mov ah,[si-0x2]                         ; F7FC
        not ah                                  ; F7FF
        test [0xc5],ah                          ; F801
        jnz L_F808                              ; F805
        lodsb                                   ; F807
L_F808:
        sub al,[0xc6]                           ; F808
        ret                                     ; F80C
sub_F80D:
        pop bx                                  ; F80D
        pop cx                                  ; F80E
L_F80F:
        mov ah,0x80                             ; F80F
        call sub_F994                           ; F811
        jc L_F81F                               ; F814
        pop ax                                  ; F816
        mov dx,0x3f5                            ; F817
        out dx,al                               ; F81A
        loop L_F80F                             ; F81B
        jmp short L_F823                        ; F81D
L_F81F:
        pop ax                                  ; F81F
        loop L_F81F                             ; F820
        stc                                     ; F822
L_F823:
        push bx                                 ; F823
        ret                                     ; F824
sub_F825:
        push cx                                 ; F825
        mov [0xc3],dl                           ; F826
        mov [0xc5],ch                           ; F82A
        mov byte [0xcf],0x2                     ; F82E
        mov al,0x1                              ; F833
        db 0x8A, 0xCA                           ; F835  (mov cl,dl)
        shl al,cl                               ; F837
        test [0x3e],al                          ; F839
        jnz L_F86D                              ; F83D
        or [0x3e],al                            ; F83F
        mov bl,[0xc3]                           ; F843
        push bx                                 ; F847
        mov bx,0x7                              ; F848
        push bx                                 ; F84B
        mov bx,0x2                              ; F84C
        push bx                                 ; F84F
        call sub_F80D                           ; F850
        jc L_F892                               ; F853
        call sub_F90C                           ; F855
        jc L_F8B2                               ; F858
        mov cx,0x750                            ; F85A
L_F85D:
        loop L_F85D                             ; F85D
        and byte [0x3e],0x3f                    ; F85F
        mov al,[0x42]                           ; F864
        and al,0x60                             ; F867
        sub al,0x20                             ; F869
        jnz L_F892                              ; F86B
L_F86D:
        mov bl,[0xc5]                           ; F86D
        push bx                                 ; F871
        mov bl,[0xc3]                           ; F872
        push bx                                 ; F876
        mov bx,0xf                              ; F877
        push bx                                 ; F87A
        mov bx,0x3                              ; F87B
        push bx                                 ; F87E
        call sub_F80D                           ; F87F
        jc L_F892                               ; F882
        call sub_F90C                           ; F884
        jc L_F8B2                               ; F887
        mov al,[0x42]                           ; F889
        and al,0x60                             ; F88C
        sub al,0x20                             ; F88E
        jz L_F89A                               ; F890
L_F892:
        or byte [0x41],0x40                     ; F892
        stc                                     ; F897
        jmp short L_F8B2                        ; F898
L_F89A:
        push es                                 ; F89A
        call get_diskette_params                ; F89B
        mov cl,0x1f                             ; F89E
        pop es                                  ; F8A0
        mov ch,0x0                              ; F8A1
        cmp cl,0x0                              ; F8A3
        jz L_F8B2                               ; F8A6
L_F8A8:
        mov bx,0xe4                             ; F8A8
L_F8AB:
        dec bx                                  ; F8AB
        nop                                     ; F8AC
        jnz L_F8AB                              ; F8AD
        loop L_F8A8                             ; F8AF
        clc                                     ; F8B1
L_F8B2:
        pop cx                                  ; F8B2
        ret                                     ; F8B3
sub_F8B4:
        mov al,[0xcd]                           ; F8B4
        out 0xb,al                              ; F8B7  DMA mode register
        push es                                 ; F8B9
        pop ax                                  ; F8BA
        db 0x8A, 0xF4                           ; F8BB  (mov dh,ah)
        mov cx,0x4                              ; F8BD
L_F8C0:
        shr dh,1                                ; F8C0
        shl ax,1                                ; F8C2
        loop L_F8C0                             ; F8C4
        db 0x03, 0xC3                           ; F8C6  (add ax,bx)
        jnc L_F8CD                              ; F8C8
        add dh,0x1                              ; F8CA
L_F8CD:
        xchg al,dh                              ; F8CD
        out 0x81,al                             ; F8CF  DMA page reg ch2
        xchg al,dh                              ; F8D1
        out 0xc,al                              ; F8D3  DMA clear flip-flop
        out 0x4,al                              ; F8D5
        xchg al,ah                              ; F8D7
        out 0x4,al                              ; F8D9
        xchg al,ah                              ; F8DB
        db 0x32, 0xF6                           ; F8DD  (xor dh,dh)
        mov dl,[0xc7]                           ; F8DF
        call get_diskette_params                ; F8E3
        mov cl,[es:di+0x3]                      ; F8E6
        add cl,0x7                              ; F8EA
        shl dx,cl                               ; F8ED
        sub dx,byte +0x1                        ; F8EF
        db 0x03, 0xC2                           ; F8F2  (add ax,dx)
        xchg ax,dx                              ; F8F4
        jc L_F903                               ; F8F5
        out 0x5,al                              ; F8F7
        xchg al,ah                              ; F8F9
        out 0x5,al                              ; F8FB
        mov al,0x2                              ; F8FD
        out 0xa,al                              ; F8FF  DMA mask register
        jmp short L_F90B                        ; F901
L_F903:
        add byte [0x41],0x9                     ; F903
        db 0x2A, 0xC0                           ; F908  (sub al,al)
        stc                                     ; F90A
L_F90B:
        ret                                     ; F90B
sub_F90C:
        push ax                                 ; F90C
        push cx                                 ; F90D
        mov ax,0x4                              ; F90E
        db 0x33, 0xC9                           ; F911  (xor cx,cx)
L_F913:
        test byte [0x3e],0xc0                   ; F913
        jnz L_F92D                              ; F918
        loop L_F913                             ; F91A
        dec ax                                  ; F91C
        jnz L_F913                              ; F91D
        add byte [0x41],0x80                    ; F91F
        and byte [0x3e],0x3f                    ; F924
        stc                                     ; F929
L_F92A:
        pop cx                                  ; F92A
        pop ax                                  ; F92B
        ret                                     ; F92C
L_F92D:
        and byte [0x3e],0x3f                    ; F92D
        jmp short L_F92A                        ; F932

; =====================================================================
;  INT 0Eh - DISKETTE IRQ: read FDC result bytes into 40:42
; =====================================================================
int0e_diskette_irq:
        sti                                     ; F934
        call save_regs                          ; F935
        push ax                                 ; F938
        mov di,0x40                             ; F939
        mov ds,di                               ; F93C
        test byte [0xcf],0xff                   ; F93E
        jz L_F98D                               ; F943
        cmp byte [0xcf],0x2                     ; F945
        jnz L_F957                              ; F94A
        mov bx,0x8                              ; F94C
        push bx                                 ; F94F
        mov bx,0x1                              ; F950
        push bx                                 ; F953
        call sub_F80D                           ; F954
L_F957:
        cld                                     ; F957
        mov di,0x42                             ; F958
        mov ch,0x0                              ; F95B
        mov cl,[0xcf]                           ; F95D
L_F961:
        mov ah,0xc0                             ; F961
        call sub_F994                           ; F963
        jc L_F985                               ; F966
        mov dx,0x3f5                            ; F968
        in al,dx                                ; F96B
        mov [di],al                             ; F96C
        add di,byte +0x1                        ; F96E
        loop L_F961                             ; F971
        mov cx,0x20                             ; F973
        mov dx,0x3f4                            ; F976
L_F979:
        in al,dx                                ; F979
        and al,0x10                             ; F97A
        jz L_F98D                               ; F97C
        loop L_F979                             ; F97E
        add byte [0x41],0x20                    ; F980
L_F985:
        call send_eoi                           ; F985
        pop ax                                  ; F988
        call restore_regs                       ; F989
        iret                                    ; F98C
L_F98D:
        or byte [0x3e],0xc0                     ; F98D
        jmp short L_F985                        ; F992
sub_F994:
        push bx                                 ; F994
        mov dx,0x3f4                            ; F995
        db 0x33, 0xDB                           ; F998  (xor bx,bx)
L_F99A:
        in al,dx                                ; F99A
        and al,0xc0                             ; F99B
        db 0x3A, 0xC4                           ; F99D  (cmp al,ah)
        jz L_F9B7                               ; F99F
        sub bx,byte +0x1                        ; F9A1
        jnz L_F99A                              ; F9A4
        test al,0x80                            ; F9A6
        jz L_F9B1                               ; F9A8
        add byte [0x41],0x20                    ; F9AA
        jmp short L_F9B6                        ; F9AF
L_F9B1:
        add byte [0x41],0x80                    ; F9B1
L_F9B6:
        stc                                     ; F9B6
L_F9B7:
        pop bx                                  ; F9B7
        ret                                     ; F9B8
sub_F9B9:
        push bx                                 ; F9B9
        mov bl,[0x40]                           ; F9BA
        mov [0xce],bl                           ; F9BE
        pop bx                                  ; F9C2
        ret                                     ; F9C3
get_diskette_params:
        push ds                                 ; F9C4
        push dx                                 ; F9C5
        mov dx,0x0                              ; F9C6
        mov ds,dx                               ; F9C9
        les di,[0x78]                           ; F9CB
        pop dx                                  ; F9CF
        pop ds                                  ; F9D0
        ret                                     ; F9D1
        db 0x04, 0x00, 0x10, 0x08, 0x00, 0x04, 0x03, 0x02 ; F9D2

; =====================================================================
;  INT 08h - TIMER: tick count at 40:6C, midnight roll-over at 1800B0h,
;  diskette motor-off countdown (40:40), then INT 1Ch.
; =====================================================================
int08_timer:
        sti                                     ; F9DA
        push ds                                 ; F9DB
        push ax                                 ; F9DC
        push dx                                 ; F9DD
        call set_ds_bda                         ; F9DE
        push si                                 ; F9E1
        mov si,0x6c                             ; F9E2
        inc word [si]                           ; F9E5
        jnz L_F9EC                              ; F9E7
        inc word [si+0x2]                       ; F9E9
L_F9EC:
        cmp word [si+0x2],byte +0x18            ; F9EC
        jl L_FA03                               ; F9F0
        cmp word [si],0xb0                      ; F9F2
        jnz L_FA03                              ; F9F6
        db 0x33, 0xC0                           ; F9F8  (xor ax,ax)
        mov [si],ax                             ; F9FA
        mov [si+0x2],ax                         ; F9FC
        mov byte [si+0x4],0x1                   ; F9FF
L_FA03:
        pop si                                  ; FA03
        dec byte [0x40]                         ; FA04
        jnz L_FA15                              ; FA08
        and byte [0x3f],0xc                     ; FA0A
        mov al,0xc                              ; FA0F
        mov dx,0x3f2                            ; FA11
        out dx,al                               ; FA14
L_FA15:
        int 0x1c                                ; FA15
        call send_eoi                           ; FA17
        pop dx                                  ; FA1A
        pop ax                                  ; FA1B
        pop ds                                  ; FA1C
        iret                                    ; FA1D
sub_FA1E:
        mov ax,[ds:bp+di]                       ; FA1E
        xchg al,ah                              ; FA21
        db 0x32, 0xD2                           ; FA23  (xor dl,dl)
        mov bl,0x1                              ; FA25
L_FA27:
        test ax,0xffff                          ; FA27
        jz L_FA3C                               ; FA2A
        shr ax,1                                ; FA2C
        jnc L_FA32                              ; FA2E
        db 0x0A, 0xD3                           ; FA30  (or dl,bl)
L_FA32:
        shr ax,1                                ; FA32
        jnc L_FA38                              ; FA34
        db 0x0A, 0xD3                           ; FA36  (or dl,bl)
L_FA38:
        shl bl,1                                ; FA38
        jmp short L_FA27                        ; FA3A
L_FA3C:
        mov [es:si],dl                          ; FA3C
        inc si                                  ; FA3F
        mov bp,0x2000                           ; FA40
        ret                                     ; FA43
sub_FA44:
        cli                                     ; FA44
        mov si,[bx]                             ; FA45
        cmp si,[bx+0x2]                         ; FA47
        mov ax,[si]                             ; FA4A
        ret                                     ; FA4C
save_regs:
        push bx                                 ; FA4D
        push cx                                 ; FA4E
        push dx                                 ; FA4F
        push di                                 ; FA50
        push si                                 ; FA51
        push bp                                 ; FA52
        push ds                                 ; FA53
        push es                                 ; FA54
        db 0x8B, 0xEC                           ; FA55  (mov bp,sp)
        push word [bp+0x10]                     ; FA57
        ret                                     ; FA5A
restore_regs:
        db 0x8B, 0xEC                           ; FA5B  (mov bp,sp)
        pop word [bp+0x12]                      ; FA5D
        pop es                                  ; FA60
        pop ds                                  ; FA61
        pop bp                                  ; FA62
        pop si                                  ; FA63
        pop di                                  ; FA64
        pop dx                                  ; FA65
        pop cx                                  ; FA66
        pop bx                                  ; FA67
        ret                                     ; FA68
        db 0x00, 0x00, 0x00, 0x00, 0x00         ; FA69

; =====================================================================
;  8x8 character font, characters 00-7F (CGA graphics modes) - IBM address
; =====================================================================
font_8x8:
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; FA6E
        db 0x7E, 0x81, 0xA5, 0x81, 0xBD, 0x99, 0x81, 0x7E ; FA76
        db 0x7E, 0xFF, 0xDB, 0xFF, 0xC3, 0xE7, 0xFF, 0x7E ; FA7E
        db 0x6C, 0xFE, 0xFE, 0xFE, 0x7C, 0x38, 0x10, 0x00 ; FA86
        db 0x10, 0x38, 0x7C, 0xFE, 0x7C, 0x38, 0x10, 0x00 ; FA8E
        db 0x38, 0x7C, 0x38, 0xFE, 0xFE, 0x7C, 0x38, 0x7C ; FA96
        db 0x10, 0x10, 0x38, 0x7C, 0xFE, 0x7C, 0x38, 0x7C ; FA9E
        db 0x00, 0x00, 0x18, 0x3C, 0x3C, 0x18, 0x00, 0x00 ; FAA6
        db 0xFF, 0xFF, 0xE7, 0xC3, 0xC3, 0xE7, 0xFF, 0xFF ; FAAE
        db 0x00, 0x3C, 0x66, 0x42, 0x42, 0x66, 0x3C, 0x00 ; FAB6
        db 0xFF, 0xC3, 0x99, 0xBD, 0xBD, 0x99, 0xC3, 0xFF ; FABE
        db 0x0F, 0x07, 0x0F, 0x7D, 0xCC, 0xCC, 0xCC, 0x78 ; FAC6
        db 0x3C, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x7E, 0x18 ; FACE
        db 0x3F, 0x33, 0x3F, 0x30, 0x30, 0x70, 0xF0, 0xE0 ; FAD6
        db 0x7F, 0x63, 0x7F, 0x63, 0x63, 0x67, 0xE6, 0xC0 ; FADE
        db 0x99, 0x5A, 0x3C, 0xE7, 0xE7, 0x3C, 0x5A, 0x99 ; FAE6
        db 0x80, 0xE0, 0xF8, 0xFE, 0xF8, 0xE0, 0x80, 0x00 ; FAEE
        db 0x02, 0x0E, 0x3E, 0xFE, 0x3E, 0x0E, 0x02, 0x00 ; FAF6
        db 0x18, 0x3C, 0x7E, 0x18, 0x18, 0x7E, 0x3C, 0x18 ; FAFE
        db 0x66, 0x66, 0x66, 0x66, 0x66, 0x00, 0x66, 0x00 ; FB06
        db 0x7F, 0xDB, 0xDB, 0x7B, 0x1B, 0x1B, 0x1B, 0x00 ; FB0E
        db 0x3E, 0x63, 0x38, 0x6C, 0x6C, 0x38, 0xCC, 0x78 ; FB16
        db 0x00, 0x00, 0x00, 0x00, 0x7E, 0x7E, 0x7E, 0x00 ; FB1E
        db 0x18, 0x3C, 0x7E, 0x18, 0x7E, 0x3C, 0x18, 0xFF ; FB26
        db 0x18, 0x3C, 0x7E, 0x18, 0x18, 0x18, 0x18, 0x00 ; FB2E
        db 0x18, 0x18, 0x18, 0x18, 0x7E, 0x3C, 0x18, 0x00 ; FB36
        db 0x00, 0x18, 0x0C, 0xFE, 0x0C, 0x18, 0x00, 0x00 ; FB3E
        db 0x00, 0x30, 0x60, 0xFE, 0x60, 0x30, 0x00, 0x00 ; FB46
        db 0x00, 0x00, 0xC0, 0xC0, 0xC0, 0xFE, 0x00, 0x00 ; FB4E
        db 0x00, 0x24, 0x66, 0xFF, 0x66, 0x24, 0x00, 0x00 ; FB56
        db 0x00, 0x18, 0x3C, 0x7E, 0xFF, 0xFF, 0x00, 0x00 ; FB5E
        db 0x00, 0xFF, 0xFF, 0x7E, 0x3C, 0x18, 0x00, 0x00 ; FB66
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; FB6E
        db 0x30, 0x78, 0x78, 0x30, 0x30, 0x00, 0x30, 0x00 ; FB76
        db 0x6C, 0x6C, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00 ; FB7E
        db 0x6C, 0x6C, 0xFE, 0x6C, 0xFE, 0x6C, 0x6C, 0x00 ; FB86
        db 0x30, 0x7C, 0xC0, 0x78, 0x0C, 0xF8, 0x30, 0x00 ; FB8E
        db 0x00, 0xC6, 0xCC, 0x18, 0x30, 0x66, 0xC6, 0x00 ; FB96
        db 0x38, 0x6C, 0x38, 0x76, 0xDC, 0xCC, 0x76, 0x00 ; FB9E
        db 0x60, 0x60, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00 ; FBA6
        db 0x18, 0x30, 0x60, 0x60, 0x60, 0x30, 0x18, 0x00 ; FBAE
        db 0x60, 0x30, 0x18, 0x18, 0x18, 0x30, 0x60, 0x00 ; FBB6
        db 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00 ; FBBE
        db 0x00, 0x30, 0x30, 0xFC, 0x30, 0x30, 0x00, 0x00 ; FBC6
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x60 ; FBCE
        db 0x00, 0x00, 0x00, 0xFC, 0x00, 0x00, 0x00, 0x00 ; FBD6
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x30, 0x00 ; FBDE
        db 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0x80, 0x00 ; FBE6
        db 0x7C, 0xC6, 0xCE, 0xDE, 0xF6, 0xE6, 0x7C, 0x00 ; FBEE
        db 0x30, 0x70, 0x30, 0x30, 0x30, 0x30, 0xFC, 0x00 ; FBF6
        db 0x78, 0xCC, 0x0C, 0x38, 0x60, 0xCC, 0xFC, 0x00 ; FBFE
        db 0x78, 0xCC, 0x0C, 0x38, 0x0C, 0xCC, 0x78, 0x00 ; FC06
        db 0x1C, 0x3C, 0x6C, 0xCC, 0xFE, 0x0C, 0x1E, 0x00 ; FC0E
        db 0xFC, 0xC0, 0xF8, 0x0C, 0x0C, 0xCC, 0x78, 0x00 ; FC16
        db 0x38, 0x60, 0xC0, 0xF8, 0xCC, 0xCC, 0x78, 0x00 ; FC1E
        db 0xFC, 0xCC, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00 ; FC26
        db 0x78, 0xCC, 0xCC, 0x78, 0xCC, 0xCC, 0x78, 0x00 ; FC2E
        db 0x78, 0xCC, 0xCC, 0x7C, 0x0C, 0x18, 0x70, 0x00 ; FC36
        db 0x00, 0x30, 0x30, 0x00, 0x00, 0x30, 0x30, 0x00 ; FC3E
        db 0x00, 0x30, 0x30, 0x00, 0x00, 0x30, 0x30, 0x60 ; FC46
        db 0x18, 0x30, 0x60, 0xC0, 0x60, 0x30, 0x18, 0x00 ; FC4E
        db 0x00, 0x00, 0xFC, 0x00, 0x00, 0xFC, 0x00, 0x00 ; FC56
        db 0x60, 0x30, 0x18, 0x0C, 0x18, 0x30, 0x60, 0x00 ; FC5E
        db 0x78, 0xCC, 0x0C, 0x18, 0x30, 0x00, 0x30, 0x00 ; FC66
        db 0x7C, 0xC6, 0xDE, 0xDE, 0xDE, 0xC0, 0x78, 0x00 ; FC6E
        db 0x30, 0x78, 0xCC, 0xCC, 0xFC, 0xCC, 0xCC, 0x00 ; FC76
        db 0xFC, 0x66, 0x66, 0x7C, 0x66, 0x66, 0xFC, 0x00 ; FC7E
        db 0x3C, 0x66, 0xC0, 0xC0, 0xC0, 0x66, 0x3C, 0x00 ; FC86
        db 0xF8, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0xF8, 0x00 ; FC8E
        db 0xFE, 0x62, 0x68, 0x78, 0x68, 0x62, 0xFE, 0x00 ; FC96
        db 0xFE, 0x62, 0x68, 0x78, 0x68, 0x60, 0xF0, 0x00 ; FC9E
        db 0x3C, 0x66, 0xC0, 0xC0, 0xCE, 0x66, 0x3E, 0x00 ; FCA6
        db 0xCC, 0xCC, 0xCC, 0xFC, 0xCC, 0xCC, 0xCC, 0x00 ; FCAE
        db 0x78, 0x30, 0x30, 0x30, 0x30, 0x30, 0x78, 0x00 ; FCB6
        db 0x1E, 0x0C, 0x0C, 0x0C, 0xCC, 0xCC, 0x78, 0x00 ; FCBE
        db 0xE6, 0x66, 0x6C, 0x78, 0x6C, 0x66, 0xE6, 0x00 ; FCC6
        db 0xF0, 0x60, 0x60, 0x60, 0x62, 0x66, 0xFE, 0x00 ; FCCE
        db 0xC6, 0xEE, 0xFE, 0xFE, 0xD6, 0xC6, 0xC6, 0x00 ; FCD6
        db 0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00 ; FCDE
        db 0x38, 0x6C, 0xC6, 0xC6, 0xC6, 0x6C, 0x38, 0x00 ; FCE6
        db 0xFC, 0x66, 0x66, 0x7C, 0x60, 0x60, 0xF0, 0x00 ; FCEE
        db 0x78, 0xCC, 0xCC, 0xCC, 0xDC, 0x78, 0x1C, 0x00 ; FCF6
        db 0xFC, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0xE6, 0x00 ; FCFE
        db 0x78, 0xCC, 0xE0, 0x70, 0x1C, 0xCC, 0x78, 0x00 ; FD06
        db 0xFC, 0xB4, 0x30, 0x30, 0x30, 0x30, 0x78, 0x00 ; FD0E
        db 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xFC, 0x00 ; FD16
        db 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0x78, 0x30, 0x00 ; FD1E
        db 0xC6, 0xC6, 0xC6, 0xD6, 0xFE, 0xEE, 0xC6, 0x00 ; FD26
        db 0xC6, 0xC6, 0x6C, 0x38, 0x38, 0x6C, 0xC6, 0x00 ; FD2E
        db 0xCC, 0xCC, 0xCC, 0x78, 0x30, 0x30, 0x78, 0x00 ; FD36
        db 0xFE, 0xC6, 0x8C, 0x18, 0x32, 0x66, 0xFE, 0x00 ; FD3E
        db 0x78, 0x60, 0x60, 0x60, 0x60, 0x60, 0x78, 0x00 ; FD46
        db 0xC0, 0x60, 0x30, 0x18, 0x0C, 0x06, 0x02, 0x00 ; FD4E
        db 0x78, 0x18, 0x18, 0x18, 0x18, 0x18, 0x78, 0x00 ; FD56
        db 0x10, 0x38, 0x6C, 0xC6, 0x00, 0x00, 0x00, 0x00 ; FD5E
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF ; FD66
        db 0x30, 0x30, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00 ; FD6E
        db 0x00, 0x00, 0x78, 0x0C, 0x7C, 0xCC, 0x76, 0x00 ; FD76
        db 0xE0, 0x60, 0x60, 0x7C, 0x66, 0x66, 0xDC, 0x00 ; FD7E
        db 0x00, 0x00, 0x78, 0xCC, 0xC0, 0xCC, 0x78, 0x00 ; FD86
        db 0x1C, 0x0C, 0x0C, 0x7C, 0xCC, 0xCC, 0x76, 0x00 ; FD8E
        db 0x00, 0x00, 0x78, 0xCC, 0xFC, 0xC0, 0x78, 0x00 ; FD96
        db 0x38, 0x6C, 0x60, 0xF0, 0x60, 0x60, 0xF0, 0x00 ; FD9E
        db 0x00, 0x00, 0x76, 0xCC, 0xCC, 0x7C, 0x0C, 0xF8 ; FDA6
        db 0xE0, 0x60, 0x6C, 0x76, 0x66, 0x66, 0xE6, 0x00 ; FDAE
        db 0x30, 0x00, 0x70, 0x30, 0x30, 0x30, 0x78, 0x00 ; FDB6
        db 0x0C, 0x00, 0x0C, 0x0C, 0x0C, 0xCC, 0xCC, 0x78 ; FDBE
        db 0xE0, 0x60, 0x66, 0x6C, 0x78, 0x6C, 0xE6, 0x00 ; FDC6
        db 0x70, 0x30, 0x30, 0x30, 0x30, 0x30, 0x78, 0x00 ; FDCE
        db 0x00, 0x00, 0xCC, 0xFE, 0xFE, 0xD6, 0xC6, 0x00 ; FDD6
        db 0x00, 0x00, 0xF8, 0xCC, 0xCC, 0xCC, 0xCC, 0x00 ; FDDE
        db 0x00, 0x00, 0x78, 0xCC, 0xCC, 0xCC, 0x78, 0x00 ; FDE6
        db 0x00, 0x00, 0xDC, 0x66, 0x66, 0x7C, 0x60, 0xF0 ; FDEE
        db 0x00, 0x00, 0x76, 0xCC, 0xCC, 0x7C, 0x0C, 0x1E ; FDF6
        db 0x00, 0x00, 0xDC, 0x76, 0x66, 0x60, 0xF0, 0x00 ; FDFE
        db 0x00, 0x00, 0x7C, 0xC0, 0x78, 0x0C, 0xF8, 0x00 ; FE06
        db 0x10, 0x30, 0x7C, 0x30, 0x30, 0x34, 0x18, 0x00 ; FE0E
        db 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0xCC, 0x76, 0x00 ; FE16
        db 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0x78, 0x30, 0x00 ; FE1E
        db 0x00, 0x00, 0xC6, 0xD6, 0xFE, 0xFE, 0x6C, 0x00 ; FE26
        db 0x00, 0x00, 0xC6, 0x6C, 0x38, 0x6C, 0xC6, 0x00 ; FE2E
        db 0x00, 0x00, 0xCC, 0xCC, 0xCC, 0x7C, 0x0C, 0xF8 ; FE36
        db 0x00, 0x00, 0xFC, 0x98, 0x30, 0x64, 0xFC, 0x00 ; FE3E
        db 0x1C, 0x30, 0x30, 0xE0, 0x30, 0x30, 0x1C, 0x00 ; FE46
        db 0x18, 0x18, 0x18, 0x00, 0x18, 0x18, 0x18, 0x00 ; FE4E
        db 0xE0, 0x30, 0x30, 0x1C, 0x30, 0x30, 0xE0, 0x00 ; FE56
        db 0x76, 0xDC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; FE5E
        db 0x00, 0x10, 0x38, 0x6C, 0xC6, 0xC6, 0xFE, 0x00 ; FE66

; =====================================================================
;  INT 1Ah - TIME OF DAY (functions 0-1 only, no RTC)
; =====================================================================
int1a_time:
        cmp ah,0x2                              ; FE6E
        jnc L_FE9B                              ; FE71
        push ds                                 ; FE73
        call set_ds_bda                         ; FE74
        push si                                 ; FE77
        mov si,0x6c                             ; FE78
        cmp ah,0x0                              ; FE7B
        cli                                     ; FE7E
        jnz L_FE8F                              ; FE7F
        mov dx,[si]                             ; FE81
        mov cx,[si+0x2]                         ; FE83
        mov al,[si+0x4]                         ; FE86
        mov byte [si+0x4],0x0                   ; FE89
        jmp short L_FE98                        ; FE8D
L_FE8F:
        mov [si],dx                             ; FE8F
        mov [si+0x2],cx                         ; FE91
        mov byte [si+0x4],0x0                   ; FE94
L_FE98:
        sti                                     ; FE98
        pop si                                  ; FE99
        pop ds                                  ; FE9A
L_FE9B:
        iret                                    ; FE9B
set_ds_bda:
        push bx                                 ; FE9C
        mov bx,0x40                             ; FE9D
        mov ds,bx                               ; FEA0
        pop bx                                  ; FEA2
        ret                                     ; FEA3
        db 0x00                                 ; FEA4
int08_entry:
        jmp near int08_timer                    ; FEA5

; =====================================================================
;  Interrupt vector table copied to 0000:0000 at POST (offsets, seg F000)
;  INT 00-07, 08-0F (IRQs), 10-17, 18-1F
;  NOTE: INT 1Fh points at FF4C (code) instead of 0 - see notes.
; =====================================================================
vector_table:
        dw 0xFF4C                               ; FEA8
        dw 0xFF4C                               ; FEAA
        dw 0xE6EA                               ; FEAC
        dw 0xFF4C                               ; FEAE
        dw 0xFF4C                               ; FEB0
        dw 0xFF54                               ; FEB2
        dw 0xFF4C                               ; FEB4
        dw 0xFF4C                               ; FEB6
        dw 0xFEA5                               ; FEB8
        dw 0xE987                               ; FEBA
        dw 0xFF47                               ; FEBC
        dw 0xFF47                               ; FEBE
        dw 0xFF47                               ; FEC0
        dw 0xFF47                               ; FEC2
        dw 0xF934                               ; FEC4
        dw 0xFF47                               ; FEC6
        dw 0xF065                               ; FEC8
        dw 0xFEF2                               ; FECA
        dw 0xFEE8                               ; FECC
        dw 0xEC59                               ; FECE
        dw 0xE831                               ; FED0
        dw 0xE923                               ; FED2
        dw 0xE82E                               ; FED4
        dw 0xF502                               ; FED6
        dw 0xE63B                               ; FED8
        dw 0xE5FC                               ; FEDA
        dw 0xFE6E                               ; FEDC
        dw 0xFF4C                               ; FEDE
        dw 0xFF4C                               ; FEE0
        dw 0xEDB8                               ; FEE2
        dw 0xEFC7                               ; FEE4
        dw 0xFF4C                               ; FEE6
int12_memsize:
        sti                                     ; FEE8
        push ds                                 ; FEE9
        call set_ds_bda                         ; FEEA
        mov ax,[0x13]                           ; FEED
        pop ds                                  ; FEF0
        iret                                    ; FEF1
int11_equipment:
        sti                                     ; FEF2
        push ds                                 ; FEF3
        call set_ds_bda                         ; FEF4
        mov ax,[0x10]                           ; FEF7
        pop ds                                  ; FEFA
        iret                                    ; FEFB

; ---------------------------------------------------------------------
;  POST messages
; ---------------------------------------------------------------------
msg_8259:
        db '8259', 0x00                         ; FEFC
msg_printer_err:
        db 'PR.P.Err', 0x00                     ; FF01
msg_keyboard:
        db 'K-B ', 0x00                         ; FF0A
msg_disk:
        db 'Disk', 0x00                         ; FF0F
msg_self_test:
        db '* SELF-TEST *'                      ; FF14
msg_crlf:
        db 0x0D, 0x0A, 0x00                     ; FF21
msg_space:
        db ' ', 0x00                            ; FF24
msg_parity:
        db 'P-CK'                               ; FF26
msg_error:
        db ' Error !', 0x00                     ; FF2A
msg_version:
        db 'BIOS Version 3.30', 0x0D, 0x0A, 0x00 ; FF33
dummy_irq:
        push ax                                 ; FF47
        call send_eoi                           ; FF48
        pop ax                                  ; FF4B
dummy_iret:
        sti                                     ; FF4C
        iret                                    ; FF4D
        db 0x00, 0x00, 0x00, 0x00, 0x00         ; FF4E
ibm_iret:
        db 0xCF                                 ; FF53

; =====================================================================
;  INT 05h - PRINT SCREEN (IBM address).  Status byte at 50:00.
; =====================================================================
int05_print_screen:
        call save_regs                          ; FF54
        mov bx,0x50                             ; FF57
        mov es,bx                               ; FF5A
        db 0x33, 0xED                           ; FF5C  (xor bp,bp)
        test byte [es:bp+0x0],0x80              ; FF5E
        jnz L_FF6C                              ; FF63
        cmp byte [es:bp+0x0],0x0                ; FF65
        jnz L_FFD8                              ; FF6A
L_FF6C:
        mov byte [es:bp+0x0],0x1                ; FF6C
        push ax                                 ; FF71
        mov al,0xa                              ; FF72
        call sub_FFDB                           ; FF74
        mov al,0xd                              ; FF77
        call sub_FFDB                           ; FF79
        call set_ds_bda                         ; FF7C
        mov bh,[0x62]                           ; FF7F
        call sub_F363                           ; FF83
        db 0x32, 0xED                           ; FF86  (xor ch,ch)
        mov di,[di]                             ; FF88
        db 0x33, 0xD2                           ; FF8A  (xor dx,dx)
L_FF8C:
        db 0x8B, 0xF2                           ; FF8C  (mov si,dx)
        mov ah,0x2                              ; FF8E
        int 0x10                                ; FF90
        mov ah,0x8                              ; FF92
        int 0x10                                ; FF94
        mov ah,0x0                              ; FF96
        cmp al,0x0                              ; FF98
        jnz L_FF9E                              ; FF9A
        mov al,0x20                             ; FF9C
L_FF9E:
        call sub_FFDB                           ; FF9E
        test ah,0x29                            ; FFA1
        jz L_FFAA                               ; FFA4
        dec ch                                  ; FFA6
        jmp short L_FFCD                        ; FFA8
L_FFAA:
        db 0x8B, 0xD6                           ; FFAA  (mov dx,si)
        add dl,0x1                              ; FFAC
        cmp dl,[0x4a]                           ; FFAF
        jnz L_FF8C                              ; FFB3
        mov dl,0x0                              ; FFB5
        db 0x8B, 0xF2                           ; FFB7  (mov si,dx)
        mov al,0xa                              ; FFB9
        call sub_FFDB                           ; FFBB
        mov al,0xd                              ; FFBE
        call sub_FFDB                           ; FFC0
        db 0x8B, 0xD6                           ; FFC3  (mov dx,si)
        add dh,0x1                              ; FFC5
        cmp dh,0x19                             ; FFC8
        jnz L_FF8C                              ; FFCB
L_FFCD:
        db 0x8B, 0xD7                           ; FFCD  (mov dx,di)
        mov ah,0x2                              ; FFCF
        int 0x10                                ; FFD1
        pop ax                                  ; FFD3
        mov [es:bp+0x0],ch                      ; FFD4
L_FFD8:
        jmp near L_F1C0                         ; FFD8
sub_FFDB:
        mov ah,0x0                              ; FFDB
        db 0x33, 0xD2                           ; FFDD  (xor dx,dx)
        int 0x17                                ; FFDF
        ret                                     ; FFE1
int10_thunk:
        pushf                                   ; FFE2
        call 0xf000:0xed54                      ; FFE3
        iret                                    ; FFE8
        db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 ; FFE9

; =====================================================================
;  Reset vector, "date" field and model byte
;  FFF5: "Multitech" instead of the usual MM/DD/YY date
;  FFFE: model byte FFh = IBM PC (5150), not XT (FEh); FFFF = checksum
; =====================================================================
reset_vector:
        db 0xEA, 0x5B, 0xE0, 0x00, 0xF0         ; FFF0
date_id:
        db 'Multitech'                          ; FFF5  date field holds the name
model_byte:
        db 0xFF, 0x2B                           ; FFFE  model byte FF = PC, checksum 2Bh

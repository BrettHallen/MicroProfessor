# MPF-PC/500 BIOS V3.30: disassembly notes

These notes go with `mpf-pc500-bios-v330.asm`, a fully labelled disassembly of the U36 ROM
(`MultiTech_MPF_PC-500_U36_62370F21.ROM`). The source re-assembles to a
byte-identical image:

```
nasm -O0 -f bin -o bios.bin mpf-pc500-bios-v330.asm
```

Leave `-O0` in. Without it NASM shortens some immediates and the output no longer matches.
About 350 instructions are written as `db` bytes, with the instruction in the comment. NASM would
encode them differently (for example `33 C0` rather than `31 C0` for `xor ax,ax`), so the
original bytes are kept.

Routine names, section headers and comments are my interpretation of the code. Treat them
as a starting point, not as Multitech documentation.

## ROM identification

| Item | Value |
|---|---|
| Chip | Mitsubishi M5L2764K (2764, 8 KB EPROM), socket U36, label "PC/500 V3.30 © Multitech" |
| Mapped at | F000:E000 – F000:FFFF (physical FE000–FFFFF) |
| CRC32 / MD5 / SHA-1 | `62370F21` / `518378fc59ea13168bf0120a7962a283` / `da6e161c7454dc6a2d4fd4b73dac2a3e782ed7e8` |
| 8-bit checksum | 00 (valid), with the correction byte at FFFF = 2Bh |
| Version string | `BIOS Version 3.30` |
| "Date" field (FFF5) | `Multitech`. The usual `MM/DD/YY` date is replaced by the company name |
| Model byte (FFFE) | FFh = IBM PC (5150), not FEh (XT) |

## How compatible it is with IBM

Software in the 1980s sometimes jumped straight to fixed addresses in the IBM BIOS.
Multitech kept the most commonly used entry points and moved the rest:

| IBM address | IBM use | Here |
|---|---|---|
| E05B | POST entry | ✅ |
| E2C3 | NMI handler | ❌ NMI is at E6EA |
| E6F2 | INT 19h boot | ❌ boot is at E5FC |
| E729 / E739 | Baud table / INT 14h | ❌ INT 14h is at E831 |
| E82E | INT 16h | ✅ |
| E987 | INT 09h | ✅ |
| EC59 | INT 13h | ✅ |
| EF57 | INT 0Eh | ❌ at F934 |
| EFC7 | Diskette parameter table | ✅ |
| EFD2 | INT 17h | ❌ INT 17h is at F502. EFD2 is the INT 10h "write char/attr" code |
| F065 | INT 10h | ✅ |
| F0A4 | Video parameter table | ❌ at EDB8 |
| F841 / F84D / F859 | INT 12h / 11h / 15h | ❌ at FEE8 / FEF2 / E923 |
| FA6E | 8×8 graphics font | ✅ |
| FE6E | INT 1Ah | ✅ |
| FEA5 | INT 08h | ✅ |
| FEF3 | Vector table | ❌ at FEA8 |
| FF53 | Dummy IRET | ✅ (a lone `CF` byte placed there on purpose) |
| FF54 | INT 05h print screen | ✅ |
| FFF0 | Reset vector | ✅ |

Software that calls only through interrupt vectors, which covers almost everything, won't notice.

## Power-on sequence (POST)

Addresses are offsets in segment F000.

1. **E006: extension ROM hook.** Before touching any hardware, the BIOS reads the word at
   F000:5FFE (physical F5FFE). If it is `55 AA`, it jumps to F000:4104 and never comes back.
   See "Interesting findings" below.
2. **E016: chipset reset.** Sets the 8255 to mode 99h, the same as the IBM PC. Disables NMI, both
   MDA and CGA video and the 8237.
3. **E7A1: PIT channel 2 test.** This is a "stackless call": SP points at a return
   address stored in ROM (E002), because RAM hasn't been checked yet. On failure: `HLT`.
4. **E046: start a tone.** On success the speaker starts. It stops again after the first
   64 KB has been cleared, which gives the short power-on chirp.
5. **E05D: 8237 DMA register test.** On failure: `HLT`. See the quirk below.
6. **E081: DRAM refresh.** PIT channel 1 is set to mode 2 with a count of 18 (about 15 µs), driving DMA
   channel 0. Then DMA channels 1–3 and the 8259 (vectors at INT 08h) are programmed.
7. **E0B6: clear RAM.** The BIOS zeroes (SW1-3/4 + 1) × 64 KB, which initialises parity. The warm-boot
   flag at 40:72 is saved across the clear.
8. **E7CF: test the first 64 KB.** Cold boot only. A second stackless routine uses `PUSH`/`POP`
   with SS = the segment under test. It makes three passes (00→01, 01→FF, FF→00) and checks the
   parity bit in port 62h. On failure: `HLT`.
9. **E10E: set up a stack and vectors.** Stack at 0030:0100. 32 vectors are copied from FEA8, and
   SW1 is copied into the equipment word at 40:10.
10. **E145: video.** The mode comes from SW1-5/6. Video RAM is tested (16 KB on CGA, 4 KB on MDA),
    and the BIOS checks that the retrace bits in 3DA/3BA toggle. On failure it gives a beep code and
    continues with INT 10h pointed at a dummy handler.
11. **E1EB: video option ROMs.** Scans C000–C7FF, for example for an EGA card's ROM.
12. **E211: colour bars.** Cold boot on a colour mode only: three full-width bars of `R`, `G` and `B`
    in red, green and blue. Then it prints `* SELF-TEST *`.
13. **E23D: 8259 test.** Checks that the IMR reads back correctly, then masks all IRQs and makes sure
    none arrive.
14. **E26C: keyboard test.** Resets the keyboard and expects AAh.
15. **E283: RAM test prompt.** Prints `RAM TEST (Y/N) ?` and waits briefly. **Y** (scan code 15h)
    tests every byte of every KB with the patterns 55h, ABh and 00h. Anything else, or no key, only
    probes one byte per KB. Either way the size is counted up live from 64 KB in 1 KB steps, up to 640 KB.
16. **E28F: memory warning.** `WARNING: RAM Error !` appears if the size isn't a multiple of 64 KB, or if
    working RAM turns up above a failed bank.
17. **E3E8: zero the rest of RAM.** Cold boot only. Zeroes everything above 64 KB.
18. **E4D1: BIOS data area.** Sets up the keyboard buffer (40:1A/1C/80/82) and the printer and serial
    time-outs. Restores the real IRQ vectors and checks the printer port at 378h.
19. **E51C: diskette.** Only if SW1-1 is off. Resets the FDC, turns on drive A's motor and seeks to track 39.
20. **E56B: port detection.** Printers at 3BC/378/278, the game port at 201h and serial ports at 3F8/2F8 are
    counted into the equipment word. NMI is then enabled.
21. **E5D0: finish.** Clears the screen, prints `BIOS Version 3.30`, scans C800–F5FF for option ROMs,
    unmasks the timer and keyboard, then calls INT 19h.
22. **E5FC: INT 19h boot.** Up to 3 tries to read drive A's boot sector to 0:7C00. On success it
    gives **two short beeps** and jumps to it. On failure it calls INT 18h (ROM BASIC, if fitted at
    F6000), then `* No-System *  *Insert system disk and strike any key`.

If SW1-1 says no diskettes are fitted, POST calls INT 18h straight after port detection.

## Messages and beep codes

| Message | Meaning |
|---|---|
| `* SELF-TEST *` | Start of the visible tests (cold boot) |
| `8259 Error !` | Interrupt controller IMR failed, or a stray interrupt arrived |
| `K-B  Error !` | Keyboard didn't answer the reset with AAh |
| `RAM TEST (Y/N) ?` / `RAM SIZE (K)` | Memory test prompt and live count |
| `WARNING: RAM Error !` | Odd memory size, or a hole in memory |
| `PR.P.Err` | No printer port at 378h |
| `Disk Error !` | Diskette controller or drive A failed the reset or seek |
| `P-CK Error !` | NMI: memory parity error or I/O channel check |
| `* No-System *` | No bootable diskette and no ROM BASIC |

| Beeps | Meaning |
|---|---|
| Short chirp at power-on | Normal (PIT test passed, RAM being cleared) |
| 2 short | Boot sector loaded OK, about to boot |
| 1 long, 2 short | Video RAM test failed |
| 1 long, 3 short | Video adapter not producing retrace |
| (1 long, 5 short) × 10, then halt | Parity / I/O channel check (NMI) |
| Silent halt, blank screen | PIT, DMA or first-64 KB RAM failure (before video is up) |

## SW1 DIP switch

The BIOS reads SW1 through port 60h with port 61h bit 7 set, exactly like the IBM 5150. Switch ON
reads as 0. The board has pads for **SW2 but no switch fitted**. That fits the code, which never
reads memory size from switches and finds it by probing instead.

| Switch | Bit | Meaning | On the board in the photo |
|---|---|---|---|
| 1 | 0 | OFF = diskette drive(s) fitted (boot from A:) | OFF: fitted |
| 2 | 1 | 8087 present (IBM meaning, unused by this BIOS) | ON: none |
| 3–4 | 2–3 | Number of 64 KB blocks to pre-clear (1–4) | 3 OFF, 4 ON: 128 KB |
| 5–6 | 4–5 | Display: ON/ON none or EGA, OFF/ON CGA 40×25, ON/OFF CGA 80×25, OFF/OFF MDA | 5 ON, 6 OFF: CGA 80×25 |
| 7–8 | 6–7 | Number of diskette drives − 1 | 7 OFF, 8 ON: 2 drives |

The setting in the photo (CGA, two drives) matches the Popular 500's stock configuration.
SW1-3/4 only controls the first clear. Real memory size always comes from the probe, so these two
switches matter far less than they do on an IBM PC.

## I/O the BIOS expects

| Port | Device |
|---|---|
| 00–0F, 81–83 | 8237 DMA and page registers |
| 20–21 | 8259 PIC |
| 40–43 | 8253 PIT (ch0 timer, ch1 refresh, ch2 speaker) |
| 60–63 | 8255 PPI (keyboard / SW1, control, parity status) |
| A0 | NMI mask |
| F0 | Written by Ctrl+Alt+Keypad-plus (see below) |
| 201 | Game port (detected) |
| 278 / 378 / 3BC | Printer ports (378 is tested and initialised) |
| 2F8 / 3F8 | Serial ports (detected) |
| 3B0–3BF / 3D0–3DF | MDA / CGA |
| 3F0–3F5 | NEC 765 diskette controller |

## Interesting findings

**1. A reset-time extension ROM hook (E006).** The very first instruction after reset looks for
`55 AA` at F5FFE, the last word of an 8 KB block at F4000–F5FFF. If it finds it, it jumps to F4104
before initialising anything, so that ROM would take over the whole machine. IBM doesn't do this.
The empty 28-pin socket on the CPU card (silkscreen U43, next to JP1) is the obvious candidate, but
I haven't confirmed its address decoding. Tracing U43's chip select, or checking what JP1 changes,
would settle it. Possible uses include a diagnostic ROM, a Chinese-language BIOS, or a replacement BIOS.

**2. "Columbia" inside the diskette code (F768).** The ASCII text `Columbia` sits between two INT 13h
routines, and a `jmp short` at F701 skips over it. Its position looks deliberate. It could
be a credit or watermark, perhaps for Columbia Data Products, which shipped one of the first
clean-room PC BIOSes (MPC 1600, 1982). The INT 13h code also looks different from the rest of the
ROM: it builds FDC commands by pushing bytes on the stack and keeps its own scratch bytes at
40:C3–40:CF. That suggests this part came from somewhere else. Comparing it with a CDP BIOS dump
would be the way to check.

**3. Ctrl+Alt+Keypad-plus writes to port F0h (EC45 → F71E).** This sits next to the Ctrl+Alt+Del
handler. It writes 00h to I/O port F0h. On many later "turbo" XT clones a key combination like this
switched CPU speed, and this card has an 8088-2 (an 8 MHz part), but nothing in the BIOS shows what
F0h does. If something on the board decodes F0h, that's the place to look.

**4. Interactive RAM test.** Most BIOSes of the time either always tested memory or never did.
This one asks, and shows the size counting up as it goes.

**5. Colour bars at power-on.** In a colour mode, the cold boot draws red, green and blue bars, which
makes a quick monitor check.

**6. Quirks and small bugs**
- The DMA register test (E05D) reuses the E813 pattern table, which starts with 00h. The loop stops
  on a zero pattern, so only 00h is ever written and read back. The test would miss most stuck bits.
- The byte test patterns at E491 are `55h, ABh, 00h`. `ABh` rather than the usual `AAh` looks like a
  typo. Bit 0 stays at 1 for both the 55h and ABh passes, so only the 00h pass checks it.
- At E103 there is a "speaker on, then halt" path after the first-64 KB test that can never run.
  A failure always takes the `jc` to a silent halt.
- Option ROMs are called without checking their checksum, unlike IBM.
- The INT 1Fh vector (font for characters 80h–FFh in CGA graphics) points at FF4C, which is code,
  instead of 0000:0000. Programs that print high-ASCII characters in graphics mode without setting
  INT 1Fh themselves would draw garbage.
- INT 15h always returns AH=86h, CF=1 (no cassette), and INT 1Ah supports only functions 0 and 1 (no RTC).

## Open questions / next steps

- Trace U43's address decode and JP1, to find out whether the spare socket is the F4000 extension ROM.
- Find out what responds to I/O port F0h.
- Dump the BIOS of an MPF-PC/700 or an Acer 500+ (CPU/500+ PB87035-2) to see how the code evolved.
- Compare the INT 13h section with a Columbia Data Products MPC BIOS.
- An emulator machine profile (86Box, MAME) could be worth trying. The BIOS only drives standard
  PC chips, so it may run on a generic 8088 PC/XT machine model.

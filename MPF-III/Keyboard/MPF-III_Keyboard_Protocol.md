# MPF‑III Keyboard → Host Serial Protocol

How the Multitech Micro‑Professor MPF‑III talks to its detached keyboard, reverse‑engineered
from the keyboard's INS8035 firmware, the host (Apple IIe‑clone) ROMs, and logic‑analyser
captures of an Arduino keyboard emulator.

---

## The setup

The MPF‑III keyboard is a separate unit on a coiled cable with a **DE9 connector**. Inside it
is an **Intel 8035** microcontroller (program in an external 2732 EPROM, U5) that scans the key
matrix and sends keystrokes to the main computer **serially**. The main board is an Apple IIe
clone (6502), which reconstructs each byte in hardware (a 74LS164 shift register + an LM556)
and presents it to the CPU at the classic Apple keyboard address **$C000**.

So there are really two puzzles: (1) get the machine to **boot** with our emulated keyboard,
and (2) speak the **serial keystroke protocol** correctly.

---

## Stage 1 — getting past the self‑test

With no keyboard attached, the machine just loops in its self‑test. The reason turned out to be
delightfully mundane. At cold start the host ROM runs:

```
C1E1:  LDY $C062     ; read Closed‑Apple button (BUTN1)
C1E4:  BPL ...        ; bit7 = 0 -> boot normally
C1E6:  JMP $C230      ; bit7 = 1 -> SELF‑TEST
```

That's the standard Apple IIe "hold Solid/Closed‑Apple at reset → diagnostics" feature. On the
MPF‑III the Apple buttons live **on the keyboard** (PB0/PB1, DE9 pins 7 & 1). With no keyboard,
those inputs float to the "pressed" state, so every reset drops into the self‑test.

**Fix:** hold the PB1 line at its released level (drive it low / pull it down) so `$C062`
reads 0. Then the machine boots normally — in both MPF‑III and Apple‑II modes.

---

## Stage 2 — the serial keystroke protocol

### The DE9 link

| DE9 pin | Signal  | Direction | Role |
|--------:|---------|-----------|------|
| 4 | DATA   | kbd → host | serial data bit (one bit per clock) |
| 5 | CLOCK  | kbd → host | **bit clock** — 8 pulses, one per data bit |
| 6 | STROBE | kbd → host | **byte strobe** — one pulse *after* the 8 bits |
| 9 | AKD    | kbd → host | "Any Key Down" — high while a key is held |
| 1 / 7 | PB1 / PB0 | kbd → host | the two Apple buttons |
| 8 | RESET  | kbd → host | warm‑reset line |
| 2 / 3 | +5V / GND | power | |

> Note: early documentation listed pin 5 as a *host‑driven* "clock" handshake. It isn't —
> it's the keyboard's own **bit clock**. That one misunderstanding is what cost the most time.

### What's actually sent — the scan code

Each key is sent as a single 8‑bit value that is simply the **7‑bit ASCII code with bit 7 set**:

```
scan code = (ASCII & 0x7F) | 0x80
```

So `A` = `0xC1`, `1` = `0xB1`, space = `0xA0`, Return = `0x8D`. Bit 7 is the "key down" marker,
which conveniently becomes the key‑available strobe bit the host expects at `$C000`.

### Anatomy of one keystroke (measured)

For each character the keyboard:

1. Raises **AKD** (key is down).
2. ~0.5 ms later, clocks the **8 data bits, LSB first**, on **DATA**, one **CLOCK** pulse each.
3. ~0.8 ms after the last bit, emits **one STROBE** pulse — this tells the host "byte complete".
4. Drops **AKD**.

```
            <-- ~5 ms per character -->
AKD     ___/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___
DATA    ‾‾‾‾< b0 >< b1 >< .. >< .. >< b7 >‾‾‾‾‾‾‾‾‾‾‾‾‾‾    (LSB first, valid before each clock)
CLOCK   ______|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|________________  (8 pulses, ~460 µs apart)
STROBE  _________________________________________|‾|_______  (1 pulse, ~0.8 ms after bit 8)
```

Measured timing from the working capture (Arduino emulator):
- bit‑clock period ≈ **460 µs** (the real 8035 at 3.58 MHz runs ~670 µs; the host tolerates a range)
- AKD → first clock ≈ **500 µs**
- last clock → byte strobe ≈ **800 µs**
- whole character ≈ **5 ms**

Example — sending `A` (`0xC1` = `1100 0001`), DATA at the 8 clock edges, LSB first:
`1,0,0,0,0,0,1,1` → reassembles to `0xC1`. ✓

### What the host does with it

On the main board the 8 **CLOCK** pulses shift the 8 **DATA** bits into a **74LS164** shift
register. The single **STROBE** pulse then sets the key‑available flip‑flop, which is bit 7 of
**$C000**. The 6502 firmware just runs the ordinary Apple keyboard loop:

```
C9ED:  LDA $C000     ; bit7 set = a key is ready
C9F0:  BPL C9ED      ; spin until ready
C9F2:  STA $C010     ; read it, clear the strobe
```

`$C000` then holds the familiar Apple value: bit 7 = strobe, bits 6–0 = the ASCII character.

---

## The gotcha

The data was provably perfect on the wire from very early on — yet the screen showed garbage
and a stream of beeps. The cause: we were sending **all 8 bit‑clocks on the STROBE line**. The
host treats *every* strobe pulse as "a key is ready", so it read `$C000` **eight times per
character**, each time catching the shift register **half‑filled** → eight garbage bytes (mostly
control codes = beeps), with the odd complete one slipping through.

The fix was to recognise that the host needs **two separate signals**:

- a **bit clock** (8 pulses) to shift the 74LS164, and
- a **byte strobe** (1 pulse) to say "the byte is complete, latch it".

Splitting those onto **pin 5 (clock)** and **pin 6 (strobe)** — exactly the two clock‑like
signals the keyboard firmware generates internally (P1.5 ×8 and P1.6 ×1) — made it work
first try: a clean `A` on screen, no beeps.

---

## Protocol cheat‑sheet

```
Idle:        AKD low.  CLOCK/STROBE/DATA idle.
Per key:
   1. AKD -> high
   2. for bit 0..7 (LSB first):
         set DATA = bit
         pulse CLOCK   (rising edge clocks the host's 74LS164)
   3. pulse STROBE once   (sets $C000 bit7 = "key ready")
   4. AKD -> low
Scan code = (ASCII & 0x7F) | 0x80     e.g. 'A'=0xC1, ' '=0xA0, Return=0x8D
Host reads the byte at $C000 (bit7 = strobe), clears it by touching $C010.
```

*Reverse‑engineered with a lot of help from Claude (Anthropic) — disassembly of the 8035
keyboard firmware and the 6502 host ROMs, plus decoding the logic‑analyser captures.*

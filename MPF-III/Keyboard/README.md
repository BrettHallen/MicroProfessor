# MPF-III Keyboard
Unfortunately my MPF-III came sans keyboard and there appears to be ZERO information about the keyboard controller (an Intel 8048) or its matrix layout, so I need to figure things out on my own.<br>

The MPF-III will execute a self-test if it boots without the presence of a keyboard.  (How is this detected?)<br>

This is what I've discovered - updating as I progress.<br>

## Keyboard Interface
We know it uses a serial protocol via the DE9 connector on the computer.  The pinout is known from documentation:

| DE9 Pin | Signal | Direction |
|---------|--------|-----------|
| Pin 1   | PB1    | To MPF    |
| Pin 2   | +5V    | From MPF  |
| Pin 3   | GND    | From MPF  |
| Pin 4   | DATA   | To MPF    |
| Pin 5   | CLOCK  | From MPF  |
| Pin 6   | STROBE | To MPF?   |
| Pin 7   | PB0    | To MPF    |
| Pin 8   | RESET  | To MPF    |
| Pin 9   | AKD    | To MPF    |

### PB0
To invoke a cold reset:
- Press CTRL + RESET then PB0
- Release CTRL + RESET then PB0
- The MPF-III will then perform a cold restart

### PB1
This key is used for self-test of the system:
- Press CTRL + RESET then PB1
- Release CTRL + RESET then PB1
- The MPF-III will then start the self-test (same as when computer boots with no keyboard connected)

### RESET
This is idle high.  To invoke a warm restart press CTRL + RESET.

### CLOCK
This signal is idle low.  The MPF takes this signal high when they keyboard takes AKD high.  It remains high as long as AKD is high.

### AKD (Any Key Down)
This signal is idle low.  The keyboard takes it high when a key is pressed.  In response the MPF will take the CLOCK high for the duration that AKD is high.<br>

### DATA
I'm guessing that the keyboard will send the scan code serially via the DATA signal and toggle the STROBE for each bit.  Under investigation.

### STROBE
I think ... maybe ... the keyboard will toggle STROBE for each scan code bit it sends serially via the DATA signal ... ?

## Keyboard microcontroller
Annotated disassembly of the MCS-48 code used by the controller is [here](https://github.com/BrettHallen/MicroProfessor/blob/main/MPF-III/ROMs/Analysis/MPF-III_KEYBOARD_disassembly.TXT) (thanks to RetroAND & his dad for making the ROM dump available!).<br>

## Keyboard matrix
Based on the controller disassembly, here is a possible keyboard matrix.  To be confirmed (because I don't have an actual keyboard!).

```
     Col7   Col6   Col5   Col4   Col3   Col2   Col1   Col0
    (bit7) (bit6) (bit5) (bit4) (bit3) (bit2) (bit1) (bit0)
   ┌───────────────────────────────────────────────────────┐
 R0│ F1     F2     F3     F4     F5     F6     F7     F8   │
   ├───────────────────────────────────────────────────────┤
 R1│ F9     F10    F11    F12    PB1    PB0    HALT   BREAK│
   ├───────────────────────────────────────────────────────┤
 R2│ ` ~    1 !    2 @    3 #    4 $    5 %    6 ^    7 &  │
   ├───────────────────────────────────────────────────────┤
 R3│ 8 *    9 (    0 )    - _    = +    \ |    DEL    INSC │
   ├───────────────────────────────────────────────────────┤
 R4│ Tab    Q      W      E      R      T      Y      U    │
   ├───────────────────────────────────────────────────────┤
 R5│ I      O      P      [ {    ] }           CPES   ←    │
   ├───────────────────────────────────────────────────────┤
 R6│ Caps   A      S      D      F      G      H      J    │
   ├───────────────────────────────────────────────────────┤
 R7│ K      L      ; :    ' "    Return CLRS   HOME   ↑    │
   ├───────────────────────────────────────────────────────┤
 R8│ Shift  Z      X      C      V      B      N      M    │
   ├───────────────────────────────────────────────────────┤
 R9│ , <    . >    / ?    Space  Ctrl   Alt    →      ↓    │
   ├───────────────────────────────────────────────────────┤
R10│NumLk  7 Home 8 ↑    9 PgUp  /      4 ←    5      6 →  │
   │ *     1 End  2 ↓    3 PgDn  -      0 Ins  . Del  + =  │
   └───────────────────────────────────────────────────────┘
```

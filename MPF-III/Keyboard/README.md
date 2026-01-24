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


// =============================================================================
//  MPF-III Keyboard Serial-Protocol Emulator  (Arduino Uno / Nano, 5V logic)
// =============================================================================
//  Purpose: act as the keyboard and send ONE scan code to the MPF-III host over
//  the DE9, to confirm the serial bus protocol. A single momentary switch wired
//  between two pins simulates one key press.
//
//  PROTOCOL DERIVED FROM THE 8035 FIRMWARE (not guessed):
//  The transmitter is the timer-ISR routine at ROM 0x185-0x1FA. It is started
//  when the key handler sets RB0.R6 bit5 (ROM 0x21E) and then spins at 0x221
//  until the ISR clears it. One "phase" runs per timer tick (counter at [0x2F]):
//
//    Phase 0      (0x1E5): DATA=0 (line setup), AKD=1, pulse FRAME(P1.6)
//    Phase 1..8   (0x19D): 8 data bits, **LSB FIRST** (code is `rr a` each bit);
//                          DATA = current bit, then ONE STROBE pulse (P1.5 high
//                          then low) per bit  -> exactly 8 strobe pulses/byte
//    Phase 9      (0x1B8): DATA=1 (idle / stop, no strobe)
//    Phase 10     (0x1C4): pulse FRAME(P1.6) again (byte-ready marker)
//    Phase 16     (0x1BC): done; clears bit5 so the main code continues
//
//  8035 P1 line -> signal (-> DE9 pin, per your README):
//    P1.7 = DATA   (DE9 pin 4)      P1.5 = STROBE/shift-clock (DE9 pin 6)
//    P1.4 = AKD    (DE9 pin 9)      P1.6 = FRAME/byte-ready strobe (role TBC)
//    Host drives CLOCK (DE9 pin 5), idle low, goes high while AKD is high.
//
//  The byte shifted out is the full 8-bit scan code (ROM: R5 = code AND
//  (0x7F | R7), and R7 bit7 is set by SET_READY, so all 8 bits are sent).
//
//  TIMING: 8035-6 @ ~6 MHz, timer reload 0xFB -> ~400 us per phase/bit, with a
//  short (~10 us) strobe-high width. Those are the defaults below; slow them
//  down (BIT_PERIOD_US larger) if you just want to watch it on a scope.
//
//  THINGS TO CONFIRM with a logic analyzer (and flip the #defines if needed):
//   * Signal polarity through the keyboard's 74LS244 buffer / SP8337 line driver
//   * The exact role of FRAME (P1.6) and whether the host needs it
//   * Whether the host's 74LS164 expects LSB-first (firmware) or MSB-first at
//     its parallel output -> set BIT_ORDER_LSB_FIRST accordingly
//   * Whether to wait for the host CLOCK handshake before clocking data
// =============================================================================

// ---- Pin assignments (kept compatible with your probe sketch) ---------------
#define AKD_PIN     2   // OUT: any-key-down level   (P1.4, DE9 pin 9)
#define DATA_PIN    3   // OUT: serial data          (P1.7, DE9 pin 4)
#define CLOCK_PIN   4   // (legacy) host clock input (DE9 pin 5) - NON-split mode
#define BITCLK_PIN  4   // SPLIT mode: OUTPUT 8-pulse bit clock -> DE9 pin 5
#define STROBE_PIN  5   // OUT: -> DE9 pin 6.  SPLIT: one byte-strobe/byte.
                        //                     non-split: 8 pulses (old behavior)
#define PB0_PIN     6   // OUT: pushbutton 0 -> host $C061 (Open-Apple),  DE9 pin 7
#define PB1_PIN     7   // OUT: pushbutton 1 -> host $C062 (Closed-Apple), DE9 pin 1

// IMPORTANT - why the host loops in self-test with no keyboard:
//   The MPF-III host (Apple IIe clone) cold-start at ROM $C1E1 does
//       LDY $C062 ; BUTN1 / Closed-Apple (= keyboard PB1)
//       BPL ...   ; bit7=0 -> normal boot ; bit7=1 -> JMP $C230 = SELF-TEST
//   PB1/PB0 are the apple buttons, routed from the KEYBOARD over DE9 pins 1/7.
//   With no keyboard those host inputs float to the 'pressed' state (bit7=1),
//   so every reset re-enters the self-test (the cyclic self-test you see).
//   Fix: hold PB1 (and PB0) at the RELEASED level so $C062/$C061 bit7 = 0.
//   On a standard Apple, pressed = HIGH, released = LOW -> drive these LOW.
//   (A 3.3k-10k pull-DOWN to GND on host pin 1/7 does the same in hardware.)
//   If your interface turns out inverted, set PB_RELEASED_LEVEL to HIGH.
#define PB_RELEASED_LEVEL LOW
#define RESET_PIN   8   // IN : host reset            (DE9 pin 8) idle high
#define FRAME_PIN   9   // OUT: frame/byte-ready strobe (P1.6) -- role TBC

// Single-key simulation: wire a momentary switch between these two pins.
#define KEY_GND_PIN 10  // OUT driven LOW  (acts as the "ground" side of the key)
#define KEY_SNS_PIN 11  // IN  pullup      (reads LOW when the switch is closed)

// ---- What to send -----------------------------------------------------------
// The message typed when the test switch (D10-D11) is closed.
// Each character is sent as the keyboard's scan code = (ASCII & 0x7F) | 0x80,
// which is exactly the value the host expects to see at $C000.
const char* MESSAGE = "HELLO? IS THIS THING ON?";
#define APPEND_RETURN 0    // 1 = also send Return (0x8D) at the end of MESSAGE

// Or send a single raw scan code instead of MESSAGE (set SEND_MESSAGE 0).
// Codes: 'a'=0xE1 'A'=0xC1 '1'=0xB1 Return=0x8D Space=0xA0 ESC=0x9B F1=0x20 DEL=0xFF
#define SEND_MESSAGE 0       // 0 = send ONE SINGLE_CODE per press (diagnostic)
uint8_t SINGLE_CODE = 0xC1;  // 'A'. Send ONE and count how many chars appear.

// Frame (P1.6) markers. The firmware pulses at frame start AND end. If the host
// latches $C000 on the START pulse you get a spurious/duplicate read per key,
// which looks like beeps. Try SEND_FRAME_START 0 to test that theory.
#define SEND_FRAME_START 1
#define SEND_FRAME_END   1

// CALIBRATION: when 1, closing the test switch sweeps all 8 combinations of
// {bit order, data polarity, strobe polarity} and types a labelled marker for
// each. Watch the host screen: the combo whose "n=ABCDEFG" is legible tells you
// the right settings -> then set the three #defines and turn this back to 0.
#define CALIBRATION_MODE  0

// SPLIT_CLOCK_STROBE: the decisive fix. The host's 74LS164 needs an 8-pulse bit
// clock, and $C000 bit7 (key-ready) is set by a SEPARATE once-per-byte strobe.
// 1 = send 8 bit-clocks on D4 (-> DE9 pin 5) and ONE byte-strobe on D5 (-> pin 6)
//     after the 8 bits.  ** REWIRE: D4 now DRIVES DE9 pin 5 (was a probe input). **
// 0 = old behavior (8 pulses on D5/pin 6), which makes the host read 8x/char.
#define SPLIT_CLOCK_STROBE 1

// REPLAY: on each switch closure, send the EXACT combo-7 stimulus that printed
// earlier ("7=ABCDEFG " at LSB-first / data-high / strobe-high). Use this to
// capture the known-working sequence on the analyzer and compare to a single
// char. If the host prints the text SHIFTED BY ONE (e.g. you see "=ABCDEFG "
// with the '7' missing, or each char lagging), it latches $C000 on AKD-rising
// and reads the PREVIOUS byte -> we then clock data BEFORE raising AKD.
#define REPLAY_MODE       0

#define AUTO_SEND_ON_BOOT 0  // 1 = type MESSAGE once, BOOT_DELAY_MS after power-up
#define BOOT_DELAY_MS  4000  // give the host time to finish booting first
#define CHAR_GAP_MS      90  // gap between characters (host must consume each)
// AKD->data delay. Capture shows CLOCK idles HIGH (no AKD handshake), and the
// host latches $C000 a short time after AKD rises (receiver LM556 one-shot), so
// the data must be clocked PROMPTLY after AKD - exactly as the firmware does
// (AKD at phase 0, first bit ~one tick later). Keep this 0 (or <=1 ms). A large
// value makes the host latch stale shift-register data -> nothing prints.
#define AKD_SETTLE_MS     0  // ms after AKD high before data (0 = like firmware)

// ---- Behaviour / polarity / timing knobs ------------------------------------
#define BIT_ORDER_LSB_FIRST 1   // 1 = LSB first (matches firmware). 0 = MSB first.
#define DATA_ACTIVE_HIGH    1   // 1 = logic1 -> HIGH. Set 0 if buffer inverts.
#define STROBE_ACTIVE_HIGH  1   // 1 = pulse HIGH (firmware sets P1.5 then clears)
#define AKD_ACTIVE_HIGH     1   // README: AKD idle low, high on key down.
#define FRAME_ACTIVE_HIGH   1
#define WAIT_FOR_CLOCK      0   // 1 = wait for host CLOCK high before clocking out

#define BIT_PERIOD_US     400   // per-bit period (~firmware tick). Raise to slow.
#define DATA_SETUP_US      25   // DATA stable before STROBE edge
#define STROBE_HIGH_US     10   // STROBE active width
#define FRAME_PULSE_US     10
#define DEBOUNCE_MS         8

// ---- Runtime-switchable transmission settings (init from #defines) ----------
// These three are the usual cause of "key detected but wrong character". The
// calibration sweep (below) flips them to find the combination your host wants.
bool gLSBFirst   = BIT_ORDER_LSB_FIRST;
bool gDataHigh   = DATA_ACTIVE_HIGH;
bool gStrobeHigh = STROBE_ACTIVE_HIGH;

// ---- Low-level helpers (apply polarity) -------------------------------------
static inline void dataWrite(uint8_t bit) {
  bool h = bit ? gDataHigh : !gDataHigh;
  digitalWrite(DATA_PIN, h ? HIGH : LOW);
}
static inline void akdWrite(bool on) {
  digitalWrite(AKD_PIN, (on == (bool)AKD_ACTIVE_HIGH) ? HIGH : LOW);
}
static inline void strobeIdle() {
  digitalWrite(STROBE_PIN, gStrobeHigh ? LOW : HIGH);
}
static inline void strobePulse() {
  digitalWrite(STROBE_PIN, gStrobeHigh ? HIGH : LOW);
  delayMicroseconds(STROBE_HIGH_US);
  digitalWrite(STROBE_PIN, gStrobeHigh ? LOW : HIGH);
}
static inline void bitClockPulse() {           // SPLIT: bit clock on D4 (DE9 pin 5)
  digitalWrite(BITCLK_PIN, gStrobeHigh ? HIGH : LOW);
  delayMicroseconds(STROBE_HIGH_US);
  digitalWrite(BITCLK_PIN, gStrobeHigh ? LOW : HIGH);
}
static inline void framePulse() {
  digitalWrite(FRAME_PIN, FRAME_ACTIVE_HIGH ? HIGH : LOW);
  delayMicroseconds(FRAME_PULSE_US);
  digitalWrite(FRAME_PIN, FRAME_ACTIVE_HIGH ? LOW : HIGH);
}

// ---- Send one scan-code frame, mirroring ROM 0x185-0x1FA --------------------
void sendScanCode(uint8_t code) {
  // Phase 0: line setup + AKD asserted + frame marker (original working order)
  dataWrite(0);                 // DATA low (start/setup)
  akdWrite(true);               // AKD high (any key down)
#if SEND_FRAME_START
  framePulse();                 // P1.6 pulse at frame start
#endif
  delayMicroseconds(BIT_PERIOD_US);

  // Phases 1..8: 8 data bits. Bit clock pulses once per bit.
  for (uint8_t i = 0; i < 8; i++) {
    uint8_t bitIndex = gLSBFirst ? i : (7 - i);
    dataWrite((code >> bitIndex) & 0x01);
    delayMicroseconds(DATA_SETUP_US);
#if SPLIT_CLOCK_STROBE
    bitClockPulse();            // clock the 164 on DE9 pin 5 (8 pulses)
#else
    strobePulse();              // legacy: 8 pulses on DE9 pin 6
#endif
    delayMicroseconds(BIT_PERIOD_US > DATA_SETUP_US + STROBE_HIGH_US
                      ? BIT_PERIOD_US - DATA_SETUP_US - STROBE_HIGH_US : 1);
  }

  // Phase 9: DATA back to idle/stop high
  dataWrite(1);
  delayMicroseconds(BIT_PERIOD_US);

#if SPLIT_CLOCK_STROBE
  // Byte complete: ONE strobe on DE9 pin 6 -> sets host $C000 bit7 (key ready).
  strobePulse();
#elif SEND_FRAME_END
  framePulse();
#endif
  delayMicroseconds(BIT_PERIOD_US);
}

// ASCII -> keyboard scan code (= host $C000 value): 7-bit ASCII with bit7 set.
static inline uint8_t asciiToScan(char c) { return ((uint8_t)c & 0x7F) | 0x80; }

// Send one character: assert AKD, clock the frame, release AKD (= press+release).
void sendChar(uint8_t code) {
  sendScanCode(code);          // asserts AKD high + clocks the byte
  akdWrite(false);             // release: AKD low between keystrokes
  dataWrite(1);                // DATA idle high
  delay(CHAR_GAP_MS);          // let the host's input routine consume it
}

// Type the whole MESSAGE string.
void sendMessage() {
  for (const char* p = MESSAGE; *p; p++) {
    uint8_t code = asciiToScan(*p);
    Serial.print(F("  '")); Serial.print(*p);
    Serial.print(F("' -> 0x")); Serial.println(code, HEX);
    sendChar(code);
  }
  if (APPEND_RETURN) { Serial.println(F("  <Return>")); sendChar(0x8D); }
}

// Sweep the 8 combinations of bit order / data polarity / strobe polarity.
// Types "n=ABCDEFG " with each; only the correct combo prints legibly.
void runCalibration() {
  Serial.println(F("Calibration sweep - watch the host screen for a legible 'n=ABCDEFG'."));
  for (uint8_t combo = 0; combo < 8; combo++) {
    gLSBFirst   = (combo & 0x01);   // bit0: 1 = LSB-first, 0 = MSB-first
    gDataHigh   = (combo & 0x02);   // bit1: 1 = data active-high
    gStrobeHigh = (combo & 0x04);   // bit2: 1 = strobe pulses high
    strobeIdle();
    Serial.print(F("combo ")); Serial.print((char)('0' + combo));
    Serial.print(F("  LSBfirst=")); Serial.print((char)('0' + (gLSBFirst?1:0)));
    Serial.print(F(" dataHigh="));  Serial.print((char)('0' + (gDataHigh?1:0)));
    Serial.print(F(" strobeHigh=")); Serial.println((char)('0' + (gStrobeHigh?1:0)));
    sendChar(asciiToScan((char)('0' + combo)));
    sendChar(asciiToScan('='));
    for (char c = 'A'; c <= 'G'; c++) sendChar(asciiToScan(c));
    sendChar(asciiToScan(' '));
    delay(700);
  }
  // restore configured defaults
  gLSBFirst = BIT_ORDER_LSB_FIRST; gDataHigh = DATA_ACTIVE_HIGH; gStrobeHigh = STROBE_ACTIVE_HIGH;
  strobeIdle();
  Serial.println(F("Sweep done. Set the 3 #defines to the readable combo, then CALIBRATION_MODE 0."));
}

// Replay the exact combo-7 stimulus that printed earlier: "7=ABCDEFG ".
void sendCombo7() {
  gLSBFirst = true; gDataHigh = true; gStrobeHigh = true; strobeIdle();   // combo 7
  const char* s = "7=ABCDEFG ";
  Serial.println(F("Replay combo-7: typing 7=ABCDEFG"));
  for (const char* p = s; *p; p++) {
    Serial.print(F("  '")); Serial.print(*p);
    Serial.print(F("' -> 0x")); Serial.println(asciiToScan(*p), HEX);
    sendChar(asciiToScan(*p));
  }
}

// ---- Single-key scan with debounce ------------------------------------------
bool keyDownRaw() { return digitalRead(KEY_SNS_PIN) == LOW; }  // closed = LOW

bool keyDownDebounced() {
  static bool stable = false;
  static bool last = false;
  static unsigned long tEdge = 0;
  bool now = keyDownRaw();
  if (now != last) { last = now; tEdge = millis(); }
  else if ((millis() - tEdge) >= DEBOUNCE_MS) { stable = now; }
  return stable;
}

void sendAll();   // forward declaration (defined after setup)

void setup() {
  Serial.begin(115200);

  pinMode(AKD_PIN, OUTPUT);    akdWrite(false);          // idle: no key
  pinMode(DATA_PIN, OUTPUT);   dataWrite(1);             // idle: high
  pinMode(STROBE_PIN, OUTPUT); strobeIdle();             // idle
  pinMode(FRAME_PIN, OUTPUT);  digitalWrite(FRAME_PIN, FRAME_ACTIVE_HIGH ? LOW : HIGH);
  // Hold both apple buttons RELEASED so the host doesn't drop into self-test.
  pinMode(PB0_PIN, OUTPUT);    digitalWrite(PB0_PIN, PB_RELEASED_LEVEL);
  pinMode(PB1_PIN, OUTPUT);    digitalWrite(PB1_PIN, PB_RELEASED_LEVEL);

#if SPLIT_CLOCK_STROBE
  pinMode(BITCLK_PIN, OUTPUT);            // D4 drives DE9 pin 5 (bit clock)
  digitalWrite(BITCLK_PIN, gStrobeHigh ? LOW : HIGH);   // idle
#else
  pinMode(CLOCK_PIN, INPUT_PULLUP);
#endif
  pinMode(RESET_PIN, INPUT_PULLUP);

  pinMode(KEY_GND_PIN, OUTPUT); digitalWrite(KEY_GND_PIN, LOW);  // key "ground"
  pinMode(KEY_SNS_PIN, INPUT_PULLUP);                            // key sense

  Serial.println(F("MPF-III keyboard emulator ready."));
  Serial.println(F("PB0/PB1 held released so the host boots past self-test."));
#if REPLAY_MODE
  Serial.println(F("REPLAY mode: close switch D10-D11 to send combo-7 '7=ABCDEFG'."));
#elif CALIBRATION_MODE
  Serial.println(F("CALIBRATION mode: close switch D10-D11 to sweep all 8 settings."));
#else
  Serial.println(F("Close the switch between D10 and D11 to type the message."));
#endif

#if AUTO_SEND_ON_BOOT
  delay(BOOT_DELAY_MS);          // wait for the host to finish booting
  Serial.println(F("[auto-send]"));
  sendAll();
#endif
}

// Send the configured message or single code.
void sendAll() {
#if SEND_MESSAGE
  sendMessage();
#else
  Serial.print(F("Sending 0x")); Serial.println(SINGLE_CODE, HEX);
  sendChar(SINGLE_CODE);
#endif
}

void loop() {
  static bool wasDown = false;
  bool down = keyDownDebounced();

  if (down && !wasDown) {                 // switch just closed
#if REPLAY_MODE
    sendCombo7();
#elif CALIBRATION_MODE
    runCalibration();
#else
    Serial.println(F("Test switch closed -> typing message:"));
    sendAll();
    Serial.println(F("...done. Release and re-close to repeat."));
#endif
  }
  wasDown = down;
}

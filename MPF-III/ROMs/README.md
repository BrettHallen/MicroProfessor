# ROM Dumps
These are dumps of the ROMs for the MPF-III.  My machine is the PAL version called the MPF-III/311.<br>

CRC32 checksums are appended to the filenames.<br>

A big thanks to [RetroAND and Retrolab](https://bitspassats.com) for obtaining the keyboard & MOS 1.1 ROM dumps.<br>

| ROM # | Use         | Size  | CRC32    | Notes                 |
|-------|-------------|-------|----------|-----------------------|
| U5    | Keyboard    | 2732  | 46D4227A | INS8035 MCU           |
| U20   | Video       | 2732  | 2597BC19 |                       |
| U24   | AB (MOS1.1) | 2764  | 304B62E0 | A000-BFFF             |
| U24   | AB (MOS1.3) | 2764  | 4C3ECB15 | A000-BFFF             |
| U25   | CD (MOS1.1) | 2764  | 3D507B48 | C000-DFFF             |
| U25   | CD (MOS1.3) | 2764  | FCCC5C7D | C000-DFFF             |
| U25   | CD (IIe)    | 2764  | 6A54E1AA | Modified Apple IIe    |
| U25   | CD combo    | 27128 | CF146C2F | Combined MOS1.3 & IIe |
| U26   | EF (MOS1.1) | 2764  | 71B9783D | E000-FFFF             |
| U26   | EF (MOS1.3) | 2764  | 56AFE670 | E000-FFFF             |
| U26   | EF (IIe)    | 2764  | FC3D59D8 | Original Apple IIe    |
| U26   | EF combo    | 27128 | 04EE155B | Combined MOS1.3 & IIe |

Note that my machine came with two sets of U25 & U26 ROMs - piggybacked with their enable pins switched.<br>

The top ROMs are #1 (Multitech MOS) and the bottom ROMs are #2 (Apple IIe) -  either both #1 ROMs are active or both #2 ROMs are active (enable pulled low).<br>

![Piggyback ROMs](/MPF-III/ROMs/MPF-III_ROMs_piggybacked.jpg)

I think the #1 set are Multitech's Apple 2 clone firmware.<br>

The #2 set look to be a slightly modified version of the Apple IIe ROMs:
- Bytes 0x000 to 0x00FF are empty in the original Apple IIe C000-DFFF but has some data in the Multitech version
- The E000-FFFF ROMs were almost identical with the Apple IIe ... my original had two wrong bytes resulting in "ROM:E10" error (see below)
- I have now replaced the corrupted EF#2 with the original Apple IIe and recreated the EF combo (Multitech plus Apple IIe)

## "ROM:E10" error
My machine's EF #2 ROM had only two bytes difference with the IIe ROM at offset 0x1FB6 (0xFFB6 in memory): 
```
B9 CB FF ... lda $FFCB,y
```
They should've been:
```
B9 08 FB ... lda $FB08,y
```
From the [disassembly](https://6502disassembly.com/a2-rom/Unenh_IIe_F8ROM.html):
```
fb02: 20 ff 00 ff+ DSKID           .bulk   $20,$ff,$00,$ff,$03,$ff,$3c
fb09: c1 f0 f0 ec+ TITLE           .str    “Apple ][”
...
fb65: b9 08 fb     STITLE          lda     TITLE-1,y         ;get a char
...
ffcb: 60                           rts                       ;and 'RTS' to the subroutine!
```
The code wasn't executing as the boot-up was failing during the EF self-test.  This self-test generates an 8-bit sum of all the bytes, bar the actual checksum byte, of the ROM (see Python scripts below).<br>

This self-test was failing for the ROM due to these two bytes difference, hence the "ROM:E10" error.<br>

## Python scripts
I created two Python 3 scripts to help with the ROM analysis.<br>

One script extracts possible text strings from the ROM and outputs as ASCII - this is how I discovered that the #2 ROMs were copies of the original Apple ROMs ... the EF #2 had "(c) Apple" text.

The second was to help solve the "ROM:E10" error by calculating the ROM checksum in the [same manner as the Apple does](https://github.com/GLGPrograms/appleIIe-self-test) - the checksum is actually hardcoded in the EF ROM itself at location 0x17FF/0x7FFF.<br>

Faulty ROM:
```
% python3 checksum.py DODGY_ROM.BIN

########################
# Apple 2 ROM Checksum #
#          26/Jan/2026 #
########################

>> File: DODGY_ROM.BIN
>> Size: 8192 bytes (8.0KB)

>> Computed 8-bit checksum (sum mod 256, excluding offset 0x17FF): $65
>> Expected checksum (byte at offset 0x17FF/$F7FF):                $78

!! MISMATCH: This would fail self-test (bad/corrupted ROM or wrong file).
   Difference: $13
   To fix for burning: Set byte at 0x17FF to the computed value above.
```
Good ROM:
```
########################
# Apple 2 ROM Checksum #
#          26/Jan/2026 #
########################

>> File: MPF-III_ROM_EF_U26_APPLE2E_2764_FC3D59D8.BIN
>> Size: 8192 bytes (8.0KB)

>> Computed 8-bit checksum (sum mod 256, excluding offset 0x17FF): $78
>> Expected checksum (byte at offset 0x17FF/$F7FF):                $78

   MATCH: This dump should pass the self-test (good ROM).
```


 

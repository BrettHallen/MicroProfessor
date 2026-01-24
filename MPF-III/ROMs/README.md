# ROM Dumps
These are dumps of the ROMs for the MPF-III.<br>

CRC32 checksums are appended to the filenames.<br>

A big thanks to RetroAND (and his dad) for obtaining the keyboard ROM dump.<br>

| ROM # | Use      | Size  | CRC32    | Notes     |
|-------|----------|-------|----------|-----------|
| U5    | Keyboard | 2732  | 46D4227A |           |
| U20   | Video    | 2732  | 2597BC19 |           |
| U24   | AB       | 2764  | 4C3ECB15 | A000-BFFF |
| U25   | CD #1    | 2764  | FCCC5C7D | C000-DFFF |
| U25   | CD #2    | 2764  | 6A54E1AA | Modified Apple IIe |
| U25   | CD combo | 27128 | CF146C2F |           |
| U26   | EF #1    | 2764  | 56AFE670 | E000-FFFF |
| U26   | EF #2    | 2764  | FC3D59D8 | Original Apple IIe |
| U26   | EF combo | 27128 | 04EE155B |           |

Note that my machine came with two sets of U25 & U26 ROMs - piggybacked with their enable pins switched.<br>

The top ROMs are #1 and the bottom ROMs are #2 -  either both #1 ROMs are active or both #2 ROMs are active (enable pulled low).<br>

![Piggyback ROMs](/MPF-III/ROMs/MPF-III_ROMs_piggybacked.jpg)

The #2 set look to be a slightly modified version of the Apple IIe ROMs:
- Bytes 0x000 to 0x00FF are empty in the original Apple IIe C000-DFFF but has some data in the Multitech version
- The E000-FFFF ROMs are identical with the Apple IIe ... although my original had two wrong bytes resulting in "ROM:E10" error
- I have now replaced the corrupted EF#2 with the original Apple IIe and recreated the EF combo (Multitech plus Apple IIe)

## Python scripts
I created two Python 3 scripts to help with the ROM analysis.<br>

One script extracts possible text strings from the ROM and outputs as ASCII - this is how I discovered that the #2 ROMs were copies of the original Apple ROMs ... the EF #2 had "(c) Apple" text.

The second was to help solve the "ROM:E10" error by calculating the ROM checksum in the [same manner as the Apple does](https://github.com/GLGPrograms/appleIIe-self-test) - the checksum is actually hardcoded in the EF ROM itself at location 0x17FF/0x7FFF.


 

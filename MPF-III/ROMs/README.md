# ROM Dumps
These are dumps of the ROMs for the MPF-III.<br>

CRC32 checksums are appended to the filenames.<br>

A big thanks to RetroAND (and his dad) for obtaining the keyboard ROM dump.<br>

| ROM # | Use      | Size  | CRC32    |
|-------|----------|-------|----------|
| U5    | Keyboard | 2732  | 46D4227A |
| U20   | Video    | 2732  | 2597BC19 |
| U24   | AB       | 2764  | 4C3ECB15 |
| U25   | CD set 1 | 2764  | FCCC5C7D |
| U25   | CD set 2 | 2764  | 6A54E1AA |
| U25   | CD combo | 27128 | CF146C2F |
| U26   | EF set 1 | 2764  | 56AFE670 |
| U26   | EF set 2 | 2764  | 110B1018 |
| U26   | EF combo | 27128 | E9D85C9B |

Note that my machine came with two sets of U25 & U26 ROMs - piggybacked with their enable pins switched.<br>

The top ROMs are #1 and the bottom ROMs are #2 -  either both #1 ROMs are active or both #2 ROMs are active (enable pulled low).<br>

![Piggyback ROMs](/ROMs/MPF-III_ROMs_piggybacked.jpg)

One set works whilst the other halts with error "E10".  Further investigation required.<br>

I'm not sure which one is the corrupt one, yet.<br>

I have combined them into a 27128 to clean up the wiring a little.<br>


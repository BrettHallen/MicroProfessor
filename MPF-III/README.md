# Multitech Micro Professor MPF-III
The MPF-III was Multitech's (later Acer) second Apple 2 clone, coming after the MPF-II.<br>

My example is a PAL model MPF-III/311.  The NTSC model is the MPF-III/310.<br>

Unfortunatley mine came without a keyboard which means it's not usable because:
- It's a custom keyboard using a serial protocol via a DE9 connector
- The schematics have been scrubbed from the Internet (Archive)
- You need a keyboard to do anything

I do know the DE9 interface pin out and am currently trying to reverse engineer the protocol.  I also know the scan codes and keyboard layout (but not keyboard matrix) from the available documentation.<br>

I do also have a dump of the MCS-48 firmware in the keyboard.<br>

My example actually has dual ROMs that can be switched: it has Multitech's original Apple 2 clone firmware plus an almost exact copy of the Apple IIe firmware.<br>

## [Documentation](/MPF-III/Documentation)
Copies of the MPF-III documentation (available on Archive) just in case they get disappeared from there:
- BASIC Programming Manual
- Operating Manual
- Reference Manual

## [Images](/MPF-III/Images)
Images of my MPF-III/311 machine's inards.

## [Keyboard](/MPF-III/Keyboard)
My in-progress attempt to develop a home brew replacement for the original Multitech keyboard.<br>

The keyboard looks to be similar to the Multitech AccuFeel so this is perhaps a possible replacment, if one of those could be found of course.

## [ROMs](/MPF-III/ROMs)
Dumps of the ROMs from my machine, plus also some analysis of the keyboard microcontroller code and maybe other parts that differ from a standard Apple IIe.


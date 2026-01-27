# Multitech Micro Professor MPF-III
The MPF-III was Multitech's (later Acer) Apple IIe clone, coming after the MPF-II Apple ][ clone.<br>

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
- Operating Manual (working on trying to reduce my 190MB PDF copy)
- Reference Manual (working on trying to reduce my 190MB PDF copy)

## [Images](/MPF-III/Images)
Images of my MPF-III/311 machine's inards.

## [Keyboard](/MPF-III/Keyboard)
My in-progress attempt to develop a home brew replacement for the original Multitech keyboard.<br>

The keyboard looks to be similar to the Multitech AccuFeel so this is perhaps a possible replacment, if one of those could be found of course.

## [Switchable Firmware](/MPF-III/MPF-III_Switchable_ROM)
Small PCB to add the ability to switch between Multitech's original firmware (boots to "MPF-III") and the actual Apple //e firmware (boots to "APPLE ][".<br>

Takes two 27128 EPROMs (one for combined CD and one for combined EF) which are switched via the A13 address line.<br>

![Switchable ROM PCB 3D](/MPF-III/MPF-III_Switchable_ROM/MPF-III_Switchable_ROM_3D.png)

## [ROMs](/MPF-III/ROMs)
Dumps of the ROMs from my machine (MOS 1.3) and RetroAND's (MOS 1.1), plus also some analysis of the keyboard microcontroller code and maybe other parts that differ from a standard Apple IIe.<br>

A big thanks to [RetroAND and Retrolab](https://bitspassats.com/index.php/Main_Page) for getting the keyboard controller ROM dumped!

## [PALs](/MPF-III/PALs)
Dumps of the PALs courtesy of [RetroAND and Retrolab](https://bitspassats.com/index.php/Main_Page).

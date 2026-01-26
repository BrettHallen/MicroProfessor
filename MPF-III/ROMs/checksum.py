#!/usr/bin/env python3
"""
Apple IIe self-test compatible 8-bit ROM checksum calculator
(for E10/EF ROM dumps)

Computes the 8-bit sum (mod 256) of all bytes except the checksum byte at offset 0x17FF ($F7FF address).
Compares to the stored expected value at that offset.
For a good dump, computed == expected.

Usage:
    python3 checksum.py yourfile.bin

Brett Hallen, 26/Jan/2026
"""

import sys
import os

def calculate_8bit_checksum(filepath: str, checksum_offset: int = 0x17FF) -> tuple:
    try:
        with open(filepath, "rb") as f:
            data = f.read()
    except Exception as e:
        print(f"!! Error reading file {filepath}: {e}", file=sys.stderr)
        sys.exit(1)

    if len(data) != 8192:
        print("!! Warning: File is not 8 KB (8192 bytes) — may not be an E10/EF ROM dump.")

    expected = data[checksum_offset] if len(data) > checksum_offset else 0  # Stored checksum byte

    total = 0
    for i, byte in enumerate(data):
        if i == checksum_offset:  # Skip the checksum byte itself
            continue
        total = (total + byte) & 0xFF  # 8-bit add with wrap (mod 256)

    return total, expected

def main():
    print("\n########################")
    print("# Apple 2 ROM Checksum #")
    print("#          26/Jan/2026 #")
    print("########################\n")

    if len(sys.argv) < 2:
        print("Usage: python3 checksum.py <filename.bin>")
        sys.exit(1)

    filepath = sys.argv[1]

    if not os.path.isfile(filepath):
        print(f"!! Error: '{filepath}' is not a file or does not exist.")
        sys.exit(1)

    size = os.path.getsize(filepath)
    print(f">> File: {filepath}")
    print(f">> Size: {size} bytes ({size / 1024:.1f}KB)\n")

    computed, expected = calculate_8bit_checksum(filepath)

    print(f">> Computed 8-bit checksum (sum mod 256, excluding offset 0x17FF): ${computed:02X}")
    print(f">> Expected checksum (byte at offset 0x17FF/$F7FF):                ${expected:02X}")
    print()

    if computed == expected:
        print("   MATCH: This dump should pass the self-test (good ROM).")
    else:
        print("!! MISMATCH: This would fail self-test (bad/corrupted ROM or wrong file).")
        print(f"   Difference: ${(expected - computed) & 0xFF:02X}")
        print("   To fix for burning: Set byte at 0x17FF to the computed value above.")

    print()

if __name__ == "__main__":
    main()
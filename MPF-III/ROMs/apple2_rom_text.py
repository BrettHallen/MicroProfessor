import sys

def is_apple2_printable(b):
    """
    Returns True if the byte, after masking to 7 bits, is considered a printable
    Apple II text character (typically 0x20–0x7E, space to ~).
    Control characters (0x00–0x1F) and DEL (0x7F) usually not part of strings.
    """
    c = b & 0x7F
    return 0x20 <= c <= 0x7E


def extract_apple2_strings(filename, min_length=4):
    """
    Extract text strings from an Apple II ROM file.
    Only considers sequences of bytes that map to printable Apple II characters
    (after high-bit masking). Outputs starting offset in hex + string.
    """
    try:
        with open(filename, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)

    strings = []
    i = 0
    n = len(data)

    while i < n:
        if is_apple2_printable(data[i]):
            start = i
            chars = []

            while i < n and is_apple2_printable(data[i]):
                c = data[i] & 0x7F
                chars.append(chr(c))
                i += 1

            length = i - start
            if length >= min_length:
                text = ''.join(chars)
                strings.append((start, text))
        else:
            i += 1

    return strings


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python extract_apple2_strings.py <romfile> [min_length]")
        print("   example: python extract_apple2_strings.py apple2e.rom 5")
        sys.exit(1)

    filename = sys.argv[1]
    min_length = 4

    if len(sys.argv) >= 3:
        try:
            min_length = int(sys.argv[2])
            if min_length < 1:
                min_length = 1
        except ValueError:
            print("Warning: invalid min_length, using default 4")

    found = extract_apple2_strings(filename, min_length)

    if not found:
        print("No text strings found (minimum length =", min_length, ")")
        sys.exit(0)

    print(f"Found {len(found)} text string(s) (min length {min_length}):\n")

    for offset, text in found:
        print(f"0x{offset:04X}:  {text!r}")
        # Alternative styles you might prefer:
        # print(f"0x{offset:04X}  {text}")
        # print(f"[{offset:04X}h]  {text}")
# BlazeBinary

## Hex Dump Utilities

_Last updated: February 2025_

BlazeBinary provides hex dump utilities for debugging and inspecting binary data. These utilities are particularly useful when debugging encoding/decoding issues, analyzing frame structures, or inspecting corrupted data.

## Overview

The `HexDump` enum provides several methods for formatting binary data in hexadecimal format:

- **`dump(_:bytesPerLine:showOffset:)`** - Full hex dump with offsets and ASCII representation
- **`dumpCompact(_:)`** - Compact hex string without formatting
- **`dump(_:prefix:bytesPerLine:)`** - Custom formatted hex dump with prefix

## Usage

### Basic Hex Dump

```swift
import BlazeBinary

let data = Data([0x01, 0x02, 0x03, 0x41, 0x42, 0x43])
print(HexDump.dump(data))
```

Output:
```
00000000  01 02 03 41 42 43                          |...ABC|
```

### Full Hex Dump with Offsets

```swift
let largeData = Data(0..<256)
print(HexDump.dump(largeData))
```

Output:
```
00000000  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  |................|
00000010  10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F  |................|
...
```

### Compact Format

```swift
let data = Data([0xFF, 0xFE, 0xFD])
print(HexDump.dumpCompact(data))
// Output: "FF FE FD"
```

### Custom Formatting

```swift
let data = Data([0x01, 0x02, 0x03])
print(HexDump.dump(data, prefix: "  ", bytesPerLine: 8))
```

Output:
```
  00000000  01 02 03                                    |...|
```

## Integration with Tests

Hex dump utilities are automatically integrated into test failures. When a test assertion fails involving binary data, the hex dump is printed to help diagnose the issue.

Example test output:
```
XCTAssertEqual failed: ("Optional(3 bytes)") is not equal to ("Optional(3 bytes)")
Hex dump of actual:
00000000  01 02 03                                    |...|
Hex dump of expected:
00000000  01 02 04                                    |...|
```

## Use Cases

1. **Debugging Encoding Issues**: Inspect encoded data to verify correctness
2. **Frame Analysis**: Analyze frame structure and headers
3. **Corruption Detection**: Identify corrupted bytes in test failures
4. **Protocol Development**: Visualize binary protocol messages
5. **Performance Analysis**: Inspect data structures for optimization opportunities

## Format Details

The hex dump format follows standard conventions:

- **Offset**: 8-digit hexadecimal byte offset (e.g., `00000000`)
- **Hex Bytes**: Two-digit hexadecimal representation, space-separated
- **ASCII**: Printable ASCII characters (32-126), non-printable shown as `.`
- **Line Width**: Default 16 bytes per line (configurable)

## Related Documents

- [SPECIFICATION.md](SPECIFICATION.md) - Binary format specification
- [FRAME_PROTOCOL.md](FRAME_PROTOCOL.md) - Frame format details
- [ProtocolExamples.md](ProtocolExamples.md) - Usage examples


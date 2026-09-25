# BlazeBinary C

A small C implementation of BlazeBinary for microcontrollers and other C code. It encodes and decodes the same bytes as the Swift library, and the shared golden vectors in `../Fixtures/golden/primitives.txt` prove it: the Swift tests (`Tests/BlazeBinaryTests/GoldenVectorTests.swift`) and the C tests (`tests/test_blaze_binary.c`) check the same file.

- No heap allocation, no global state, caller-owned buffers
- Every read and write is bounds checked; on error the offset is left unchanged
- Portable C99: builds for RP2040/RP2350, ESP32, STM32, Linux, macOS

It covers a subset of BlazeBinary: the fixed-width integers, `Int`, `Bool`, varints, and the schema version marker. `Data`, `String`, arrays, optionals, floats, compression, encryption, and `BlazeBinaryFrame` are not implemented.

## Build and test

```bash
make test
```

This builds with `-Wall -Wextra -Wpedantic -Werror -Wconversion` plus AddressSanitizer and UBSan, then runs every golden vector.

## Wire format

The Swift implementation is authoritative. Each rule below cites the Swift code it was taken from (`Sources/BlazeBinary/`).

| Type | Wire bytes | Swift source |
|---|---|---|
| `UInt8` | 1 byte, raw | `BlazeBinaryEncoder.encode(_: UInt8)`, `BlazeBinaryDecoder.decodeUInt8()` |
| `UInt16` | 2 bytes, big-endian | `encode(_: UInt16)`, `decodeUInt16()` |
| `UInt32` | 4 bytes, big-endian | `encode(_: UInt32)`, `decodeUInt32()` |
| `UInt64` | 8 bytes, big-endian | `encode(_: UInt64)`, `decodeUInt64()` |
| `Int` | zigzag `(v << 1) ^ (v >> 63)` on Int64, then unsigned varint, 1 to 10 bytes | `encode(_: Int)`, `decodeInt()` |
| varint | unsigned LEB128: 7 bits per byte, low bits first, high bit set on every byte except the last | `encodeVarint(_:)`, `decodeVarint()` |
| `Bool` | `00` or `01`; any other byte is an error | `encode(_: Bool)`, `decodeBool()` |
| `Float` / `Double` | IEEE 754 bit pattern as big-endian `UInt32` / `UInt64` | `encode(_: Float)`, `encode(_: Double)` (not in C) |
| `Data` | varint length, then the bytes | `encode(_: Data)`, `decodeData()` (not in C) |
| `String` | varint UTF-8 byte count, then the UTF-8 bytes | `encode(_: String)`, `decodeString()` (not in C) |
| optional | `Bool` present flag, then the value if present | `encode<T>(_: T?)`, `decodeOptional(_:)` (not in C) |
| array | varint count, then each element | `encode<T>(_: [T])`, `decodeArray(_:)` (not in C) |

There are no field names or tags. A record is its fields written in order, so both sides must agree on the field order.

### Schema version marker

- Version 1 is the default and writes no marker at all (`BlazeBinaryEncoder.encodedData()`).
- Versions 2 to 127 are written as `FE <version>` in front of the record.
- When decoding, the marker is recognised only if the record is longer than 2 bytes, byte 0 is `FE`, and byte 1 is 2 to 127 (`BlazeBinaryDecoder.init(data:maxAllowedLength:)`). Otherwise the record is treated as version 1 and nothing is skipped.
- `FE` is also the zigzag varint for `Int(127)`, so a version 1 record whose first field is `Int(127)` can be misread as versioned. The Swift source documents this collision. Records that need an explicit version should either use version 2 or higher, or carry the version as an ordinary field.

### Errors

| Situation | Swift | C |
|---|---|---|
| Input ends early | `BlazeBinaryError.truncated` | `BLAZE_BINARY_EOF` |
| Varint longer than 10 bytes | `invalidVarint` | `BLAZE_BINARY_INVALID` |
| Bool byte other than `00`/`01` | `decodeFailed` | `BLAZE_BINARY_INVALID` |
| Writer out of space | n/a (Swift grows) | `BLAZE_BINARY_BUFFER_TOO_SMALL` |
| Schema version outside 2 to 127 | `precondition` failure | `BLAZE_BINARY_UNSUPPORTED_VERSION` |

### Where C is stricter than Swift

The C decoder rejects two kinds of input that no encoder produces but the Swift decoder currently accepts. Both are recorded as `strict` vectors in the golden file:

1. **Overlong varints**, such as `80 00` for zero. Swift decodes them; C returns `BLAZE_BINARY_INVALID`.
2. **A 10th varint byte above `01`**. Swift silently drops the bits that do not fit in 64 bits; C returns `BLAZE_BINARY_OVERFLOW`.

Anything either encoder writes decodes identically on both sides.

## API

```c
void blaze_binary_reader_init(blaze_binary_reader_t *r, const uint8_t *data, size_t length);
void blaze_binary_writer_init(blaze_binary_writer_t *w, uint8_t *data, size_t capacity);
size_t blaze_binary_reader_remaining(const blaze_binary_reader_t *r);

blaze_binary_result_t blaze_binary_write_u8 / _u16 / _u32 / _u64 (blaze_binary_writer_t *w, value);
blaze_binary_result_t blaze_binary_read_u8  / _u16 / _u32 / _u64 (blaze_binary_reader_t *r, *out);
blaze_binary_result_t blaze_binary_write_int(blaze_binary_writer_t *w, int64_t value);
blaze_binary_result_t blaze_binary_read_int(blaze_binary_reader_t *r, int64_t *out);
blaze_binary_result_t blaze_binary_write_varint(blaze_binary_writer_t *w, uint64_t value);
blaze_binary_result_t blaze_binary_read_varint(blaze_binary_reader_t *r, uint64_t *out);
blaze_binary_result_t blaze_binary_write_bool(blaze_binary_writer_t *w, bool value);
blaze_binary_result_t blaze_binary_read_bool(blaze_binary_reader_t *r, bool *out);
blaze_binary_result_t blaze_binary_write_schema_version(blaze_binary_writer_t *w, uint8_t version);
blaze_binary_result_t blaze_binary_read_schema_version(blaze_binary_reader_t *r, uint8_t *version);
```

See `include/blaze_binary.h` for the full contract.

## Using it in another project

Copy `include/blaze_binary.h` and `src/blaze_binary.c`, and record the BlazeBinary commit you copied from. Run your own copy against `Fixtures/golden/primitives.txt` to make sure it has not drifted.

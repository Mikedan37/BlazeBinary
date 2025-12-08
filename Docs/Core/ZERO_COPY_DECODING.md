# BlazeBinary

## Zero-Copy Struct Decoding

_Last updated: February 2025_

BlazeBinary Protocol v1.1 introduces experimental zero-copy struct decoding, inspired by Cap'n Proto's approach. This feature allows direct memory mapping of fixed-width primitive structs onto the underlying data buffer, eliminating copies and allocations.

## Overview

Zero-copy decoding maps struct memory directly onto the `Data` buffer, providing:

- **Zero allocations**: No memory copies for fixed-width types
- **Maximum performance**: Direct memory access
- **Strict safety**: Alignment checks, bounds validation, fixed-layout constraints

## Restrictions

Zero-copy decoding has strict requirements:

1. **Fixed-width primitives only**: Structs must contain only:
   - `UInt8`, `UInt16`, `UInt32`, `UInt64`
   - `Int8`, `Int16`, `Int32`, `Int64`
   - `Float`, `Double`
   - `Bool` (as 1 byte)

2. **No variable-length types**: Cannot contain:
   - `String`
   - `Data`
   - Arrays
   - Optional types
   - Nested structs (unless also zero-copy compatible)

3. **Alignment requirements**: Struct must be properly aligned for the target platform

4. **No padding**: Struct layout must match expected byte layout exactly

## API

```swift
// Decode a zero-copy struct
let decoder = BlazeBinaryDecoder(data: encodedData)
let structValue = try decoder.decodeZeroCopy(MyStruct.self)
```

## Safety Guarantees

The decoder enforces:

- **Bounds checking**: Verifies sufficient data is available
- **Alignment checking**: Ensures struct alignment matches platform requirements
- **Layout validation**: Confirms struct layout matches expected format
- **Type constraints**: Only allows fixed-width primitive types

## Example

```swift
struct Point: BlazeBinaryCodable {
    let x: Float
    let y: Float
    
    // Zero-copy compatible: only fixed-width primitives
}

let decoder = BlazeBinaryDecoder(data: encodedData)
let point = try decoder.decodeZeroCopy(Point.self) // Zero-copy decode
```

## Limitations

- **Platform-specific**: Alignment requirements vary by platform
- **No schema evolution**: Fixed layout cannot change
- **Experimental**: API may change in future versions

## Related Documents

- [SPECIFICATION.md](SPECIFICATION.md) - Encoding format
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture


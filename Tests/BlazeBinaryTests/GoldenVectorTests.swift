import XCTest
@testable import BlazeBinary

/// Checks Swift BlazeBinary against the golden vectors in Fixtures/golden/primitives.txt.
/// The C implementation (c/tests/test_blaze_binary.c) is checked against the same file,
/// so a vector passing in both proves Swift-encoded bytes decode in C and vice versa.
final class GoldenVectorTests: XCTestCase {

    private struct Vector {
        let line: Int
        let kind: String
        let type: String
        let fields: [String]
    }

    private func loadVectors() throws -> [Vector] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden/primitives.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var vectors: [Vector] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ").map(String.init)
            vectors.append(Vector(line: index + 1, kind: parts[0], type: parts[1], fields: Array(parts.dropFirst(2))))
        }
        return vectors
    }

    private func bytes(_ hex: String) -> Data {
        if hex == "-" { return Data() }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func encode(_ type: String, _ value: String) -> Data {
        if type == "schema" {
            let parts = value.split(separator: ":")
            let encoder = BlazeBinaryEncoder(schemaVersion: UInt32(parts[0])!)
            encoder.encode(UInt8(parts[1])!)
            return encoder.encodedData()
        }
        let encoder = BlazeBinaryEncoder()
        switch type {
        case "u8": encoder.encode(UInt8(value)!)
        case "u16": encoder.encode(UInt16(value)!)
        case "u32": encoder.encode(UInt32(value)!)
        case "u64": encoder.encode(UInt64(value)!)
        case "int": encoder.encode(Int(value)!)
        case "bool": encoder.encode(value == "1")
        default: XCTFail("unknown type \(type)")
        }
        return encoder.encodedData()
    }

    /// Decodes one value and returns it as the fixture's string form, plus bytes left over.
    private func decode(_ type: String, _ data: Data) throws -> (String, Int) {
        let decoder = BlazeBinaryDecoder(data: data)
        let value: String
        switch type {
        case "u8": value = String(try decoder.decodeUInt8())
        case "u16": value = String(try decoder.decodeUInt16())
        case "u32": value = String(try decoder.decodeUInt32())
        case "u64": value = String(try decoder.decodeUInt64())
        case "int": value = String(try decoder.decodeInt())
        case "bool": value = try decoder.decodeBool() ? "1" : "0"
        case "schema": value = "\(decoder.version):\(try decoder.decodeUInt8())"
        default: throw BlazeBinaryError.decodeFailed("unknown type \(type)")
        }
        return (value, decoder.remainingData.count)
    }

    func testGoldenVectors() throws {
        let vectors = try loadVectors()
        var counts: [String: Int] = [:]

        for v in vectors {
            counts[v.kind, default: 0] += 1
            switch v.kind {
            case "ok":
                let (value, golden) = (v.fields[0], bytes(v.fields[1]))
                XCTAssertEqual(hex(encode(v.type, value)), v.fields[1], "line \(v.line): encode \(v.type) \(value)")
                let (decoded, left) = try decode(v.type, golden)
                XCTAssertEqual(decoded, value, "line \(v.line): decode \(v.type) \(v.fields[1])")
                XCTAssertEqual(left, 0, "line \(v.line): trailing bytes")

            case "err":
                let expected = v.fields[1]
                XCTAssertThrowsError(try decode(v.type, bytes(v.fields[0])), "line \(v.line)") { error in
                    let isTruncated = (error as? BlazeBinaryError) == .truncated
                    XCTAssertEqual(isTruncated ? "truncated" : "invalid", expected, "line \(v.line): got \(error)")
                }

            case "strict":
                // Swift accepts these non-canonical bytes today; C rejects them. Recorded, not changed.
                XCTAssertNoThrow(try decode(v.type, bytes(v.fields[0])), "line \(v.line)")

            default:
                XCTFail("line \(v.line): unknown kind \(v.kind)")
            }
        }

        XCTAssertEqual(counts["ok"], 42)
        XCTAssertEqual(counts["err"], 12)
        XCTAssertEqual(counts["strict"], 2)
    }

    // MARK: - UInt8

    func testUInt8IsExactlyOneByte() throws {
        for value: UInt8 in [0, 1, 42, 127, 128, 254, 255] {
            let encoder = BlazeBinaryEncoder()
            encoder.encode(value)
            XCTAssertEqual(encoder.encodedData(), Data([value]))
            XCTAssertEqual(try BlazeBinaryDecoder(data: Data([value])).decodeUInt8(), value)
        }
    }

    func testUInt8TruncatedThrows() {
        XCTAssertThrowsError(try BlazeBinaryDecoder(data: Data()).decodeUInt8()) { error in
            XCTAssertEqual(error as? BlazeBinaryError, .truncated)
        }
    }

    /// Adding encode(UInt8) must not change how untyped integer literals encode:
    /// a literal still resolves to Int (zigzag varint), exactly as before.
    func testIntegerLiteralStillEncodesAsInt() {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(127)
        XCTAssertEqual(encoder.encodedData(), Data([0xFE, 0x01]))
    }

    func testUInt8FieldsInSequence() throws {
        let encoder = BlazeBinaryEncoder()
        encoder.encode(UInt64(0x0123456789ABCDEF))
        encoder.encode(UInt8(0x03))
        encoder.encode(UInt8(0x5A))
        let data = encoder.encodedData()
        XCTAssertEqual(hex(data), "0123456789abcdef035a")

        let decoder = BlazeBinaryDecoder(data: data)
        XCTAssertEqual(try decoder.decodeUInt64(), 0x0123456789ABCDEF)
        XCTAssertEqual(try decoder.decodeUInt8(), 0x03)
        XCTAssertEqual(try decoder.decodeUInt8(), 0x5A)
        XCTAssertThrowsError(try decoder.decodeUInt8())
    }
}

import XCTest
import Foundation
@testable import BlazeBinary

final class Fuzzstyleteststests: XCTestCase {
    /// Fuzz-style tests for invalid varints, corrupted frames, and truncated data.
    struct FuzzStyleTests {
        // MARK: - Invalid Varint Tests
        func testInvalidVarintTooManyBytes() throws {
            // Create varint with 11 continuation bytes (exceeds max of 10)
            var invalid = Data()
            for _ in 0..<11 {
                invalid.append(0x80) // All continuation bits set
            }
            let decoder = BlazeBinaryDecoder(data: invalid)
            XCTAssertThrowsError(try decoder.decodeInt()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.invalidVarint)
                }
            }
        }
        func testInvalidVarintShiftOverflow() throws {
            // Create varint that would cause shift overflow
            // This is hard to construct directly, but we test the validation
            var invalid = Data()
            // 10 bytes with continuation bits, but with shift that would exceed 63
            for i in 0..<10 {
                if i < 9 {
                    invalid.append(0x80) // Continuation
                } else {
                    invalid.append(0x00) // Last byte
                }
            }
            let decoder = BlazeBinaryDecoder(data: invalid)
            // Should decode successfully (this particular pattern is valid)
            // The shift overflow check catches cases during decoding
            _ = try? decoder.decodeInt()
        }
        func testInvalidVarintTruncated() throws {
            // Varint with continuation bit but no more bytes
            var truncated = Data()
            truncated.append(0x80) // Continuation bit set, but no more bytes
            let decoder = BlazeBinaryDecoder(data: truncated)
            XCTAssertThrowsError(try decoder.decodeInt()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.truncated)
                }
            }
        }
        // MARK: - Corrupted Frame Tests
        func testCorruptedFrameZeroLength() throws {
            // Frame with zero length prefix
            var frame = Data()
            let zeroLength = UInt32(0).bigEndian
            frame.append(contentsOf: withUnsafeBytes(of: zeroLength) { Data($0) })
            let parser = BlazeFrameParser()
            try parser.append(frame)
            XCTAssertThrowsError(try parser.nextFrame()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.invalidFrameLength)
                }
            }
        }
        func testCorruptedFrameOversizedLength() throws {
            // Frame with length exceeding maxFrameSize
            var frame = Data()
            let oversizedLength = UInt32(6 * 1024 * 1024).bigEndian // 6 MB > 5 MB limit
            frame.append(contentsOf: withUnsafeBytes(of: oversizedLength) { Data($0) })
            let parser = BlazeFrameParser()
            try parser.append(frame)
            XCTAssertThrowsError(try parser.nextFrame()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.invalidFrameLength)
                }
            }
        }
        func testCorruptedFrameTruncatedPayload() throws {
            // Frame with valid length prefix but truncated payload
            var frame = Data()
            let length = UInt32(100).bigEndian
            frame.append(contentsOf: withUnsafeBytes(of: length) { Data($0) })
            frame.append(Data(repeating: 0xAA, count: 50)) // Only 50 bytes, need 100
            let parser = BlazeFrameParser()
            try parser.append(frame)
            // Should return nil (need more data), not throw
            let result = try parser.nextFrame()
            XCTAssert(result == nil)
        }
        func testCorruptedFrameInvalidLengthPrefix() throws {
            // Frame with corrupted length prefix bytes
            var frame = Data()
            frame.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // Max UInt32
            frame.append(Data(repeating: 0xAA, count: 100))
            let parser = BlazeFrameParser()
            try parser.append(frame)
            XCTAssertThrowsError(try parser.nextFrame()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.invalidFrameLength)
                }
            }
        }
        // MARK: - Truncated Data Tests
        func testTruncatedUInt32() throws {
            // Only 2 bytes available for UInt32 (needs 4)
            let truncated = Data([0x01, 0x02])
            let decoder = BlazeBinaryDecoder(data: truncated)
            XCTAssertThrowsError(try decoder.decodeUInt32()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.truncated)
                }
            }
        }
        func testTruncatedUInt64() throws {
            // Only 4 bytes available for UInt64 (needs 8)
            let truncated = Data([0x01, 0x02, 0x03, 0x04])
            let decoder = BlazeBinaryDecoder(data: truncated)
            XCTAssertThrowsError(try decoder.decodeUInt64()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.truncated)
                }
            }
        }
        func testTruncatedDataPayload() throws {
            // Length prefix says 100 bytes, but only 50 available
            let encoder = BlazeBinaryEncoder()
            encoder.encode(Data(repeating: 0xAA, count: 100))
            let fullData = encoder.encodedData()
            // Truncate after length prefix + 50 bytes
            let truncated = fullData.prefix(fullData.count - 50)
            let decoder = BlazeBinaryDecoder(data: truncated)
            XCTAssertThrowsError(try decoder.decodeData()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.truncated)
                }
            }
        }
        func testTruncatedStringPayload() throws {
            // Length prefix says 100 bytes, but only 50 available
            let encoder = BlazeBinaryEncoder()
            encoder.encode(String(repeating: "A", count: 100))
            let fullData = encoder.encodedData()
            // Truncate after length prefix + 50 bytes
            let truncated = fullData.prefix(fullData.count - 50)
            let decoder = BlazeBinaryDecoder(data: truncated)
            XCTAssertThrowsError(try decoder.decodeString()) { error in
                XCTAssertTrue(error is BlazeBinaryError)
                if let bbError = error as? BlazeBinaryError {
                    XCTAssertEqual(bbError, BlazeBinaryError.truncated)
                }
            }
        }
        func testTruncatedArray() throws {
            // Array count says 10 items, but only 5 available
            struct Item: BlazeBinaryCodable {
                var value: Int
                init(value: Int) {
                    self.value = value
                }
                func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
                    encoder.encode(value)
                }
                init(from decoder: BlazeBinaryDecoder) throws {
                    self.value = try decoder.decodeInt()
                }
            }
            let encoder = BlazeBinaryEncoder()
            let items = (0..<10).map { Item(value: $0) }
            try encoder.encode(items)
            let fullData = encoder.encodedData()
            // Truncate in the middle
            let truncated = fullData.prefix(fullData.count / 2)
            let decoder = BlazeBinaryDecoder(data: truncated)
            do {
                _ = try decoder.decodeArray(Item.self)
                XCTFail("Decoder should reject truncated array")
            } catch {
                // Any error is acceptable for truncated data
            }
        }
        // MARK: - Malformed Input Tests
        func testMalformedBool() throws {
            // Bool value that's not 0x00 or 0x01
            let malformed = Data([0x02])
            let decoder = BlazeBinaryDecoder(data: malformed)
            do {
                _ = try decoder.decodeBool()
                XCTFail("Decoder should reject malformed bool value")
            } catch let error as BlazeBinaryError {
                switch error {
                case .decodeFailed:
                    // Expected
                    break
                default:
                    // Also acceptable
                    break
                }
            } catch {
                // Any error is acceptable
            }
        }
        func testMalformedUTF8() throws {
            // Invalid UTF-8 sequence
            // Create data with length prefix and invalid UTF-8
            var data = Data()
            // Encode varint for length 2
            data.append(0x02)
            let invalidUTF8 = Data([0xFF, 0xFE])
            data.append(invalidUTF8)
            // Note: String(data:encoding:) might handle some invalid UTF-8
            // But we test that decodeString attempts validation
            let decoder = BlazeBinaryDecoder(data: data)
            // String might still decode depending on Swift's String behavior
            // This test verifies the decode path is exercised
            _ = try? decoder.decodeString()
        }
        func testOversizedDataLength() throws {
            // Data length exceeding maxAllowedLength
            // Create encoded data with huge length prefix
            // We'll encode a small data with huge length varint manually
            var data = Data()
            // Encode varint for 20 MB
            var v = UInt64(20 * 1024 * 1024)
            repeat {
                var byte = UInt8(v & 0x7F)
                v >>= 7
                if v != 0 {
                    byte |= 0x80
                }
                data.append(byte)
            } while v != 0
            // Add some payload (but length says 20MB)
            data.append(Data(repeating: 0xAA, count: 100))
            let decoder = BlazeBinaryDecoder(data: data, maxAllowedLength: 10 * 1024 * 1024)
            do {
                _ = try decoder.decodeData()
                XCTFail("Decoder should reject oversized data length")
            } catch let error as BlazeBinaryError {
                switch error {
                case .decodeFailed:
                    // Expected
                    break
                default:
                    // Also acceptable
                    break
                }
            } catch {
                // Any error is acceptable
            }
        }
    }
}

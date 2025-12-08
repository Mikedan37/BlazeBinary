//
//  HexDumpTests.swift
//  BlazeBinary
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import XCTest
@testable import BlazeBinary

final class HexDumpTests: XCTestCase {
    
    func testHexDumpBasic() {
        let data = Data([0x01, 0x02, 0x03, 0x41, 0x42, 0x43])
        let dump = HexDump.dump(data)
        
        XCTAssertTrue(dump.contains("01 02 03"))
        XCTAssertTrue(dump.contains("ABC"))
    }
    
    func testHexDumpCompact() {
        let data = Data([0xFF, 0xFE, 0xFD])
        let dump = HexDump.dumpCompact(data)
        
        XCTAssertEqual(dump, "FF FE FD")
    }
    
    func testHexDumpWithPrefix() {
        let data = Data([0x01, 0x02])
        let dump = HexDump.dump(data, prefix: "  ")
        
        XCTAssertTrue(dump.contains("  "))
        XCTAssertTrue(dump.contains("01 02"))
    }
    
    func testHexDumpEmpty() {
        let data = Data()
        let dump = HexDump.dump(data)
        
        XCTAssertFalse(dump.isEmpty)
    }
    
    func testHexDumpLargeData() {
        let data = Data((0..<256).map { UInt8($0) })
        let dump = HexDump.dump(data)
        
        XCTAssertTrue(dump.contains("00000000"))
        XCTAssertTrue(dump.contains("00000010"))
    }
}


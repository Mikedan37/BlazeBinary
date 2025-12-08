//
// FileSender.swift
// BlazeBinary Examples
//
// Chunked file transfer example using incremental decoding
// and streaming compression
//

import Foundation
import BlazeBinary

/// File sender using chunked transfer with incremental decoding.
///
/// This example demonstrates:
/// - Chunked file transfer
/// - Incremental frame parsing
/// - Streaming compression
/// - Large payload handling
///
/// Usage:
/// ```swift
/// let sender = FileSender()
/// try sender.sendFile(at: fileURL, chunkSize: 64 * 1024)
/// ```
public class FileSender {
    private let chunkSize: Int
    
    public init(chunkSize: Int = 64 * 1024) {
        self.chunkSize = chunkSize
    }
    
    /// Sends a file in chunks.
    /// - Parameters:
    ///   - fileURL: URL of file to send
    ///   - compressionMode: Optional compression mode
    /// - Returns: Array of frame data (one per chunk)
    /// - Throws: `BlazeBinaryError` if encoding fails
    public func sendFile(
        at fileURL: URL,
        compressionMode: CompressionMode = .none
    ) throws -> [Data] {
        let fileData = try Data(contentsOf: fileURL)
        return try sendFileData(fileData, compressionMode: compressionMode)
    }
    
    /// Sends file data in chunks.
    /// - Parameters:
    ///   - fileData: File data to send
    ///   - compressionMode: Optional compression mode
    /// - Returns: Array of frame data (one per chunk)
    /// - Throws: `BlazeBinaryError` if encoding fails
    public func sendFileData(
        _ fileData: Data,
        compressionMode: CompressionMode = .none
    ) throws -> [Data] {
        var frames: [Data] = []
        
        // Send file metadata first
        let metadata = FileMetadata(
            fileName: "file.bin",
            totalSize: fileData.count,
            chunkCount: (fileData.count + chunkSize - 1) / chunkSize
        )
        
        let metadataEncoder = BlazeBinaryEncoder()
        try metadataEncoder.encode(metadata)
        let metadataFrame = try BlazeFrameEncoder.encodeFrame(
            metadataEncoder.encodedData(),
            compressionMode: compressionMode
        )
        frames.append(metadataFrame)
        
        // Send file in chunks
        var offset = 0
        var chunkIndex = 0
        
        while offset < fileData.count {
            let chunkEnd = min(offset + chunkSize, fileData.count)
            let chunk = fileData.subdata(in: offset..<chunkEnd)
            
            // Encode chunk
            let chunkEncoder = BlazeBinaryEncoder()
            chunkEncoder.encode(chunkIndex)
            chunkEncoder.encode(chunk)
            
            let chunkFrame = try BlazeFrameEncoder.encodeFrame(
                chunkEncoder.encodedData(),
                compressionMode: compressionMode
            )
            frames.append(chunkFrame)
            
            offset = chunkEnd
            chunkIndex += 1
        }
        
        return frames
    }
}

/// File receiver using incremental decoding.
public class FileReceiver {
    private var parser: BlazeFrameParser
    private var receivedChunks: [Int: Data] = [:]
    private var metadata: FileMetadata?
    private var expectedChunks: Int = 0
    
    public init() {
        self.parser = BlazeFrameParser()
    }
    
    /// Receives a frame and processes it.
    /// - Parameter frameData: Frame data from network
    /// - Returns: `true` if file transfer is complete
    /// - Throws: `BlazeBinaryError` if decoding fails
    public func receiveFrame(_ frameData: Data) throws -> Bool {
        try parser.append(frameData)
        
        while let payload = try parser.nextFrame() {
            let decoder = BlazeBinaryDecoder(data: payload)
            
            // Check if this is metadata (first frame)
            if metadata == nil {
                metadata = try decoder.decode(FileMetadata.self)
                expectedChunks = metadata!.chunkCount
                continue
            }
            
            // Decode chunk
            let chunkIndex = try decoder.decodeInt()
            let chunkData = try decoder.decodeData()
            
            receivedChunks[chunkIndex] = chunkData
            
            // Check if all chunks received
            if receivedChunks.count == expectedChunks {
                return true // Transfer complete
            }
        }
        
        return false // More chunks needed
    }
    
    /// Reassembles the received file.
    /// - Returns: Reassembled file data
    /// - Throws: `BlazeBinaryError` if reassembly fails
    public func reassembleFile() throws -> Data {
        guard let metadata = metadata else {
            throw BlazeBinaryError.decodeFailed("Metadata not received")
        }
        
        guard receivedChunks.count == expectedChunks else {
            throw BlazeBinaryError.decodeFailed("Not all chunks received: \(receivedChunks.count)/\(expectedChunks)")
        }
        
        // Reassemble chunks in order
        var fileData = Data()
        for i in 0..<expectedChunks {
            guard let chunk = receivedChunks[i] else {
                throw BlazeBinaryError.decodeFailed("Missing chunk \(i)")
            }
            fileData.append(chunk)
        }
        
        guard fileData.count == metadata.totalSize else {
            throw BlazeBinaryError.decodeFailed("Size mismatch: \(fileData.count) != \(metadata.totalSize)")
        }
        
        return fileData
    }
}

/// File metadata structure.
struct FileMetadata: BlazeBinaryCodable {
    var fileName: String
    var totalSize: Int
    var chunkCount: Int
    
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(fileName)
        encoder.encode(totalSize)
        encoder.encode(chunkCount)
    }
    
    init(from decoder: BlazeBinaryDecoder) throws {
        self.fileName = try decoder.decodeString()
        self.totalSize = try decoder.decodeInt()
        self.chunkCount = try decoder.decodeInt()
    }
}

// MARK: - Example Usage

func runFileSenderExample() {
    print("=== BlazeBinary File Sender Example ===\n")
    
    // Create test file data
    let testFileData = Data((0..<256 * 1024).map { UInt8($0 % 256) }) // 256KB
    
    do {
        // Send file
        print("1. Sending file (256KB)...")
        let sender = FileSender(chunkSize: 64 * 1024)
        let frames = try sender.sendFileData(testFileData, compressionMode: .lz4)
        print("   Generated \(frames.count) frames")
        print("   Total size: \(frames.reduce(0) { $0 + $1.count }) bytes")
        
        // Receive file
        print("\n2. Receiving file...")
        let receiver = FileReceiver()
        var frameIndex = 0
        
        for frame in frames {
            frameIndex += 1
            let complete = try receiver.receiveFrame(frame)
            
            if complete {
                print("   ✅ All chunks received after frame \(frameIndex)")
                break
            } else {
                print("   Received frame \(frameIndex), more chunks needed...")
            }
        }
        
        // Reassemble
        print("\n3. Reassembling file...")
        let receivedData = try receiver.reassembleFile()
        print("   Reassembled size: \(receivedData.count) bytes")
        
        // Verify
        if receivedData == testFileData {
            print("   ✅ File matches original!")
        } else {
            print("   ❌ File mismatch!")
        }
        
        print("\n✅ File sender example completed successfully!")
        print("   - Chunked transfer: \(frames.count) chunks")
        print("   - Incremental decoding: Handled chunked arrival")
        print("   - Compression: LZ4 enabled")
        
    } catch {
        print("❌ Error: \(error)")
    }
}

// Run example if executed directly
if CommandLine.arguments.contains("--run-file-sender") {
    runFileSenderExample()
}


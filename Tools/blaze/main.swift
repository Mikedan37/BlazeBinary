//
//  main.swift
//  blaze
//
//  Copyright (c) 2025 Michael Danylchuk
//  MIT License
//

import Foundation
import BlazeBinary

// Minimal CLI tool for encoding JSON to BlazeBinary format
// This is a preview implementation. Full functionality will be released in a later minor version.

func printUsage() {
    print("""
    Usage: blaze encode <input.json> [--output <output.bb>]
    
    Commands:
      encode    Encode JSON file to BlazeBinary format
    
    Options:
      --output  Output file path (default: stdout as base64)
    
    Examples:
      blaze encode data.json
      blaze encode data.json --output data.bb
    """)
}

func encodeJSONToBlazeBinary(inputPath: String, outputPath: String?) throws {
    // Read JSON file
    let jsonData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
    guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        throw NSError(domain: "blaze", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON must be a dictionary"])
    }
    
    // Convert to BlazeBinary
    // Note: This is a simplified conversion. Full implementation will handle all JSON types.
    let encoder = BlazeBinaryEncoder()
    
    // Encode dictionary count
    encoder.encode(jsonObject.count)
    
    // Encode key-value pairs (sorted for determinism)
    for (key, value) in jsonObject.sorted(by: { $0.key < $1.key }) {
        encoder.encode(key)
        
        // Handle different JSON value types
        if let stringValue = value as? String {
            encoder.encode(stringValue)
        } else if let intValue = value as? Int {
            encoder.encode(intValue)
        } else if let doubleValue = value as? Double {
            encoder.encode(doubleValue)
        } else if let boolValue = value as? Bool {
            encoder.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            // Simple array encoding (preview only)
            encoder.encode(arrayValue.count)
            for item in arrayValue {
                if let str = item as? String {
                    encoder.encode(str)
                } else if let num = item as? Int {
                    encoder.encode(num)
                }
            }
        } else {
            throw NSError(domain: "blaze", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported JSON type: \(type(of: value))"])
        }
    }
    
    let encodedData = encoder.encodedData()
    
    // Write output
    if let outputPath = outputPath {
        try encodedData.write(to: URL(fileURLWithPath: outputPath))
        print("Encoded \(inputPath) → \(outputPath) (\(encodedData.count) bytes)")
    } else {
        // Output as base64 to stdout
        let base64 = encodedData.base64EncodedString()
        print(base64)
    }
}

// Main
let args = CommandLine.arguments

guard args.count >= 3 else {
    printUsage()
    exit(1)
}

let command = args[1]

switch command {
case "encode":
    let inputPath = args[2]
    var outputPath: String? = nil
    
    // Parse --output flag if present
    if let outputIndex = args.firstIndex(of: "--output"), outputIndex + 1 < args.count {
        outputPath = args[outputIndex + 1]
    }
    
    do {
        try encodeJSONToBlazeBinary(inputPath: inputPath, outputPath: outputPath)
    } catch {
        print("Error: \(error.localizedDescription)", to: &standardError)
        exit(1)
    }
    
default:
    print("Unknown command: \(command)", to: &standardError)
    printUsage()
    exit(1)
}


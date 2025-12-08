import Testing
import Foundation
@testable import BlazeBinary

/// Verification test to show encoded bytes
@Test func verify_handwriting_encoding_bytes() throws {
    // Test HandwritingContinuationRequest
    let request = HandwritingContinuationRequest(textBefore: "Hello, world")
    let encoder = BlazeBinaryEncoder()
    try encoder.encode(request)
    let requestData = encoder.encodedData()
    
    // Show encoded bytes
    let hexString = requestData.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("\n[VERIFICATION] HandwritingContinuationRequest encoded bytes:")
    print("  Input: textBefore = \"Hello, world\"")
    print("  Bytes (\(requestData.count) bytes): \(hexString)")
    
    // Verify deterministic
    let encoder2 = BlazeBinaryEncoder()
    try encoder2.encode(request)
    let requestData2 = encoder2.encodedData()
    #expect(requestData == requestData2, "Encoding must be deterministic")
    
    // Test HandwritingContinuationResponse
    let response = HandwritingContinuationResponse(predictedText: "This is a prediction")
    let encoder3 = BlazeBinaryEncoder()
    try encoder3.encode(response)
    let responseData = encoder3.encodedData()
    
    // Show encoded bytes
    let hexString2 = responseData.map { String(format: "%02X", $0) }.joined(separator: " ")
    print("\n[VERIFICATION] HandwritingContinuationResponse encoded bytes:")
    print("  Input: predictedText = \"This is a prediction\"")
    print("  Bytes (\(responseData.count) bytes): \(hexString2)")
    
    // Verify deterministic
    let encoder4 = BlazeBinaryEncoder()
    try encoder4.encode(response)
    let responseData2 = encoder4.encodedData()
    #expect(responseData == responseData2, "Encoding must be deterministic")
}


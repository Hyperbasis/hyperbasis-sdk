//
//  HBAnchorTests.swift
//  HyperbasisTests
//
//  Tests for HBAnchor model
//

import XCTest
import simd
@testable import Hyperbasis

final class HBAnchorTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithSimdTransform() {
        let transform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(1.5, 0.8, -2.0, 1)  // Position
        )

        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: transform,
            metadata: ["text": "Test"]
        )

        XCTAssertEqual(anchor.transform.count, 16)
        XCTAssertEqual(anchor.position.x, 1.5, accuracy: 0.001)
        XCTAssertEqual(anchor.position.y, 0.8, accuracy: 0.001)
        XCTAssertEqual(anchor.position.z, -2.0, accuracy: 0.001)
    }

    func testInitWithFlatTransform() {
        let flatTransform: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            1.5, 0.8, -2.0, 1
        ]

        let anchor = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: flatTransform,
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(anchor.transform, flatTransform)
    }

    func testInitWithEmptyMetadata() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [:]
        )

        XCTAssertTrue(anchor.metadata.isEmpty)
        XCTAssertFalse(anchor.hasMetadata)
    }

    func testInitSetsTimestamps() {
        let beforeCreation = Date()

        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        XCTAssertGreaterThanOrEqual(anchor.createdAt, beforeCreation)
        XCTAssertGreaterThanOrEqual(anchor.updatedAt, beforeCreation)
        XCTAssertNil(anchor.deletedAt)
    }

    // MARK: - Transform Conversion Tests

    func testFlattenAndUnflatten() throws {
        let original = simd_float4x4(
            SIMD4<Float>(1, 2, 3, 4),
            SIMD4<Float>(5, 6, 7, 8),
            SIMD4<Float>(9, 10, 11, 12),
            SIMD4<Float>(13, 14, 15, 16)
        )

        let flattened = HBAnchor.flatten(original)
        XCTAssertEqual(flattened.count, 16)

        let restored = try HBAnchor.unflatten(flattened)

        // Compare each element
        for i in 0..<4 {
            XCTAssertEqual(original[i].x, restored[i].x, accuracy: 0.0001)
            XCTAssertEqual(original[i].y, restored[i].y, accuracy: 0.0001)
            XCTAssertEqual(original[i].z, restored[i].z, accuracy: 0.0001)
            XCTAssertEqual(original[i].w, restored[i].w, accuracy: 0.0001)
        }
    }

    func testFlattenColumnMajorOrder() {
        let matrix = simd_float4x4(
            SIMD4<Float>(1, 2, 3, 4),     // Column 0
            SIMD4<Float>(5, 6, 7, 8),     // Column 1
            SIMD4<Float>(9, 10, 11, 12),  // Column 2
            SIMD4<Float>(13, 14, 15, 16)  // Column 3
        )

        let flattened = HBAnchor.flatten(matrix)

        // Verify column-major order
        XCTAssertEqual(flattened[0], 1)   // Column 0, row 0
        XCTAssertEqual(flattened[1], 2)   // Column 0, row 1
        XCTAssertEqual(flattened[4], 5)   // Column 1, row 0
        XCTAssertEqual(flattened[12], 13) // Column 3, row 0 (x position)
    }

    func testUnflattenInvalidCount() {
        let invalid: [Float] = [1, 2, 3]  // Only 3 elements

        XCTAssertThrowsError(try HBAnchor.unflatten(invalid)) { error in
            guard case HBAnchorError.invalidTransform(let count) = error else {
                XCTFail("Expected invalidTransform error")
                return
            }
            XCTAssertEqual(count, 3)
        }
    }

    func testUnflattenEmptyArray() {
        XCTAssertThrowsError(try HBAnchor.unflatten([])) { error in
            guard case HBAnchorError.invalidTransform(let count) = error else {
                XCTFail("Expected invalidTransform error")
                return
            }
            XCTAssertEqual(count, 0)
        }
    }

    func testSimdTransformFromAnchor() throws {
        let original = matrix_identity_float4x4

        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: original
        )

        let restored = try anchor.simdTransform()

        // Identity matrix should have 1s on diagonal
        XCTAssertEqual(restored.columns.0.x, 1, accuracy: 0.0001)
        XCTAssertEqual(restored.columns.1.y, 1, accuracy: 0.0001)
        XCTAssertEqual(restored.columns.2.z, 1, accuracy: 0.0001)
        XCTAssertEqual(restored.columns.3.w, 1, accuracy: 0.0001)
    }

    func testPositionExtraction() {
        let transform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(5.0, 10.0, -15.0, 1)
        )

        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: transform
        )

        XCTAssertEqual(anchor.position.x, 5.0, accuracy: 0.001)
        XCTAssertEqual(anchor.position.y, 10.0, accuracy: 0.001)
        XCTAssertEqual(anchor.position.z, -15.0, accuracy: 0.001)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: [
                "text": "Hello",
                "count": 42,
                "active": true
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HBAnchor.self, from: encoded)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.spaceId, decoded.spaceId)
        XCTAssertEqual(original.transform, decoded.transform)
        XCTAssertEqual(decoded.stringMetadata(forKey: "text"), "Hello")
        XCTAssertEqual(decoded.intMetadata(forKey: "count"), 42)
        XCTAssertEqual(decoded.boolMetadata(forKey: "active"), true)
    }

    func testEncodeDecodeWithDeletedAt() throws {
        var original = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )
        original.deletedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HBAnchor.self, from: encoded)

        XCTAssertNotNil(decoded.deletedAt)
        XCTAssertTrue(decoded.isDeleted)
    }

    // MARK: - Metadata Tests

    func testMetadataAccess() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [
                "text": "Note",
                "priority": 5,
                "completed": false
            ]
        )

        XCTAssertEqual(anchor.stringMetadata(forKey: "text"), "Note")
        XCTAssertEqual(anchor.intMetadata(forKey: "priority"), 5)
        XCTAssertEqual(anchor.boolMetadata(forKey: "completed"), false)
        XCTAssertNil(anchor.stringMetadata(forKey: "missing"))
    }

    func testMetadataForKey() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["key": "value"]
        )

        let value = anchor.metadata(forKey: "key")
        XCTAssertNotNil(value)
        XCTAssertEqual(value?.stringValue, "value")

        XCTAssertNil(anchor.metadata(forKey: "nonexistent"))
    }

    func testMetadataUpdate() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["text": "Old"]
        )

        let originalUpdatedAt = anchor.updatedAt
        Thread.sleep(forTimeInterval: 0.01)

        anchor.updateMetadata(key: "text", value: "New")

        XCTAssertEqual(anchor.stringMetadata(forKey: "text"), "New")
        XCTAssertGreaterThan(anchor.updatedAt, originalUpdatedAt)
    }

    func testMetadataUpdateRemovesKey() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["key": "value"]
        )

        anchor.updateMetadata(key: "key", value: nil)

        XCTAssertNil(anchor.metadata(forKey: "key"))
        XCTAssertFalse(anchor.hasMetadata)
    }

    func testMetadataReplace() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["old": "data"]
        )

        anchor.update(metadata: ["new": "data"])

        XCTAssertNil(anchor.stringMetadata(forKey: "old"))
        XCTAssertEqual(anchor.stringMetadata(forKey: "new"), "data")
    }

    func testHasMetadata() {
        let anchorWithMetadata = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["key": "value"]
        )

        let anchorWithoutMetadata = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [:]
        )

        XCTAssertTrue(anchorWithMetadata.hasMetadata)
        XCTAssertFalse(anchorWithoutMetadata.hasMetadata)
    }

    // MARK: - Soft Delete Tests

    func testSoftDelete() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [:]
        )

        XCTAssertFalse(anchor.isDeleted)
        XCTAssertNil(anchor.deletedAt)

        anchor.markDeleted()

        XCTAssertTrue(anchor.isDeleted)
        XCTAssertNotNil(anchor.deletedAt)
    }

    func testRestore() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [:]
        )

        anchor.markDeleted()
        XCTAssertTrue(anchor.isDeleted)

        anchor.restore()
        XCTAssertFalse(anchor.isDeleted)
        XCTAssertNil(anchor.deletedAt)
    }

    func testSoftDeleteUpdatesTimestamp() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [:]
        )

        let originalUpdatedAt = anchor.updatedAt
        Thread.sleep(forTimeInterval: 0.01)

        anchor.markDeleted()

        XCTAssertGreaterThan(anchor.updatedAt, originalUpdatedAt)
    }

    func testRestoreUpdatesTimestamp() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: [:]
        )

        anchor.markDeleted()
        let afterDelete = anchor.updatedAt
        Thread.sleep(forTimeInterval: 0.01)

        anchor.restore()

        XCTAssertGreaterThan(anchor.updatedAt, afterDelete)
    }

    // MARK: - Transform Update Tests

    func testUpdateTransform() {
        var anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        let originalUpdatedAt = anchor.updatedAt
        Thread.sleep(forTimeInterval: 0.01)

        let newTransform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(99, 99, 99, 1)
        )

        anchor.update(transform: newTransform)

        XCTAssertEqual(anchor.position.x, 99, accuracy: 0.001)
        XCTAssertGreaterThan(anchor.updatedAt, originalUpdatedAt)
    }

    // MARK: - Validation Tests

    func testValidateWithValidTransform() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        XCTAssertTrue(anchor.validate())
    }

    func testValidateWithInvalidTransform() {
        let anchor = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: [1, 2, 3],  // Invalid: only 3 elements
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertFalse(anchor.validate())
    }

    func testValidSimdTransform() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        XCTAssertNotNil(anchor.validSimdTransform)
    }

    func testValidSimdTransformWithInvalidData() {
        let anchor = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: [1, 2, 3],
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertNil(anchor.validSimdTransform)
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        let id = UUID()
        let spaceId = UUID()
        let createdAt = Date()
        let updatedAt = Date()
        let transform: [Float] = Array(repeating: 1.0, count: 16)

        let anchor1 = HBAnchor(
            id: id,
            spaceId: spaceId,
            transform: transform,
            metadata: ["key": "value"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let anchor2 = HBAnchor(
            id: id,
            spaceId: spaceId,
            transform: transform,
            metadata: ["key": "value"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(anchor1, anchor2)
    }

    func testNotEqualDifferentId() {
        let anchor1 = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        let anchor2 = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        XCTAssertNotEqual(anchor1, anchor2)
    }

    // MARK: - Error Tests

    func testErrorDescriptions() {
        let invalidTransformError = HBAnchorError.invalidTransform(count: 5)
        XCTAssertNotNil(invalidTransformError.errorDescription)
        XCTAssertTrue(invalidTransformError.errorDescription!.contains("5"))

        let alreadyDeletedError = HBAnchorError.alreadyDeleted
        XCTAssertNotNil(alreadyDeletedError.errorDescription)
        XCTAssertTrue(alreadyDeletedError.errorDescription!.contains("deleted"))

        let keyNotFoundError = HBAnchorError.metadataKeyNotFound(key: "myKey")
        XCTAssertNotNil(keyNotFoundError.errorDescription)
        XCTAssertTrue(keyNotFoundError.errorDescription!.contains("myKey"))
    }

    // MARK: - AnyCodableValue Tests

    func testAnyCodableValueTypes() throws {
        let values: [String: AnyCodableValue] = [
            "string": "hello",
            "int": 42,
            "double": 3.14,
            "bool": true,
            "array": ["a", "b"],
            "null": nil
        ]

        let encoded = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: encoded)

        XCTAssertEqual(decoded["string"]?.stringValue, "hello")
        XCTAssertEqual(decoded["int"]?.intValue, 42)
        XCTAssertEqual(decoded["double"]?.doubleValue, 3.14)
        XCTAssertEqual(decoded["bool"]?.boolValue, true)
        XCTAssertEqual(decoded["null"]?.isNull, true)
    }

    func testAnyCodableValueNestedDictionary() throws {
        let nested: AnyCodableValue = .dictionary([
            "inner": .string("value"),
            "count": .int(10)
        ])

        let values: [String: AnyCodableValue] = ["nested": nested]

        let encoded = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: encoded)

        let decodedNested = decoded["nested"]?.dictionaryValue
        XCTAssertNotNil(decodedNested)
        XCTAssertEqual(decodedNested?["inner"]?.stringValue, "value")
        XCTAssertEqual(decodedNested?["count"]?.intValue, 10)
    }

    func testAnyCodableValueNestedArray() throws {
        let values: [String: AnyCodableValue] = [
            "tags": ["one", "two", "three"]
        ]

        let encoded = try JSONEncoder().encode(values)
        let decoded = try JSONDecoder().decode([String: AnyCodableValue].self, from: encoded)

        let tags = decoded["tags"]?.arrayValue
        XCTAssertNotNil(tags)
        XCTAssertEqual(tags?.count, 3)
        XCTAssertEqual(tags?[0].stringValue, "one")
    }

    func testAnyCodableValueExpressibleByLiterals() {
        let stringValue: AnyCodableValue = "test"
        XCTAssertEqual(stringValue.stringValue, "test")

        let intValue: AnyCodableValue = 42
        XCTAssertEqual(intValue.intValue, 42)

        let doubleValue: AnyCodableValue = 3.14
        XCTAssertEqual(doubleValue.doubleValue, 3.14)

        let boolValue: AnyCodableValue = true
        XCTAssertEqual(boolValue.boolValue, true)

        let nullValue: AnyCodableValue = nil
        XCTAssertTrue(nullValue.isNull)
    }

    func testAnyCodableValueAccessorsReturnNil() {
        let stringValue: AnyCodableValue = "test"

        XCTAssertNil(stringValue.intValue)
        XCTAssertNil(stringValue.doubleValue)
        XCTAssertNil(stringValue.boolValue)
        XCTAssertNil(stringValue.arrayValue)
        XCTAssertNil(stringValue.dictionaryValue)
        XCTAssertFalse(stringValue.isNull)
    }

    // MARK: - Identifiable Tests

    func testIdentifiable() {
        let id = UUID()
        let anchor = HBAnchor(
            id: id,
            spaceId: UUID(),
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(anchor.id, id)
    }
}

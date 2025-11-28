//
//  HBSpaceTests.swift
//  HyperbasisTests
//
//  Tests for HBSpace model
//

import XCTest
@testable import Hyperbasis

// Note: ARWorldMap cannot be easily mocked or created in unit tests without a real AR session.
// Tests involving actual ARWorldMap serialization/deserialization should be covered in integration
// tests running on a real iOS device with AR capabilities.

final class HBSpaceTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithSerializedData() {
        let id = UUID()
        let name = "Test Room"
        let worldMapData = Data([0x01, 0x02, 0x03])
        let createdAt = Date()
        let updatedAt = Date()

        let space = HBSpace(
            id: id,
            name: name,
            worldMapData: worldMapData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(space.id, id)
        XCTAssertEqual(space.name, name)
        XCTAssertEqual(space.worldMapData, worldMapData)
        XCTAssertEqual(space.createdAt, createdAt)
        XCTAssertEqual(space.updatedAt, updatedAt)
    }

    func testInitWithNilName() {
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertNil(space.name)
    }

    // MARK: - Codable Tests

    func testEncodeDecode() throws {
        let original = HBSpace(
            id: UUID(),
            name: "Test Space",
            worldMapData: Data([0x01, 0x02, 0x03, 0x04]),
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HBSpace.self, from: encoded)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.worldMapData, decoded.worldMapData)
    }

    func testEncodeDecodeWithNilName() throws {
        let original = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HBSpace.self, from: encoded)

        XCTAssertNil(decoded.name)
        XCTAssertEqual(original.id, decoded.id)
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        let id = UUID()
        let createdAt = Date()
        let updatedAt = Date()

        let space1 = HBSpace(
            id: id,
            name: "Room",
            worldMapData: Data([0x01, 0x02]),
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let space2 = HBSpace(
            id: id,
            name: "Room",
            worldMapData: Data([0x01, 0x02]),
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertEqual(space1, space2)
    }

    func testNotEqualDifferentId() {
        let createdAt = Date()

        let space1 = HBSpace(
            id: UUID(),
            name: "Room",
            worldMapData: Data([0x01]),
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let space2 = HBSpace(
            id: UUID(),
            name: "Room",
            worldMapData: Data([0x01]),
            createdAt: createdAt,
            updatedAt: createdAt
        )

        XCTAssertNotEqual(space1, space2)
    }

    func testNotEqualDifferentName() {
        let id = UUID()
        let createdAt = Date()

        let space1 = HBSpace(
            id: id,
            name: "Room A",
            worldMapData: Data([0x01]),
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let space2 = HBSpace(
            id: id,
            name: "Room B",
            worldMapData: Data([0x01]),
            createdAt: createdAt,
            updatedAt: createdAt
        )

        XCTAssertNotEqual(space1, space2)
    }

    // MARK: - Validation Tests

    func testValidateWithEmptyData() {
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: Data(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertFalse(space.validate())
    }

    func testValidateWithInvalidData() {
        // Non-empty but invalid data that can't be deserialized to ARWorldMap
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: Data([0x01, 0x02, 0x03]),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertFalse(space.validate())
    }

    // MARK: - World Map Size Tests

    func testWorldMapSize() {
        let data = Data(repeating: 0, count: 1024)
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: data,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(space.worldMapSize, 1024)
    }

    func testWorldMapSizeEmpty() {
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: Data(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(space.worldMapSize, 0)
    }

    func testWorldMapSizeFormatted() {
        let data = Data(repeating: 0, count: 1024)
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: data,
            createdAt: Date(),
            updatedAt: Date()
        )

        // ByteCountFormatter returns localized strings, so check it's not empty
        XCTAssertFalse(space.worldMapSizeFormatted.isEmpty)
    }

    func testWorldMapSizeFormattedLarge() {
        // 10MB of data
        let data = Data(repeating: 0, count: 10 * 1024 * 1024)
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: data,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertFalse(space.worldMapSizeFormatted.isEmpty)
        // Should contain "MB" for megabytes
        XCTAssertTrue(space.worldMapSizeFormatted.contains("MB"))
    }

    // MARK: - Mutation Tests

    func testUpdateName() {
        var space = HBSpace(
            id: UUID(),
            name: "Old Name",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        let originalUpdatedAt = space.updatedAt

        // Small delay to ensure timestamp changes
        Thread.sleep(forTimeInterval: 0.01)

        space.update(name: "New Name")

        XCTAssertEqual(space.name, "New Name")
        XCTAssertGreaterThan(space.updatedAt, originalUpdatedAt)
    }

    func testUpdateNameToNil() {
        var space = HBSpace(
            id: UUID(),
            name: "Some Name",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        space.update(name: nil)

        XCTAssertNil(space.name)
    }

    func testCreatedAtRemainsUnchangedAfterUpdate() {
        var space = HBSpace(
            id: UUID(),
            name: "Test",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        let originalCreatedAt = space.createdAt

        Thread.sleep(forTimeInterval: 0.01)
        space.update(name: "Updated")

        XCTAssertEqual(space.createdAt, originalCreatedAt)
    }

    // MARK: - Error Tests

    func testDeserializationFailedWithInvalidData() {
        let space = HBSpace(
            id: UUID(),
            name: nil,
            worldMapData: Data([0xFF, 0xFE, 0xFD]),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertThrowsError(try space.arWorldMap()) { error in
            guard let spaceError = error as? HBSpaceError else {
                XCTFail("Expected HBSpaceError")
                return
            }

            switch spaceError {
            case .deserializationFailed:
                // Expected
                break
            default:
                XCTFail("Expected deserializationFailed error")
            }
        }
    }

    func testErrorDescriptions() {
        let serializationError = HBSpaceError.serializationFailed(underlying: nil)
        XCTAssertNotNil(serializationError.errorDescription)
        XCTAssertTrue(serializationError.errorDescription!.contains("serialize"))

        let deserializationError = HBSpaceError.deserializationFailed(underlying: nil)
        XCTAssertNotNil(deserializationError.errorDescription)
        XCTAssertTrue(deserializationError.errorDescription!.contains("deserialize"))

        let invalidDataError = HBSpaceError.invalidWorldMapData
        XCTAssertNotNil(invalidDataError.errorDescription)
        XCTAssertTrue(invalidDataError.errorDescription!.contains("invalid"))
    }

    func testErrorDescriptionWithUnderlyingError() {
        let underlyingError = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = HBSpaceError.serializationFailed(underlying: underlyingError)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Test error"))
    }

    // MARK: - Identifiable Tests

    func testIdentifiable() {
        let id = UUID()
        let space = HBSpace(
            id: id,
            name: nil,
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(space.id, id)
    }
}

//
//  HBStorageTests.swift
//  HyperbasisTests
//
//  Tests for HBStorage and related components.
//

import XCTest
import simd
@testable import Hyperbasis

final class HBStorageTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create a temporary directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Configuration Tests

    func testDefaultConfig() {
        let config = HBStorageConfig.default

        XCTAssertEqual(config.backend, .localOnly)
        XCTAssertEqual(config.syncStrategy, .manual)
        XCTAssertEqual(config.compression, .balanced)
    }

    func testSupabaseConfig() {
        let config = HBStorageConfig.supabase(
            url: "https://test.supabase.co",
            anonKey: "test-key"
        )

        XCTAssertEqual(config.backend, .supabase(url: "https://test.supabase.co", anonKey: "test-key"))
        XCTAssertEqual(config.syncStrategy, .onSave)
        XCTAssertEqual(config.compression, .balanced)
    }

    func testSupabaseConfigWithManualSync() {
        let config = HBStorageConfig.supabase(
            url: "https://test.supabase.co",
            anonKey: "test-key",
            syncStrategy: .manual
        )

        XCTAssertEqual(config.syncStrategy, .manual)
    }

    func testLocalOnlyBackend() {
        let config = HBStorageConfig(
            backend: .localOnly,
            syncStrategy: .manual,
            compression: .none
        )

        XCTAssertEqual(config.backend, .localOnly)
    }

    // MARK: - Compression Tests

    func testCompressDecompressRoundtrip() throws {
        let originalData = Data(repeating: 0x42, count: 1000)

        let compressed = try HBCompression.compress(originalData, level: .balanced)
        let decompressed = try HBCompression.decompress(compressed)

        XCTAssertEqual(originalData, decompressed)
    }

    func testCompressionReducesSize() throws {
        // Repeating data compresses well
        let originalData = Data(repeating: 0x42, count: 10000)

        let compressed = try HBCompression.compress(originalData, level: .balanced)

        XCTAssertLessThan(compressed.count, originalData.count)
    }

    func testNoCompressionLevel() throws {
        let originalData = Data([0x01, 0x02, 0x03, 0x04])

        let result = try HBCompression.compress(originalData, level: .none)

        XCTAssertEqual(result, originalData)
    }

    func testEmptyDataCompression() throws {
        let emptyData = Data()

        let compressed = try HBCompression.compress(emptyData, level: .balanced)
        let decompressed = try HBCompression.decompress(compressed)

        XCTAssertEqual(decompressed, emptyData)
    }

    func testLargeDataCompression() throws {
        // Simulate a moderate world map (~100KB)
        let largeData = Data((0..<100_000).map { UInt8($0 % 256) })

        let compressed = try HBCompression.compress(largeData, level: .balanced)
        let decompressed = try HBCompression.decompress(compressed)

        XCTAssertEqual(decompressed, largeData)
    }

    // MARK: - Local Store Tests

    func testLocalStoreSaveAndLoadSpace() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let space = HBStorageSpace(
            id: UUID(),
            name: "Test Room",
            worldMapData: Data([0x01, 0x02, 0x03]),
            createdAt: Date(),
            updatedAt: Date(),
            isCompressed: false
        )

        try localStore.saveSpace(space)
        let loaded = try localStore.loadSpace(id: space.id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, space.id)
        XCTAssertEqual(loaded?.name, space.name)
        XCTAssertEqual(loaded?.worldMapData, space.worldMapData)
    }

    func testLocalStoreLoadNonexistentSpace() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let loaded = try localStore.loadSpace(id: UUID())

        XCTAssertNil(loaded)
    }

    func testLocalStoreLoadAllSpaces() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let space1 = HBStorageSpace(
            id: UUID(),
            name: "Room 1",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date(),
            isCompressed: false
        )

        let space2 = HBStorageSpace(
            id: UUID(),
            name: "Room 2",
            worldMapData: Data([0x02]),
            createdAt: Date(),
            updatedAt: Date(),
            isCompressed: false
        )

        try localStore.saveSpace(space1)
        try localStore.saveSpace(space2)

        let allSpaces = try localStore.loadAllSpaces()

        XCTAssertEqual(allSpaces.count, 2)
    }

    func testLocalStoreDeleteSpace() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let space = HBStorageSpace(
            id: UUID(),
            name: "Test Room",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date(),
            isCompressed: false
        )

        try localStore.saveSpace(space)
        try localStore.deleteSpace(id: space.id)

        let loaded = try localStore.loadSpace(id: space.id)
        XCTAssertNil(loaded)
    }

    func testLocalStoreSaveAndLoadAnchor() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let anchor = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: ["text": "Test note"],
            createdAt: Date(),
            updatedAt: Date()
        )

        try localStore.saveAnchor(anchor)
        let loaded = try localStore.loadAnchor(id: anchor.id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, anchor.id)
        XCTAssertEqual(loaded?.stringMetadata(forKey: "text"), "Test note")
    }

    func testLocalStoreLoadAnchorsForSpace() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let spaceId = UUID()

        let anchor1 = HBAnchor(
            id: UUID(),
            spaceId: spaceId,
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        let anchor2 = HBAnchor(
            id: UUID(),
            spaceId: spaceId,
            transform: Array(repeating: Float(2.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        let otherAnchor = HBAnchor(
            id: UUID(),
            spaceId: UUID(),  // Different space
            transform: Array(repeating: Float(3.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        try localStore.saveAnchor(anchor1)
        try localStore.saveAnchor(anchor2)
        try localStore.saveAnchor(otherAnchor)

        let anchors = try localStore.loadAnchors(spaceId: spaceId)

        XCTAssertEqual(anchors.count, 2)
    }

    func testLocalStorePurgeDeletedAnchors() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let spaceId = UUID()

        var deletedAnchor = HBAnchor(
            id: UUID(),
            spaceId: spaceId,
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )
        deletedAnchor.markDeleted()

        let activeAnchor = HBAnchor(
            id: UUID(),
            spaceId: spaceId,
            transform: Array(repeating: Float(2.0), count: 16),
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        try localStore.saveAnchor(deletedAnchor)
        try localStore.saveAnchor(activeAnchor)

        // Purge anchors deleted before now + 1 second (should purge the deleted one)
        try localStore.purgeDeletedAnchors(before: Date().addingTimeInterval(1))

        let loaded = try localStore.loadAnchor(id: deletedAnchor.id)
        XCTAssertNil(loaded)

        let activeLoaded = try localStore.loadAnchor(id: activeAnchor.id)
        XCTAssertNotNil(activeLoaded)
    }

    func testLocalStoreTotalSize() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let space = HBStorageSpace(
            id: UUID(),
            name: "Test",
            worldMapData: Data(repeating: 0x42, count: 1000),
            createdAt: Date(),
            updatedAt: Date(),
            isCompressed: false
        )

        try localStore.saveSpace(space)

        let size = try localStore.totalSize()
        XCTAssertGreaterThan(size, 0)
    }

    func testLocalStoreClearAll() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let space = HBStorageSpace(
            id: UUID(),
            name: "Test",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date(),
            isCompressed: false
        )

        try localStore.saveSpace(space)
        try localStore.clearAll()

        let loaded = try localStore.loadSpace(id: space.id)
        XCTAssertNil(loaded)
    }

    // MARK: - Pending Operations Tests

    func testPendingOperationsSaveAndLoad() throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)

        let operations = [
            HBPendingOperation(type: .saveSpace(UUID())),
            HBPendingOperation(type: .saveAnchor(UUID())),
            HBPendingOperation(type: .deleteSpace(UUID()))
        ]

        try localStore.savePendingOperations(operations)
        let loaded = localStore.loadPendingOperations()

        XCTAssertEqual(loaded.count, 3)
    }

    func testPendingOperationRetryCount() {
        var operation = HBPendingOperation(type: .saveSpace(UUID()))

        XCTAssertEqual(operation.retryCount, 0)

        operation.retryCount += 1
        XCTAssertEqual(operation.retryCount, 1)
    }

    // MARK: - HBStorage Integration Tests

    func testStorageSaveAndLoadSpace() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)

        let space = HBSpace(
            id: UUID(),
            name: "Living Room",
            worldMapData: Data(repeating: 0x42, count: 100),
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space)
        let loaded = try await storage.loadSpace(id: space.id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, space.id)
        XCTAssertEqual(loaded?.name, space.name)
        XCTAssertEqual(loaded?.worldMapData, space.worldMapData)
    }

    func testStorageSaveAndLoadAnchor() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)
        let spaceId = UUID()

        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4,
            metadata: ["note": "Test"]
        )

        try await storage.save(anchor)
        let loaded = try await storage.loadAnchor(id: anchor.id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, anchor.id)
        XCTAssertEqual(loaded?.stringMetadata(forKey: "note"), "Test")
    }

    func testStorageLoadAnchorsExcludesDeleted() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)
        let spaceId = UUID()

        let activeAnchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        var deletedAnchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )
        deletedAnchor.markDeleted()

        try await storage.save(activeAnchor)
        try await storage.save(deletedAnchor)

        let anchors = try await storage.loadAnchors(spaceId: spaceId)

        XCTAssertEqual(anchors.count, 1)
        XCTAssertEqual(anchors.first?.id, activeAnchor.id)
    }

    func testStorageLoadAnchorsIncludesDeleted() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)
        let spaceId = UUID()

        let activeAnchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        var deletedAnchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )
        deletedAnchor.markDeleted()

        try await storage.save(activeAnchor)
        try await storage.save(deletedAnchor)

        let anchors = try await storage.loadAnchors(spaceId: spaceId, includeDeleted: true)

        XCTAssertEqual(anchors.count, 2)
    }

    func testStorageDeleteAnchorSoftDeletes() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)
        let spaceId = UUID()

        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)
        try await storage.deleteAnchor(id: anchor.id)

        // Should still exist but be marked deleted
        let loaded = try await storage.loadAnchor(id: anchor.id)
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded?.isDeleted ?? false)
    }

    func testStorageDeleteNonexistentAnchorThrows() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)

        do {
            try await storage.deleteAnchor(id: UUID())
            XCTFail("Should throw notFound error")
        } catch let error as HBStorageError {
            if case .notFound(let type, _) = error {
                XCTAssertEqual(type, "anchor")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    func testStorageLoadAllSpaces() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)

        let space1 = HBSpace(
            id: UUID(),
            name: "Room 1",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        let space2 = HBSpace(
            id: UUID(),
            name: "Room 2",
            worldMapData: Data([0x02]),
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space1)
        try await storage.save(space2)

        let allSpaces = try await storage.loadAllSpaces()

        XCTAssertEqual(allSpaces.count, 2)
    }

    func testStorageDeleteSpace() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)

        let space = HBSpace(
            id: UUID(),
            name: "Test",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space)
        try await storage.deleteSpace(id: space.id)

        let loaded = try await storage.loadSpace(id: space.id)
        XCTAssertNil(loaded)
    }

    func testStorageClearLocalStorage() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)

        let space = HBSpace(
            id: UUID(),
            name: "Test",
            worldMapData: Data([0x01]),
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space)
        try storage.clearLocalStorage()

        let loaded = try await storage.loadSpace(id: space.id)
        XCTAssertNil(loaded)
    }

    func testStorageLocalStorageSize() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let storage = HBStorage(config: .default, localStore: localStore)

        let space = HBSpace(
            id: UUID(),
            name: "Test",
            worldMapData: Data(repeating: 0x42, count: 1000),
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space)

        let size = try storage.localStorageSize()
        XCTAssertGreaterThan(size, 0)
    }

    func testStorageIsCloudEnabled() {
        let localOnlyStorage = HBStorage(config: .default)
        XCTAssertFalse(localOnlyStorage.isCloudEnabled)

        let cloudStorage = HBStorage(config: .supabase(
            url: "https://test.supabase.co",
            anonKey: "test-key"
        ))
        XCTAssertTrue(cloudStorage.isCloudEnabled)
    }

    func testStorageSyncWithoutCloudThrows() async {
        let storage = HBStorage(config: .default)

        do {
            try await storage.sync()
            XCTFail("Should throw cloudNotConfigured error")
        } catch let error as HBStorageError {
            XCTAssertEqual(error.errorDescription, HBStorageError.cloudNotConfigured.errorDescription)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Error Tests

    func testStorageErrorDescriptions() {
        let notFoundError = HBStorageError.notFound(type: "space", id: UUID())
        XCTAssertTrue(notFoundError.errorDescription?.contains("Space") ?? false)

        let cloudNotConfiguredError = HBStorageError.cloudNotConfigured
        XCTAssertTrue(cloudNotConfiguredError.errorDescription?.contains("not configured") ?? false)

        let compressionError = HBStorageError.compressionFailed
        XCTAssertTrue(compressionError.errorDescription?.contains("compress") ?? false)

        let invalidURLError = HBStorageError.invalidURL("bad-url")
        XCTAssertTrue(invalidURLError.errorDescription?.contains("bad-url") ?? false)
    }

    // MARK: - Compression with Storage Tests

    func testStorageCompressesWorldMapData() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let config = HBStorageConfig(
            backend: .localOnly,
            syncStrategy: .manual,
            compression: .balanced
        )
        let storage = HBStorage(config: config, localStore: localStore)

        // Create large repeating data that compresses well
        let originalData = Data(repeating: 0x42, count: 10000)
        let space = HBSpace(
            id: UUID(),
            name: "Test",
            worldMapData: originalData,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space)

        // Load back and verify data is the same
        let loaded = try await storage.loadSpace(id: space.id)
        XCTAssertEqual(loaded?.worldMapData, originalData)
    }

    func testStorageNoCompression() async throws {
        let localStore = HBLocalStore(baseDirectory: tempDirectory)
        let config = HBStorageConfig(
            backend: .localOnly,
            syncStrategy: .manual,
            compression: .none
        )
        let storage = HBStorage(config: config, localStore: localStore)

        let originalData = Data([0x01, 0x02, 0x03])
        let space = HBSpace(
            id: UUID(),
            name: "Test",
            worldMapData: originalData,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await storage.save(space)
        let loaded = try await storage.loadSpace(id: space.id)

        XCTAssertEqual(loaded?.worldMapData, originalData)
    }
}

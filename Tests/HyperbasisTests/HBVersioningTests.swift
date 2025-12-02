//
//  HBVersioningTests.swift
//  HyperbasisTests
//
//  Tests for versioning functionality: HBAnchorEvent, HBDiff, HBTimeline, and storage versioning API.
//

import XCTest
import simd
@testable import Hyperbasis

final class HBVersioningTests: XCTestCase {

    var tempDirectory: URL!
    var localStore: HBLocalStore!
    var storage: HBStorage!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        localStore = HBLocalStore(baseDirectory: tempDirectory)
        storage = HBStorage(config: .default, localStore: localStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - HBAnchorEvent Tests

    func testEventCreatedFactory() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["text": "Test"]
        )

        let event = HBAnchorEvent.created(anchor: anchor)

        XCTAssertEqual(event.anchorId, anchor.id)
        XCTAssertEqual(event.spaceId, anchor.spaceId)
        XCTAssertEqual(event.type, .created)
        XCTAssertEqual(event.version, 1)
        XCTAssertEqual(event.transform, anchor.transform)
        XCTAssertEqual(event.metadata, anchor.metadata)
    }

    func testEventMovedFactory() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        let event = HBAnchorEvent.moved(anchor: anchor, previousVersion: 1)

        XCTAssertEqual(event.type, .moved)
        XCTAssertEqual(event.version, 2)
        XCTAssertEqual(event.transform, anchor.transform)
        XCTAssertNil(event.metadata)
    }

    func testEventUpdatedFactory() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["text": "Updated"]
        )

        let event = HBAnchorEvent.updated(anchor: anchor, previousVersion: 2)

        XCTAssertEqual(event.type, .updated)
        XCTAssertEqual(event.version, 3)
        XCTAssertNil(event.transform)
        XCTAssertEqual(event.metadata, anchor.metadata)
    }

    func testEventDeletedFactory() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4
        )

        let event = HBAnchorEvent.deleted(anchor: anchor, previousVersion: 3)

        XCTAssertEqual(event.type, .deleted)
        XCTAssertEqual(event.version, 4)
        XCTAssertNil(event.transform)
        XCTAssertNil(event.metadata)
    }

    func testEventRestoredFactory() {
        let anchor = HBAnchor(
            spaceId: UUID(),
            transform: matrix_identity_float4x4,
            metadata: ["text": "Restored"]
        )

        let event = HBAnchorEvent.restored(anchor: anchor, previousVersion: 4)

        XCTAssertEqual(event.type, .restored)
        XCTAssertEqual(event.version, 5)
        XCTAssertEqual(event.transform, anchor.transform)
        XCTAssertEqual(event.metadata, anchor.metadata)
    }

    func testEventIsActiveState() {
        XCTAssertTrue(HBAnchorEvent.EventType.created.rawValue == "created")

        let spaceId = UUID()
        let anchorId = UUID()

        let createdEvent = HBAnchorEvent(anchorId: anchorId, spaceId: spaceId, type: .created, version: 1)
        XCTAssertTrue(createdEvent.isActiveState)

        let movedEvent = HBAnchorEvent(anchorId: anchorId, spaceId: spaceId, type: .moved, version: 2)
        XCTAssertTrue(movedEvent.isActiveState)

        let deletedEvent = HBAnchorEvent(anchorId: anchorId, spaceId: spaceId, type: .deleted, version: 3)
        XCTAssertFalse(deletedEvent.isActiveState)

        let restoredEvent = HBAnchorEvent(anchorId: anchorId, spaceId: spaceId, type: .restored, version: 4)
        XCTAssertTrue(restoredEvent.isActiveState)
    }

    func testEventCodable() throws {
        let event = HBAnchorEvent(
            anchorId: UUID(),
            spaceId: UUID(),
            type: .created,
            version: 1,
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: ["key": "value"],
            actorId: "user123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(HBAnchorEvent.self, from: data)

        XCTAssertEqual(event.id, decoded.id)
        XCTAssertEqual(event.anchorId, decoded.anchorId)
        XCTAssertEqual(event.type, decoded.type)
        XCTAssertEqual(event.version, decoded.version)
        XCTAssertEqual(event.actorId, decoded.actorId)
    }

    // MARK: - HBTimeline Tests

    func testTimelineStateReconstruction() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-100),
                version: 1,
                transform: Array(repeating: Float(1.0), count: 16),
                metadata: ["text": "Original"]
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .updated,
                timestamp: now.addingTimeInterval(-50),
                version: 2,
                metadata: ["text": "Updated"]
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)

        // Reconstruct at original time
        let stateAtCreation = timeline.state(at: now.addingTimeInterval(-75))
        XCTAssertEqual(stateAtCreation.count, 1)
        XCTAssertEqual(stateAtCreation.first?.stringMetadata(forKey: "text"), "Original")

        // Reconstruct at later time
        let stateAfterUpdate = timeline.state(at: now)
        XCTAssertEqual(stateAfterUpdate.count, 1)
        XCTAssertEqual(stateAfterUpdate.first?.stringMetadata(forKey: "text"), "Updated")
    }

    func testTimelineStateWithDeletion() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-100),
                version: 1,
                transform: Array(repeating: Float(1.0), count: 16)
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .deleted,
                timestamp: now.addingTimeInterval(-50),
                version: 2
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)

        // Before deletion
        let stateBeforeDelete = timeline.state(at: now.addingTimeInterval(-75))
        XCTAssertEqual(stateBeforeDelete.count, 1)

        // After deletion
        let stateAfterDelete = timeline.state(at: now)
        XCTAssertEqual(stateAfterDelete.count, 0)
    }

    func testTimelineStateWithRestoration() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-100),
                version: 1,
                transform: Array(repeating: Float(1.0), count: 16)
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .deleted,
                timestamp: now.addingTimeInterval(-50),
                version: 2
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .restored,
                timestamp: now.addingTimeInterval(-25),
                version: 3,
                transform: Array(repeating: Float(1.0), count: 16)
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)

        // After restoration
        let stateAfterRestore = timeline.state(at: now)
        XCTAssertEqual(stateAfterRestore.count, 1)
    }

    func testTimelineBounds() {
        let spaceId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(anchorId: UUID(), spaceId: spaceId, type: .created, timestamp: now.addingTimeInterval(-100), version: 1),
            HBAnchorEvent(anchorId: UUID(), spaceId: spaceId, type: .created, timestamp: now.addingTimeInterval(-50), version: 1),
            HBAnchorEvent(anchorId: UUID(), spaceId: spaceId, type: .created, timestamp: now, version: 1)
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)

        XCTAssertNotNil(timeline.startDate)
        XCTAssertNotNil(timeline.endDate)
        XCTAssertEqual(timeline.duration, 100, accuracy: 0.1)
    }

    func testTimelineEmptyState() {
        let spaceId = UUID()
        let timeline = HBTimeline(spaceId: spaceId, events: [])

        XCTAssertNil(timeline.startDate)
        XCTAssertNil(timeline.endDate)
        XCTAssertNil(timeline.duration)
        XCTAssertTrue(timeline.state(at: Date()).isEmpty)
    }

    func testTimelineScrubberDates() {
        let spaceId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(anchorId: UUID(), spaceId: spaceId, type: .created, timestamp: now.addingTimeInterval(-100), version: 1),
            HBAnchorEvent(anchorId: UUID(), spaceId: spaceId, type: .created, timestamp: now, version: 1)
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)
        let dates = timeline.scrubberDates(steps: 11)

        XCTAssertEqual(dates.count, 11)
    }

    func testTimelineEventsForAnchor() {
        let spaceId = UUID()
        let anchorId1 = UUID()
        let anchorId2 = UUID()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(anchorId: anchorId1, spaceId: spaceId, type: .created, version: 1),
            HBAnchorEvent(anchorId: anchorId1, spaceId: spaceId, type: .moved, version: 2),
            HBAnchorEvent(anchorId: anchorId2, spaceId: spaceId, type: .created, version: 1)
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)
        let anchor1Events = timeline.events(for: anchorId1)

        XCTAssertEqual(anchor1Events.count, 2)
    }

    // MARK: - HBDiff Tests

    func testDiffDetectsAddedAnchors() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-50),
                version: 1,
                transform: Array(repeating: Float(1.0), count: 16)
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)
        let diff = timeline.diff(from: now.addingTimeInterval(-100), to: now)

        XCTAssertEqual(diff.added.count, 1)
        XCTAssertEqual(diff.removed.count, 0)
        XCTAssertTrue(diff.hasChanges)
    }

    func testDiffDetectsRemovedAnchors() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-100),
                version: 1,
                transform: Array(repeating: Float(1.0), count: 16)
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .deleted,
                timestamp: now.addingTimeInterval(-25),
                version: 2
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)
        let diff = timeline.diff(from: now.addingTimeInterval(-75), to: now)

        XCTAssertEqual(diff.removed.count, 1)
        XCTAssertEqual(diff.added.count, 0)
    }

    func testDiffDetectsMovedAnchors() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let originalTransform = Array(repeating: Float(1.0), count: 16)
        var newTransform = originalTransform
        newTransform[12] = 5.0  // Change x position

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-100),
                version: 1,
                transform: originalTransform
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .moved,
                timestamp: now.addingTimeInterval(-25),
                version: 2,
                transform: newTransform
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)
        let diff = timeline.diff(from: now.addingTimeInterval(-75), to: now)

        XCTAssertEqual(diff.moved.count, 1)
        XCTAssertEqual(diff.moved.first?.previousTransform, originalTransform)
    }

    func testDiffDetectsUpdatedAnchors() {
        let spaceId = UUID()
        let anchorId = UUID()
        let now = Date()

        let events: [HBAnchorEvent] = [
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .created,
                timestamp: now.addingTimeInterval(-100),
                version: 1,
                transform: Array(repeating: Float(1.0), count: 16),
                metadata: ["text": "Original"]
            ),
            HBAnchorEvent(
                anchorId: anchorId,
                spaceId: spaceId,
                type: .updated,
                timestamp: now.addingTimeInterval(-25),
                version: 2,
                metadata: ["text": "Updated"]
            )
        ]

        let timeline = HBTimeline(spaceId: spaceId, events: events)
        let diff = timeline.diff(from: now.addingTimeInterval(-75), to: now)

        XCTAssertEqual(diff.updated.count, 1)
        XCTAssertEqual(diff.updated.first?.previousMetadata["text"]?.stringValue, "Original")
    }

    func testDiffSummary() {
        let diff = HBDiff(
            spaceId: UUID(),
            fromDate: Date(),
            toDate: Date(),
            added: [HBAnchor(spaceId: UUID(), transform: matrix_identity_float4x4)],
            removed: [],
            moved: [],
            updated: []
        )

        XCTAssertEqual(diff.summary, "1 added")
        XCTAssertEqual(diff.changeCount, 1)
    }

    func testDiffNoChanges() {
        let diff = HBDiff(
            spaceId: UUID(),
            fromDate: Date(),
            toDate: Date()
        )

        XCTAssertEqual(diff.summary, "No changes")
        XCTAssertFalse(diff.hasChanges)
    }

    func testMovedAnchorDistanceCalculation() {
        let transform1: [Float] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
        var transform2 = transform1
        transform2[12] = 3.0  // x = 3
        transform2[13] = 4.0  // y = 4

        let anchor = HBAnchor(
            id: UUID(),
            spaceId: UUID(),
            transform: transform2,
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )

        let moved = HBDiff.MovedAnchor(anchor: anchor, previousTransform: transform1)

        XCTAssertEqual(moved.distanceMoved, 5.0, accuracy: 0.001)  // 3-4-5 triangle
    }

    // MARK: - Local Store Event Tests

    func testLocalStoreAppendAndLoadEvents() throws {
        let spaceId = UUID()
        let anchorId = UUID()

        let event1 = HBAnchorEvent(
            anchorId: anchorId,
            spaceId: spaceId,
            type: .created,
            version: 1,
            transform: Array(repeating: Float(1.0), count: 16)
        )

        let event2 = HBAnchorEvent(
            anchorId: anchorId,
            spaceId: spaceId,
            type: .moved,
            version: 2,
            transform: Array(repeating: Float(2.0), count: 16)
        )

        try localStore.appendEvent(event1)
        try localStore.appendEvent(event2)

        let loaded = try localStore.loadEvents(spaceId: spaceId)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].version, 1)
        XCTAssertEqual(loaded[1].version, 2)
    }

    func testLocalStoreCurrentVersion() throws {
        let spaceId = UUID()
        let anchorId = UUID()

        let event = HBAnchorEvent(
            anchorId: anchorId,
            spaceId: spaceId,
            type: .created,
            version: 1
        )

        try localStore.appendEvent(event)

        let version = try localStore.currentVersion(anchorId: anchorId, spaceId: spaceId)
        XCTAssertEqual(version, 1)
    }

    func testLocalStoreCurrentVersionNoEvents() throws {
        let version = try localStore.currentVersion(anchorId: UUID(), spaceId: UUID())
        XCTAssertEqual(version, 0)
    }

    // MARK: - Storage Versioning API Tests

    func testStorageSaveCreatesEvent() async throws {
        let spaceId = UUID()
        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4,
            metadata: ["text": "Test"]
        )

        try await storage.save(anchor)

        let events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .created)
        XCTAssertEqual(events.first?.version, 1)
    }

    func testStorageSaveCreatesMoveEvent() async throws {
        let spaceId = UUID()
        var anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)

        // Move the anchor
        let newTransform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(5, 0, 0, 1)
        )
        anchor.update(transform: newTransform)
        try await storage.save(anchor)

        let events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].type, .moved)
        XCTAssertEqual(events[1].version, 2)
    }

    func testStorageSaveCreatesUpdateEvent() async throws {
        let spaceId = UUID()
        var anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4,
            metadata: ["text": "Original"]
        )

        try await storage.save(anchor)

        // Update metadata
        anchor.updateMetadata(key: "text", value: "Updated")
        try await storage.save(anchor)

        let events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].type, .updated)
    }

    func testStorageSaveNoEventOnNoChange() async throws {
        let spaceId = UUID()
        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)
        try await storage.save(anchor)  // Save again with no changes

        let events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.count, 1)  // Only the created event
    }

    func testStorageTimeline() async throws {
        let spaceId = UUID()
        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)

        let timeline = try await storage.timeline(spaceId: spaceId)

        XCTAssertEqual(timeline.spaceId, spaceId)
        XCTAssertEqual(timeline.events.count, 1)
    }

    func testStorageHistory() async throws {
        let spaceId = UUID()
        var anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)

        let newTransform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(5, 0, 0, 1)
        )
        anchor.update(transform: newTransform)
        try await storage.save(anchor)

        let history = try await storage.history(anchorId: anchor.id)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].type, .created)
        XCTAssertEqual(history[1].type, .moved)
    }

    func testStorageAnchorsAt() async throws {
        let spaceId = UUID()
        let now = Date()

        var anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4,
            metadata: ["text": "Original"]
        )

        try await storage.save(anchor)

        // Wait a bit then update
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        anchor.updateMetadata(key: "text", value: "Updated")
        try await storage.save(anchor)

        // Get state at "now" (before the update)
        let pastAnchors = try await storage.anchorsAt(spaceId: spaceId, date: now)

        XCTAssertEqual(pastAnchors.count, 1)
        XCTAssertEqual(pastAnchors.first?.stringMetadata(forKey: "text"), "Original")
    }

    func testStorageDiff() async throws {
        let spaceId = UUID()
        let beforeCreate = Date()

        try await Task.sleep(nanoseconds: 10_000_000)

        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)

        let diff = try await storage.diff(spaceId: spaceId, from: beforeCreate, to: Date())

        XCTAssertEqual(diff.added.count, 1)
        XCTAssertTrue(diff.hasChanges)
    }

    func testStorageRollback() async throws {
        let spaceId = UUID()
        var anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4,
            metadata: ["text": "Version 1"]
        )

        try await storage.save(anchor)

        anchor.updateMetadata(key: "text", value: "Version 2")
        try await storage.save(anchor)

        anchor.updateMetadata(key: "text", value: "Version 3")
        try await storage.save(anchor)

        // Rollback to version 1
        let restored = try await storage.rollback(anchorId: anchor.id, toVersion: 1)

        XCTAssertEqual(restored.stringMetadata(forKey: "text"), "Version 1")

        // Verify a restore event was created
        let events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.last?.type, .restored)
    }

    func testStorageRollbackInvalidVersion() async throws {
        let spaceId = UUID()
        let anchor = HBAnchor(
            spaceId: spaceId,
            transform: matrix_identity_float4x4
        )

        try await storage.save(anchor)

        do {
            _ = try await storage.rollback(anchorId: anchor.id, toVersion: 99)
            XCTFail("Should throw versionNotFound")
        } catch let error as HBStorageError {
            if case .versionNotFound(_, let version) = error {
                XCTAssertEqual(version, 99)
            } else {
                XCTFail("Wrong error type")
            }
        }
    }

    func testStorageRollbackNonexistentAnchor() async {
        do {
            _ = try await storage.rollback(anchorId: UUID(), toVersion: 1)
            XCTFail("Should throw notFound")
        } catch let error as HBStorageError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Migration Tests

    func testMigrationSeedsEventForExistingAnchor() async throws {
        let spaceId = UUID()

        // Simulate a Phase 1 anchor (saved without versioning)
        let anchor = HBAnchor(
            id: UUID(),
            spaceId: spaceId,
            transform: Array(repeating: Float(1.0), count: 16),
            metadata: ["text": "Legacy"],
            createdAt: Date().addingTimeInterval(-1000),  // Created in the past
            updatedAt: Date().addingTimeInterval(-1000)
        )

        // Save directly to local store (bypassing versioning)
        try localStore.saveAnchor(anchor)

        // Verify no events yet
        var events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.count, 0)

        // Now update via storage (should trigger migration)
        var updatedAnchor = anchor
        updatedAnchor.updateMetadata(key: "text", value: "Migrated")
        try await storage.save(updatedAnchor)

        // Should have seeded created event + update event
        events = try localStore.loadEvents(spaceId: spaceId)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].type, .created)
        XCTAssertEqual(events[1].type, .updated)
    }

    // MARK: - Error Tests

    func testVersioningErrorDescriptions() {
        let versionNotFound = HBStorageError.versionNotFound(anchorId: UUID(), version: 5)
        XCTAssertTrue(versionNotFound.errorDescription?.contains("5") ?? false)

        let reconstructionFailed = HBStorageError.reconstructionFailed(anchorId: UUID())
        XCTAssertTrue(reconstructionFailed.errorDescription?.contains("reconstruct") ?? false)

        let eventLogCorrupted = HBStorageError.eventLogCorrupted(spaceId: UUID())
        XCTAssertTrue(eventLogCorrupted.errorDescription?.contains("corrupted") ?? false)
    }
}

//
//  HBStorage.swift
//  Hyperbasis
//
//  The main persistence engine for Hyperbasis.
//  Handles saving, loading, and syncing HBSpace and HBAnchor objects.
//

import Foundation

/// The main persistence engine for Hyperbasis
/// Handles saving, loading, and syncing HBSpace and HBAnchor objects
public final class HBStorage {

    // MARK: - Properties

    /// Current configuration
    public let config: HBStorageConfig

    /// Local file storage
    private let localStore: HBLocalStore

    /// Cloud storage (nil if localOnly)
    private let cloudStore: HBCloudStore?

    /// Queue of pending cloud operations (for offline support)
    private var pendingOperations: [HBPendingOperation] = []

    /// Whether cloud sync is available
    public var isCloudEnabled: Bool {
        cloudStore != nil
    }

    // MARK: - Initialization

    /// Creates a new HBStorage instance
    /// - Parameter config: Storage configuration
    public init(config: HBStorageConfig = .default) {
        self.config = config
        self.localStore = HBLocalStore()

        switch config.backend {
        case .localOnly:
            self.cloudStore = nil
        case .supabase(let url, let anonKey):
            self.cloudStore = HBCloudStore(url: url, anonKey: anonKey)
        }

        // Load any pending operations from previous session
        self.pendingOperations = localStore.loadPendingOperations()
    }

    /// Creates a new HBStorage instance with a custom local store (for testing)
    init(config: HBStorageConfig, localStore: HBLocalStore) {
        self.config = config
        self.localStore = localStore

        switch config.backend {
        case .localOnly:
            self.cloudStore = nil
        case .supabase(let url, let anonKey):
            self.cloudStore = HBCloudStore(url: url, anonKey: anonKey)
        }

        self.pendingOperations = localStore.loadPendingOperations()
    }

    // MARK: - Space Operations

    /// Saves a space to storage
    /// - Parameter space: The space to save
    /// - Throws: HBStorageError if save fails
    public func save(_ space: HBSpace) async throws {
        // 1. Compress world map data
        let compressedData = try HBCompression.compress(
            space.worldMapData,
            level: config.compression
        )

        // 2. Create compressed version for storage
        let storageSpace = HBStorageSpace(
            id: space.id,
            name: space.name,
            worldMapData: compressedData,
            createdAt: space.createdAt,
            updatedAt: space.updatedAt,
            isCompressed: config.compression != .none
        )

        // 3. Save locally (always)
        try localStore.saveSpace(storageSpace)

        // 4. Sync to cloud if configured
        if config.syncStrategy == .onSave, let cloudStore = cloudStore {
            do {
                try await cloudStore.uploadSpace(storageSpace)
            } catch {
                // Queue for retry if cloud fails
                queueOperation(.saveSpace(space.id))
                throw HBStorageError.cloudSyncFailed(underlying: error)
            }
        }
    }

    /// Loads a space from storage
    /// - Parameter id: The space ID to load
    /// - Returns: The loaded space, or nil if not found
    /// - Throws: HBStorageError if load fails
    public func loadSpace(id: UUID) async throws -> HBSpace? {
        // Try local first
        if let storageSpace = try localStore.loadSpace(id: id) {
            return try decompress(storageSpace)
        }

        // Try cloud if available
        if let cloudStore = cloudStore {
            if let storageSpace = try await cloudStore.downloadSpace(id: id) {
                // Cache locally
                try localStore.saveSpace(storageSpace)
                return try decompress(storageSpace)
            }
        }

        return nil
    }

    /// Loads all spaces from storage
    /// - Returns: Array of all spaces
    /// - Throws: HBStorageError if load fails
    public func loadAllSpaces() async throws -> [HBSpace] {
        let storageSpaces = try localStore.loadAllSpaces()
        return try storageSpaces.map { try decompress($0) }
    }

    /// Deletes a space and all its anchors
    /// - Parameter id: The space ID to delete
    /// - Throws: HBStorageError if delete fails
    public func deleteSpace(id: UUID) async throws {
        // Delete locally
        try localStore.deleteSpace(id: id)

        // Delete from cloud if configured
        if config.syncStrategy == .onSave, let cloudStore = cloudStore {
            do {
                try await cloudStore.deleteSpace(id: id)
            } catch {
                queueOperation(.deleteSpace(id))
                throw HBStorageError.cloudSyncFailed(underlying: error)
            }
        }
    }

    // MARK: - Anchor Operations

    /// Saves an anchor to storage
    /// Now also appends versioning events
    /// - Parameter anchor: The anchor to save
    /// - Throws: HBStorageError if save fails
    public func save(_ anchor: HBAnchor) async throws {
        // Check if anchor exists
        let existingAnchor = try localStore.loadAnchor(id: anchor.id)
        var currentVersion = try localStore.currentVersion(anchorId: anchor.id, spaceId: anchor.spaceId)

        // MIGRATION: Seed event history for existing anchors from Phase 1
        // If anchor exists but has no event history, create initial "created" event
        if let existing = existingAnchor, currentVersion == 0 {
            let seedEvent = HBAnchorEvent(
                anchorId: existing.id,
                spaceId: existing.spaceId,
                type: .created,
                timestamp: existing.createdAt,  // Use original creation date
                version: 1,
                transform: existing.transform,
                metadata: existing.metadata
            )
            try localStore.appendEvent(seedEvent)
            currentVersion = 1  // Update for subsequent change detection
        }

        // Determine event type
        let event: HBAnchorEvent?

        if let existing = existingAnchor {
            // Anchor exists - determine what changed
            if existing.deletedAt != nil && anchor.deletedAt == nil {
                // Restoring from deletion
                event = .restored(anchor: anchor, previousVersion: currentVersion)
            } else if anchor.deletedAt != nil && existing.deletedAt == nil {
                // Deleting
                event = .deleted(anchor: anchor, previousVersion: currentVersion)
            } else if existing.transform != anchor.transform {
                // Transform changed
                event = .moved(anchor: anchor, previousVersion: currentVersion)
            } else if existing.metadata != anchor.metadata {
                // Metadata changed
                event = .updated(anchor: anchor, previousVersion: currentVersion)
            } else {
                // No changes - just save without event
                event = nil
            }
        } else {
            // New anchor
            event = .created(anchor: anchor)
        }

        // Append event if there was a change
        if let event = event {
            try localStore.appendEvent(event)
        }

        // Save current state
        try localStore.saveAnchor(anchor)

        // Sync to cloud if configured
        if config.syncStrategy == .onSave, let cloudStore = cloudStore {
            do {
                try await cloudStore.uploadAnchor(anchor)
                if let event = event {
                    try await cloudStore.uploadEvent(event)
                }
            } catch {
                queueOperation(.saveAnchor(anchor.id))
                throw HBStorageError.cloudSyncFailed(underlying: error)
            }
        }
    }

    /// Loads all anchors for a space
    /// - Parameter spaceId: The space ID to load anchors for
    /// - Returns: Array of anchors (excluding soft-deleted ones by default)
    /// - Throws: HBStorageError if load fails
    public func loadAnchors(spaceId: UUID, includeDeleted: Bool = false) async throws -> [HBAnchor] {
        var anchors = try localStore.loadAnchors(spaceId: spaceId)

        if !includeDeleted {
            anchors = anchors.filter { !$0.isDeleted }
        }

        return anchors
    }

    /// Loads a single anchor by ID
    /// - Parameter id: The anchor ID to load
    /// - Returns: The anchor, or nil if not found
    /// - Throws: HBStorageError if load fails
    public func loadAnchor(id: UUID) async throws -> HBAnchor? {
        try localStore.loadAnchor(id: id)
    }

    /// Deletes an anchor (soft delete - marks as deleted)
    /// - Parameter id: The anchor ID to delete
    /// - Throws: HBStorageError if delete fails
    public func deleteAnchor(id: UUID) async throws {
        // Load, mark deleted, save
        guard var anchor = try localStore.loadAnchor(id: id) else {
            throw HBStorageError.notFound(type: "anchor", id: id)
        }

        anchor.markDeleted()
        try localStore.saveAnchor(anchor)

        // Sync to cloud if configured
        if config.syncStrategy == .onSave, let cloudStore = cloudStore {
            do {
                try await cloudStore.uploadAnchor(anchor)
            } catch {
                queueOperation(.saveAnchor(anchor.id))
                throw HBStorageError.cloudSyncFailed(underlying: error)
            }
        }
    }

    /// Permanently removes soft-deleted anchors older than the specified date
    /// - Parameter before: Remove anchors deleted before this date
    /// - Throws: HBStorageError if purge fails
    public func purgeDeletedAnchors(before: Date) async throws {
        try localStore.purgeDeletedAnchors(before: before)

        if let cloudStore = cloudStore {
            try await cloudStore.purgeDeletedAnchors(before: before)
        }
    }

    // MARK: - Sync Operations

    /// Manually triggers a sync with cloud storage
    /// Uploads any pending local changes and downloads remote changes
    /// - Throws: HBStorageError if sync fails
    public func sync() async throws {
        guard let cloudStore = cloudStore else {
            throw HBStorageError.cloudNotConfigured
        }

        // 1. Process pending operations with retry
        try await processPendingOperations()

        // 2. Upload local changes not yet synced
        try await uploadLocalChanges(to: cloudStore)

        // 3. Download remote changes
        try await downloadRemoteChanges(from: cloudStore)
    }

    /// Returns the number of pending operations waiting to sync
    public var pendingOperationCount: Int {
        pendingOperations.count
    }

    // MARK: - Private Helpers

    private func decompress(_ storageSpace: HBStorageSpace) throws -> HBSpace {
        let worldMapData: Data
        if storageSpace.isCompressed {
            worldMapData = try HBCompression.decompress(storageSpace.worldMapData)
        } else {
            worldMapData = storageSpace.worldMapData
        }

        return HBSpace(
            id: storageSpace.id,
            name: storageSpace.name,
            worldMapData: worldMapData,
            createdAt: storageSpace.createdAt,
            updatedAt: storageSpace.updatedAt
        )
    }

    private func queueOperation(_ type: HBPendingOperation.OperationType) {
        let operation = HBPendingOperation(type: type)
        pendingOperations.append(operation)
        try? localStore.savePendingOperations(pendingOperations)
    }

    private func processPendingOperations() async throws {
        guard let cloudStore = cloudStore else { return }

        var remainingOperations: [HBPendingOperation] = []

        for operation in pendingOperations {
            do {
                try await executeOperation(operation, on: cloudStore)
            } catch {
                // Keep failed operations for retry
                var updatedOp = operation
                updatedOp.retryCount += 1

                if updatedOp.retryCount < 5 {
                    remainingOperations.append(updatedOp)
                }
                // After 5 retries, drop the operation
            }
        }

        pendingOperations = remainingOperations
        try? localStore.savePendingOperations(pendingOperations)
    }

    private func executeOperation(_ operation: HBPendingOperation, on cloudStore: HBCloudStore) async throws {
        switch operation.type {
        case .saveSpace(let id):
            if let storageSpace = try localStore.loadSpace(id: id) {
                try await cloudStore.uploadSpace(storageSpace)
            }
        case .deleteSpace(let id):
            try await cloudStore.deleteSpace(id: id)
        case .saveAnchor(let id):
            if let anchor = try localStore.loadAnchor(id: id) {
                try await cloudStore.uploadAnchor(anchor)
            }
        }
    }

    private func uploadLocalChanges(to cloudStore: HBCloudStore) async throws {
        // Get locally modified items since last sync
        let lastSync = localStore.lastSyncDate ?? .distantPast

        let modifiedSpaces = try localStore.loadSpacesModifiedSince(lastSync)
        for space in modifiedSpaces {
            try await cloudStore.uploadSpace(space)
        }

        let modifiedAnchors = try localStore.loadAnchorsModifiedSince(lastSync)
        for anchor in modifiedAnchors {
            try await cloudStore.uploadAnchor(anchor)
        }

        localStore.lastSyncDate = Date()
    }

    private func downloadRemoteChanges(from cloudStore: HBCloudStore) async throws {
        let lastSync = localStore.lastSyncDate ?? .distantPast

        // Download spaces modified on server
        let remoteSpaces = try await cloudStore.downloadSpacesModifiedSince(lastSync)
        for remoteSpace in remoteSpaces {
            // Last-write-wins: only save if remote is newer
            if let localSpace = try localStore.loadSpace(id: remoteSpace.id) {
                if remoteSpace.updatedAt > localSpace.updatedAt {
                    try localStore.saveSpace(remoteSpace)
                }
            } else {
                try localStore.saveSpace(remoteSpace)
            }
        }

        // Download anchors modified on server
        let remoteAnchors = try await cloudStore.downloadAnchorsModifiedSince(lastSync)
        for remoteAnchor in remoteAnchors {
            if let localAnchor = try localStore.loadAnchor(id: remoteAnchor.id) {
                if remoteAnchor.updatedAt > localAnchor.updatedAt {
                    try localStore.saveAnchor(remoteAnchor)
                }
            } else {
                try localStore.saveAnchor(remoteAnchor)
            }
        }
    }

    // MARK: - Data Management

    /// Clears all local storage data
    /// WARNING: This is destructive and cannot be undone
    public func clearLocalStorage() throws {
        try localStore.clearAll()
        pendingOperations = []
    }

    /// Returns the total size of local storage in bytes
    public func localStorageSize() throws -> Int {
        try localStore.totalSize()
    }

    // MARK: - Versioning API

    /// Get the full timeline for a space
    /// - Parameter spaceId: The space to get timeline for
    /// - Returns: Timeline with all events
    public func timeline(spaceId: UUID) async throws -> HBTimeline {
        let events = try localStore.loadEvents(spaceId: spaceId)
        return HBTimeline(spaceId: spaceId, events: events)
    }

    /// Get anchors as they existed at a specific point in time
    /// - Parameters:
    ///   - spaceId: The space to query
    ///   - date: The point in time to reconstruct
    /// - Returns: Anchors as they existed at that date
    public func anchorsAt(spaceId: UUID, date: Date) async throws -> [HBAnchor] {
        let timeline = try await timeline(spaceId: spaceId)
        return timeline.state(at: date)
    }

    /// Get the difference between two points in time
    /// - Parameters:
    ///   - spaceId: The space to diff
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Diff describing all changes
    public func diff(spaceId: UUID, from: Date, to: Date) async throws -> HBDiff {
        let timeline = try await timeline(spaceId: spaceId)
        return timeline.diff(from: from, to: to)
    }

    /// Get the history of changes for a specific anchor
    /// - Parameter anchorId: The anchor to get history for
    /// - Returns: Array of events in chronological order
    public func history(anchorId: UUID) async throws -> [HBAnchorEvent] {
        let anchor = try localStore.loadAnchor(id: anchorId)
        guard let anchor = anchor else {
            throw HBStorageError.notFound(type: "anchor", id: anchorId)
        }

        let allEvents = try localStore.loadEvents(spaceId: anchor.spaceId)
        return allEvents
            .filter { $0.anchorId == anchorId }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Rollback an anchor to a previous version
    /// - Parameters:
    ///   - anchorId: The anchor to rollback
    ///   - toVersion: The version number to restore
    /// - Returns: The restored anchor
    @discardableResult
    public func rollback(anchorId: UUID, toVersion: Int) async throws -> HBAnchor {
        let events = try await history(anchorId: anchorId)

        // Find the event with the target version
        guard events.contains(where: { $0.version == toVersion }) else {
            throw HBStorageError.versionNotFound(anchorId: anchorId, version: toVersion)
        }

        // Reconstruct state at that version
        let relevantEvents = events.filter { $0.version <= toVersion }
        guard let state = reconstructAnchor(from: relevantEvents) else {
            throw HBStorageError.reconstructionFailed(anchorId: anchorId)
        }

        // Create and save the restored anchor
        var restored = state
        restored.restore() // Clear deletedAt if set

        // Get current version for the new event
        let currentVersion = events.map(\.version).max() ?? 0

        // Append restore event
        let event = HBAnchorEvent.restored(anchor: restored, previousVersion: currentVersion)
        try localStore.appendEvent(event)

        // Update current anchor state
        try localStore.saveAnchor(restored)

        return restored
    }

    // MARK: - Private Versioning Helpers

    private func reconstructAnchor(from events: [HBAnchorEvent]) -> HBAnchor? {
        guard let firstEvent = events.first, firstEvent.type == .created else {
            return nil
        }

        var transform = firstEvent.transform ?? []
        var metadata = firstEvent.metadata ?? [:]
        var isDeleted = false
        var updatedAt = firstEvent.timestamp

        for event in events.dropFirst() {
            switch event.type {
            case .created:
                break // Shouldn't happen
            case .moved:
                transform = event.transform ?? transform
                updatedAt = event.timestamp
            case .updated:
                metadata = event.metadata ?? metadata
                updatedAt = event.timestamp
            case .deleted:
                isDeleted = true
                updatedAt = event.timestamp
            case .restored:
                transform = event.transform ?? transform
                metadata = event.metadata ?? metadata
                isDeleted = false
                updatedAt = event.timestamp
            }
        }

        return HBAnchor(
            id: firstEvent.anchorId,
            spaceId: firstEvent.spaceId,
            transform: transform,
            metadata: metadata,
            createdAt: firstEvent.timestamp,
            updatedAt: updatedAt,
            deletedAt: isDeleted ? updatedAt : nil
        )
    }
}

// MARK: - Internal Storage Types

/// Internal representation of HBSpace for storage
/// Includes compression flag and uses compressed data
struct HBStorageSpace: Codable {
    let id: UUID
    var name: String?
    var worldMapData: Data  // May be compressed
    let createdAt: Date
    var updatedAt: Date
    var isCompressed: Bool
}

/// Represents a pending cloud operation for offline support
struct HBPendingOperation: Codable {
    let type: OperationType
    var retryCount: Int = 0
    let createdAt: Date

    init(type: OperationType) {
        self.type = type
        self.retryCount = 0
        self.createdAt = Date()
    }

    enum OperationType: Codable {
        case saveSpace(UUID)
        case deleteSpace(UUID)
        case saveAnchor(UUID)
    }
}

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
    /// - Parameter anchor: The anchor to save
    /// - Throws: HBStorageError if save fails
    public func save(_ anchor: HBAnchor) async throws {
        // Save locally
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

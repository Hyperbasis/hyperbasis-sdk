//
//  HBStorageConfig.swift
//  Hyperbasis
//
//  Configuration types for HBStorage.
//

import Foundation

/// Configuration for HBStorage
public struct HBStorageConfig {

    /// The storage backend to use
    public var backend: HBBackend

    /// When to sync with cloud (ignored if backend is .localOnly)
    public var syncStrategy: HBSyncStrategy

    /// Compression level for world map data
    public var compression: HBCompressionLevel

    /// Default configuration (local only, no cloud)
    public static var `default`: HBStorageConfig {
        HBStorageConfig(
            backend: .localOnly,
            syncStrategy: .manual,
            compression: .balanced
        )
    }

    /// Configuration with Supabase cloud sync
    public static func supabase(
        url: String,
        anonKey: String,
        syncStrategy: HBSyncStrategy = .onSave
    ) -> HBStorageConfig {
        HBStorageConfig(
            backend: .supabase(url: url, anonKey: anonKey),
            syncStrategy: syncStrategy,
            compression: .balanced
        )
    }

    public init(
        backend: HBBackend,
        syncStrategy: HBSyncStrategy,
        compression: HBCompressionLevel
    ) {
        self.backend = backend
        self.syncStrategy = syncStrategy
        self.compression = compression
    }
}

/// Storage backend options
public enum HBBackend: Equatable {
    /// Local storage only, no cloud sync
    case localOnly

    /// Supabase cloud storage
    /// - Parameters:
    ///   - url: Supabase project URL (e.g., "https://xxx.supabase.co")
    ///   - anonKey: Supabase anonymous/public key
    case supabase(url: String, anonKey: String)
}

/// When to sync with cloud
public enum HBSyncStrategy: Equatable {
    /// Only sync when sync() is explicitly called
    case manual

    /// Automatically sync after every save operation
    case onSave
}

/// Compression level for world map data
public enum HBCompressionLevel: Equatable {
    /// No compression (for debugging or pre-compressed data)
    case none

    /// Balanced compression using zlib (~40% reduction, fast)
    case balanced
}

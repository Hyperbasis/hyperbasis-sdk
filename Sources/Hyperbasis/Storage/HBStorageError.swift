//
//  HBStorageError.swift
//  Hyperbasis
//
//  Error types for storage operations.
//

import Foundation

/// Errors that can occur during storage operations
public enum HBStorageError: LocalizedError {

    /// Item was not found in storage
    case notFound(type: String, id: UUID)

    /// Cloud sync is not configured
    case cloudNotConfigured

    /// Cloud sync operation failed
    case cloudSyncFailed(underlying: Error)

    /// Data compression failed
    case compressionFailed

    /// Data decompression failed
    case decompressionFailed(underlying: Error?)

    /// Invalid URL
    case invalidURL(String)

    /// Download from cloud failed
    case downloadFailed

    /// Upload to cloud failed
    case uploadFailed(underlying: Error)

    /// Local file operation failed
    case fileOperationFailed(underlying: Error)

    /// Data encoding failed
    case encodingFailed(underlying: Error)

    /// Data decoding failed
    case decodingFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notFound(let type, let id):
            return "\(type.capitalized) not found: \(id)"
        case .cloudNotConfigured:
            return "Cloud sync is not configured. Use HBBackend.supabase to enable cloud features."
        case .cloudSyncFailed(let underlying):
            return "Cloud sync failed: \(underlying.localizedDescription)"
        case .compressionFailed:
            return "Failed to compress data"
        case .decompressionFailed(let underlying):
            if let underlying = underlying {
                return "Failed to decompress data: \(underlying.localizedDescription)"
            }
            return "Failed to decompress data"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .downloadFailed:
            return "Failed to download from cloud"
        case .uploadFailed(let underlying):
            return "Failed to upload to cloud: \(underlying.localizedDescription)"
        case .fileOperationFailed(let underlying):
            return "File operation failed: \(underlying.localizedDescription)"
        case .encodingFailed(let underlying):
            return "Failed to encode data: \(underlying.localizedDescription)"
        case .decodingFailed(let underlying):
            return "Failed to decode data: \(underlying.localizedDescription)"
        }
    }
}

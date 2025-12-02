# Hyperbasis

Persistence infrastructure for spatial computing. Save, sync, and version AR content in 3 lines of code.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/hyperbasis/hyperbasis-sdk", from: "1.1.0")
]
```

## Quick Start

```swift
import Hyperbasis

let storage = HBStorage()

// Save
let space = try HBSpace(worldMap: arWorldMap)
try await storage.save(space)

let anchor = HBAnchor(spaceId: space.id, transform: matrix, metadata: ["id": .string("abc")])
try await storage.save(anchor)

// Load
let spaces = try await storage.loadAllSpaces()
let anchors = try await storage.loadAnchors(spaceId: space.id)
```

## Features

- **Persist** — AR content survives app restarts
- **Sync** — Cross-device sync via Supabase
- **Version** — Full history, time travel, rollback

## Requirements

- iOS 17.0+
- Swift 5.9+

## Docs

**[docs.hyperbasis.dev](https://docs.hyperbasis.dev)**

## License

MIT

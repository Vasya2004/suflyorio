import Foundation

public struct TakeIntent: Codable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public var filename: String { id.uuidString + ".mov" }

    public init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id; self.title = title; self.createdAt = createdAt
    }
}

/// A durable sidecar precedes recording. It survives a metadata save failure or process death.
public struct TakeFiles: Sendable {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func movieURL(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".mov") }
    public func journalURL(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    public func register(_ intent: TakeIntent) throws {
        try JSONEncoder().encode(intent).write(to: journalURL(for: intent.id), options: .atomic)
    }

    public func candidates() throws -> [TakeIntent] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var result: [UUID: TakeIntent] = [:]
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let intent = try? JSONDecoder().decode(TakeIntent.self, from: data) {
                result[intent.id] = intent
            }
        }
        // A movie without a readable sidecar must still be offered for recovery.
        for url in urls where url.pathExtension == "mov" {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), result[id] == nil {
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                result[id] = TakeIntent(id: id, title: "Восстановленный дубль", createdAt: date)
            }
        }
        return result.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(_ id: UUID) throws {
        for url in [movieURL(for: id), journalURL(for: id)] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}


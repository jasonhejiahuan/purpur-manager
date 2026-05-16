import Foundation

struct ServerExportBundle: Codable, Sendable {
    var exportedAt: Date = Date()
    var profiles: [ServerProfile]
    var note = "API keys are intentionally excluded. Re-enter them after import."
}

final class ServerStore: @unchecked Sendable {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("PurpurManager", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("servers.json")
    }

    func load() -> [ServerProfile] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [ServerProfile]) throws {
        let data = try JSONEncoder.pretty.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }

    func export(_ profiles: [ServerProfile], to url: URL) throws {
        let bundle = ServerExportBundle(profiles: profiles)
        let data = try JSONEncoder.pretty.encode(bundle)
        try data.write(to: url, options: [.atomic])
    }

    func importProfiles(from url: URL) throws -> [ServerProfile] {
        let data = try Data(contentsOf: url)
        if let bundle = try? JSONDecoder().decode(ServerExportBundle.self, from: data) {
            return bundle.profiles.map { profile in
                var copy = profile
                copy.id = UUID()
                copy.updatedAt = Date()
                return copy
            }
        }
        return try JSONDecoder().decode([ServerProfile].self, from: data).map { profile in
            var copy = profile
            copy.id = UUID()
            copy.updatedAt = Date()
            return copy
        }
    }
}

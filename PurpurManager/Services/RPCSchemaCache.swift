import Foundation

actor RPCSchemaCache {
    private let directory: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = support.appendingPathComponent("PurpurManager/Schemas", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(methods: [RPCMethodDescriptor], for serverID: UUID) throws {
        let data = try JSONEncoder.pretty.encode(methods)
        try data.write(to: url(for: serverID), options: [.atomic])
    }

    func load(for serverID: UUID) -> [RPCMethodDescriptor] {
        guard let data = try? Data(contentsOf: url(for: serverID)) else { return [] }
        return (try? JSONDecoder().decode([RPCMethodDescriptor].self, from: data)) ?? []
    }

    private func url(for serverID: UUID) -> URL {
        directory.appendingPathComponent("\(serverID.uuidString).json")
    }
}

import Foundation

/// Persists macros as versioned JSON files in a local directory. Never touches the network.
public final class MacroStore: @unchecked Sendable {
    public static let fileExtension = "macrecord"

    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// Overridable with the `macrecordDataDir` default (e.g. `-macrecordDataDir /tmp/x` for testing).
    public static var defaultDirectory: URL {
        if let custom = UserDefaults.standard.string(forKey: "macrecordDataDir") {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("macrecord/Macros", isDirectory: true)
    }

    public func loadAll() throws -> [Macro] {
        try ensureDirectory()
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == Self.fileExtension }
        return urls.compactMap { try? Self.decode(Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func save(_ macro: Macro) throws {
        try ensureDirectory()
        try Self.encode(macro).write(to: url(for: macro.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        let url = url(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Self.fileExtension)")
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public enum StoreError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    public static func encode(_ macro: Macro) throws -> Data {
        let encoder = JSONEncoder()
        // Compact: recordings hold ~1000 events per second. Pretty-print with any JSON tool if needed.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(macro)
    }

    public static func decode(_ data: Data) throws -> Macro {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Header: Decodable { let schemaVersion: Int }
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion <= Macro.currentSchemaVersion else {
            throw StoreError.unsupportedSchema(header.schemaVersion)
        }
        return try decoder.decode(Macro.self, from: data)
    }

    /// Imports an external file as a new macro (fresh id so it never overwrites an existing one).
    public func importMacro(from url: URL) throws -> Macro {
        var macro = try Self.decode(Data(contentsOf: url))
        macro.id = UUID()
        try save(macro)
        return macro
    }

    public func export(_ macro: Macro, to url: URL) throws {
        try Self.encode(macro).write(to: url, options: .atomic)
    }
}

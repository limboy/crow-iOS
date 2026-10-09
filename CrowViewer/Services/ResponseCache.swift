import CryptoKit
import Foundation
import Synchronization

/// API responses kept on disk, so documents open instantly and still show when the server
/// can't be reached. Each document's responses are tagged with the version crow-service reported
/// for it, and reused without asking the server until that version changes.
nonisolated final class ResponseCache: Sendable {
    static let shared = ResponseCache()

    struct Entry: Codable {
        /// The document's version when this was fetched; nil outside a document.
        var version: String?
        var etag: String?
        var body: Data
    }

    private let root: URL
    /// Document scope → its latest known version.
    private let versions: Mutex<[String: String]>
    /// Document scope → records seen in lists this session, with their linked records, by id.
    private let listed = Mutex<[String: [String: CrowRecord]]>([:])

    init(root: URL = .cachesDirectory.appending(path: "CrowAPI", directoryHint: .isDirectory)) {
        self.root = root
        let saved = try? PropertyListDecoder().decode([String: String].self, from: Data(contentsOf: root.appending(path: "versions.plist")))
        versions = Mutex(saved ?? [:])
    }

    /// Identifies one document on one server.
    static func scope(server: URL, doc: String) -> String { server.absoluteString + "\n" + doc }

    func version(of scope: String) -> String? {
        versions.withLock { $0[scope] }
    }

    /// Records a document's version, dropping everything cached under an older one.
    func setVersion(_ version: String, of scope: String) {
        let snapshot: [String: String]? = versions.withLock { map in
            let old = map[scope]
            guard old != version else { return nil }
            map[scope] = version
            return map
        }
        guard let snapshot else { return }
        try? FileManager.default.removeItem(at: directory(for: scope))
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? PropertyListEncoder().encode(snapshot).write(to: root.appending(path: "versions.plist"), options: .atomic)
    }

    /// Keeps listed records, and the linked records expanded into them, so a record can open
    /// offline without having been opened before.
    func remember(_ records: [CrowRecord], in scope: String) {
        listed.withLock { map in
            var known = map[scope] ?? [:]
            for record in records {
                for linked in (record.expand ?? [:]).values.joined() where known.index(forKey: linked.id) == nil {
                    known[linked.id] = linked
                }
                if record.expand != nil || known[record.id].flatMap(\.expand) == nil { known[record.id] = record }
            }
            map[scope] = known
        }
    }

    func listedRecord(_ id: String, in scope: String) -> CrowRecord? {
        listed.withLock { $0[scope]?[id] }
    }

    func entry(for url: URL, in scope: String?) -> Entry? {
        guard let data = try? Data(contentsOf: file(for: url, in: scope)) else { return nil }
        return try? PropertyListDecoder().decode(Entry.self, from: data)
    }

    func store(_ entry: Entry, for url: URL, in scope: String?) {
        let file = file(for: url, in: scope)
        guard let data = try? PropertyListEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    private func directory(for scope: String?) -> URL {
        root.appending(path: scope.map(Self.hash) ?? "_", directoryHint: .isDirectory)
    }

    private func file(for url: URL, in scope: String?) -> URL {
        directory(for: scope).appending(path: Self.hash(url.absoluteString) + ".plist")
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

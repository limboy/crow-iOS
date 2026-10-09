import Foundation

/// A read-only client for crow-service's JSON API.
struct CrowAPI: Sendable {
    let baseURL: URL

    init?(server: String) {
        var text = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        baseURL = url
    }

    struct RecordQuery: Hashable {
        var search = ""
        /// Field name → value, matching the service's `where`. `.null` matches empty.
        var whereClause: [String: JSONValue] = [:]
        /// Field names, `-` prefix for descending.
        var sort: [String] = []
        var expand: [String] = []
    }

    // Documents and schemas are always checked with the server (a 304 when unchanged), which
    // keeps each document's version current. Records come from the cache while their document's
    // version is unchanged, unless `revalidate` asks the server too.

    func documents() async throws -> [DocumentSummary] {
        let items = try await get(DocumentList.self, path: ["documents"], revalidate: true).items
        for doc in items {
            if let version = doc.version { cache.setVersion(version, of: scope(doc.name)) }
        }
        return items
    }

    func document(_ doc: String) async throws -> DocumentSchema {
        try await get(DocumentSchema.self, path: ["documents", doc], doc: doc, revalidate: true)
    }

    func records(doc: String, table: String, query: RecordQuery, page: Int, perPage: Int = 100, revalidate: Bool = false) async throws -> RecordPage {
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: String(perPage))]
        if !query.search.isEmpty { items.append(.init(name: "q", value: query.search)) }
        if !query.sort.isEmpty { items.append(.init(name: "sort", value: query.sort.joined(separator: ","))) }
        if !query.expand.isEmpty { items.append(.init(name: "expand", value: query.expand.joined(separator: ","))) }
        if !query.whereClause.isEmpty, let data = try? JSONEncoder().encode(query.whereClause) {
            items.append(.init(name: "where", value: String(decoding: data, as: UTF8.self)))
        }
        return try await get(RecordPage.self, path: ["documents", doc, "tables", table, "records"], query: items, doc: doc, revalidate: revalidate)
    }

    func record(doc: String, table: String, id: String, expand: [String], revalidate: Bool = false) async throws -> CrowRecord {
        let items = expand.isEmpty ? [] : [URLQueryItem(name: "expand", value: expand.joined(separator: ","))]
        return try await get(CrowRecord.self, path: ["documents", doc, "tables", table, "records", id], query: items, doc: doc, revalidate: revalidate)
    }

    // MARK: -

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;?#")
        return set
    }()

    func url(path: [String], query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let segments = ["api"] + path.map { $0.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed) ?? $0 }
        components.percentEncodedPath = components.percentEncodedPath + "/" + segments.joined(separator: "/")
        if !query.isEmpty {
            components.queryItems = query
            // `+` would otherwise read as a space on the server.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }

    private var cache: ResponseCache { .shared }

    private func scope(_ doc: String) -> String { ResponseCache.scope(server: baseURL, doc: doc) }

    /// `doc` names the document a response belongs to, whose version decides when its cached copy is stale.
    private func get<T: Decodable>(_ type: T.Type, path: [String], query: [URLQueryItem] = [], doc: String? = nil, revalidate: Bool = false) async throws -> T {
        let url = url(path: path, query: query)
        let scope = doc.map(scope)
        let cached = cache.entry(for: url, in: scope)
        if !revalidate, let cached, let scope, let version = cache.version(of: scope), cached.version == version,
           let value = try? JSONDecoder().decode(T.self, from: cached.body) {
            return value
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        if let etag = cached?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code != .cancelled {
            // Offline or unreachable: show what we last saw.
            if let cached, let value = try? JSONDecoder().decode(T.self, from: cached.body) { return value }
            throw error
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if let scope, let version = http?.value(forHTTPHeaderField: "X-Crow-Version") {
            cache.setVersion(version, of: scope)
        }
        let version = scope.flatMap(cache.version(of:))
        if status == 304, let cached {
            let value = try JSONDecoder().decode(T.self, from: cached.body)
            if cached.version != version { cache.store(.init(version: version, etag: cached.etag, body: cached.body), for: url, in: scope) }
            return value
        }
        guard (200..<300).contains(status) else {
            throw (try? JSONDecoder().decode(APIError.self, from: data)) ?? APIError(status: status, message: "The server answered \(status).")
        }
        let value = try JSONDecoder().decode(T.self, from: data)
        cache.store(.init(version: version, etag: http?.value(forHTTPHeaderField: "ETag"), body: data), for: url, in: scope)
        return value
    }
}

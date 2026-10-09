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

    func documents() async throws -> [DocumentSummary] {
        try await get(DocumentList.self, path: ["documents"]).items
    }

    func document(_ doc: String) async throws -> DocumentSchema {
        try await get(DocumentSchema.self, path: ["documents", doc])
    }

    func records(doc: String, table: String, query: RecordQuery, page: Int, perPage: Int = 100) async throws -> RecordPage {
        var items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "perPage", value: String(perPage))]
        if !query.search.isEmpty { items.append(.init(name: "q", value: query.search)) }
        if !query.sort.isEmpty { items.append(.init(name: "sort", value: query.sort.joined(separator: ","))) }
        if !query.expand.isEmpty { items.append(.init(name: "expand", value: query.expand.joined(separator: ","))) }
        if !query.whereClause.isEmpty, let data = try? JSONEncoder().encode(query.whereClause) {
            items.append(.init(name: "where", value: String(decoding: data, as: UTF8.self)))
        }
        return try await get(RecordPage.self, path: ["documents", doc, "tables", table, "records"], query: items)
    }

    func record(doc: String, table: String, id: String, expand: [String]) async throws -> CrowRecord {
        let items = expand.isEmpty ? [] : [URLQueryItem(name: "expand", value: expand.joined(separator: ","))]
        return try await get(CrowRecord.self, path: ["documents", doc, "tables", table, "records", id], query: items)
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

    private func get<T: Decodable>(_ type: T.Type, path: [String], query: [URLQueryItem] = []) async throws -> T {
        var request = URLRequest(url: url(path: path, query: query))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw (try? JSONDecoder().decode(APIError.self, from: data)) ?? APIError(status: status, message: "The server answered \(status).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

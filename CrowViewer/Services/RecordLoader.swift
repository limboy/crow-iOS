import Foundation
import Observation

/// Pages through a table's records for one query, loading more as the list scrolls.
@Observable
final class RecordLoader {
    private(set) var records: [CrowRecord] = []
    private(set) var totalItems = 0
    private(set) var isLoading = false
    private(set) var error: Error?

    private var page = 0
    private var totalPages = 1
    private var generation = 0

    let api: CrowAPI
    let doc: String
    let table: String
    let perPage: Int
    var query: CrowAPI.RecordQuery

    init(api: CrowAPI, doc: String, table: String, query: CrowAPI.RecordQuery, perPage: Int = 100) {
        self.api = api
        self.doc = doc
        self.table = table
        self.query = query
        self.perPage = perPage
    }

    var hasMore: Bool { page < totalPages }
    var hasLoaded: Bool { page > 0 }

    /// `revalidate` checks the server for a newer document instead of trusting the cache (pull to refresh).
    func reload(revalidate: Bool = false) async {
        generation += 1
        page = 0
        totalPages = 1
        error = nil
        isLoading = false
        await loadNextPage(replacing: true, revalidate: revalidate)
    }

    func loadMoreIfNeeded(after record: CrowRecord) async {
        guard let index = records.firstIndex(where: { $0.id == record.id }), index >= records.count - 20 else { return }
        await loadNextPage(replacing: false)
    }

    func loadNextPage(replacing: Bool = false, revalidate: Bool = false) async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let gen = generation
        defer { if gen == generation { isLoading = false } }
        do {
            let result = try await api.records(doc: doc, table: table, query: query, page: page + 1, perPage: perPage, revalidate: revalidate)
            guard gen == generation else { return }
            let known = replacing ? [] : Set(records.map(\.id))
            let fresh = result.items.filter { !known.contains($0.id) }
            records = replacing ? fresh : records + fresh
            page = result.page
            totalPages = result.totalPages
            totalItems = result.totalItems
            error = nil
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch {
            guard gen == generation else { return }
            self.error = error
        }
    }
}

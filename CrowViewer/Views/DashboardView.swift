import Charts
import SwiftUI

/// A dashboard view: how records break down across each select field.
/// crow-service doesn't send a dashboard's chart config, so this charts every choice field instead.
struct DashboardView: View {
    let context: TableContext

    struct Bucket: Identifiable {
        let id: String
        let name: String
        let color: Color
        let count: Int
    }

    @State private var breakdowns: [String: [Bucket]] = [:]
    @State private var error: Error?

    private var groupFields: [FieldSchema] {
        context.table.fields.filter { [.select, .multiSelect, .checkbox].contains($0.type) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                card("Records") {
                    Text(context.table.recordCount.formatted())
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(groupFields) { field in
                    card("Records by \(field.name)") {
                        if let buckets = breakdowns[field.id] {
                            Chart(buckets) { bucket in
                                BarMark(x: .value("Records", bucket.count), y: .value(field.name, bucket.name))
                                    .foregroundStyle(bucket.color.gradient)
                                    .annotation(position: .trailing) {
                                        Text("\(bucket.count)").font(.caption2).foregroundStyle(.secondary)
                                    }
                            }
                            .chartXAxis(.hidden)
                            .frame(height: CGFloat(max(buckets.count, 1)) * 28 + 10)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                        }
                    }
                }
            }
            .padding()
            if let error {
                Text(error.localizedDescription).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .background(Color(.systemGroupedBackground))
        .task(id: context.table.id) { await load() }
        .refreshable { await load() }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    /// Counts come from `totalItems` of one-record pages, one request per bucket.
    private func load() async {
        for field in groupFields {
            var buckets: [(String, String, Color, JSONValue)] = []
            if field.type == .checkbox {
                buckets = [("y", "Checked", .accentColor, .bool(true)), ("n", "Unchecked", .gray, .bool(false))]
            } else {
                buckets = (field.choices ?? []).map { ($0.id, $0.name, $0.tint, .string($0.name)) }
                buckets.append(("_empty", "Empty", .gray.opacity(0.5), .null))
            }
            do {
                let counts = try await withThrowingTaskGroup(of: (Int, Int).self) { group in
                    for (i, bucket) in buckets.enumerated() {
                        var query = CrowAPI.RecordQuery()
                        query.whereClause = [field.name: bucket.3]
                        let api = context.api, doc = context.doc, table = context.table.name
                        group.addTask { (i, try await api.records(doc: doc, table: table, query: query, page: 1, perPage: 1).totalItems) }
                    }
                    var counts = Array(repeating: 0, count: buckets.count)
                    for try await (i, n) in group { counts[i] = n }
                    return counts
                }
                breakdowns[field.id] = buckets.enumerated()
                    .map { Bucket(id: $1.0, name: $1.1, color: $1.2, count: counts[$0]) }
                    .filter { $0.count > 0 || $0.id != "_empty" }
            } catch is CancellationError {
                return
            } catch {
                self.error = error
            }
        }
    }
}

import SwiftUI

/// A record as a card: optional cover, its title, and its other visible, non-empty fields.
struct RecordCard: View {
    let context: TableContext
    let record: CrowRecord
    var excluding: Set<String> = []

    private var cover: FieldSchema? { context.coverField }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover {
                coverImage(cover)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(CrowFormat.label(of: record, in: context.table))
                    .font(.headline)
                    .lineLimit(2)
                ForEach(details) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.name).font(.caption2).foregroundStyle(.secondary)
                        FieldValueView(field: field, record: record, schema: context.schema, lineLimit: 2)
                            .font(.subheadline)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private var details: [FieldSchema] {
        let fields = context.visibleFields
        return fields
            .dropFirst()
            .filter { !excluding.contains($0.id) && $0.id != cover?.id && !record[$0].isEmpty }
    }

    @ViewBuilder private func coverImage(_ field: FieldSchema) -> some View {
        let value = record[field]
        let url = (field.type == .video ? value["poster"]?.string : value.string).flatMap(URL.init(string:))
        let placeholder = Rectangle().fill(.quaternary)
            .overlay { Image(systemName: field.type.symbol).font(.title2).foregroundStyle(.tertiary) }
        if let ratio = context.coverAspectRatio {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    if let url { RemoteImage(url: url) } else { placeholder }
                }
                .clipped()
        } else if let url {
            // Original shape: the card grows to fit the image.
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary).frame(height: 160)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            placeholder.frame(height: 120)
        }
    }
}

struct GalleryView: View {
    let context: TableContext
    let loader: RecordLoader

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(loader.records) { record in
                    NavigationLink(value: context.route(for: record)) {
                        RecordCard(context: context, record: record)
                    }
                    .buttonStyle(.plain)
                    .task { await loader.loadMoreIfNeeded(after: record) }
                }
            }
            .padding()
            RecordCountFooter(loader: loader)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await loader.reload(revalidate: true) }
    }

    private var columns: [GridItem] {
        guard let count = context.prefs.columns else { return [GridItem(.adaptive(minimum: 160), spacing: 14, alignment: .top)] }
        return Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }
}

struct RecordCountFooter: View {
    let loader: RecordLoader

    var body: some View {
        HStack(spacing: 8) {
            Text("\(loader.totalItems) record\(loader.totalItems == 1 ? "" : "s")")
            if loader.isLoading { ProgressView().controlSize(.small) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.bottom, 24)
    }
}

// MARK: - Kanban

struct KanbanView: View {
    let context: TableContext
    let groupField: FieldSchema
    let query: CrowAPI.RecordQuery

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(groupField.choices ?? []) { choice in
                    KanbanColumn(context: context, groupField: groupField, choice: choice, query: query)
                }
                KanbanColumn(context: context, groupField: groupField, choice: nil, query: query)
            }
            .scrollTargetLayout()
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal, 4)
        .background(Color(.systemGroupedBackground))
    }
}

private struct KanbanColumn: View {
    let context: TableContext
    let groupField: FieldSchema
    let choice: Choice?
    let query: CrowAPI.RecordQuery

    @State private var loader: RecordLoader?

    private var columnQuery: CrowAPI.RecordQuery {
        var q = query
        q.whereClause[groupField.name] = choice.map { .string($0.name) } ?? .null
        return q
    }

    var body: some View {
        let hideEmptyBucket = choice == nil && loader?.hasLoaded == true && loader?.totalItems == 0
        if !hideEmptyBucket {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let choice {
                        ChoiceChip(name: choice.name, choice: choice)
                    } else {
                        ChoiceChip(name: "No \(groupField.name)", tint: .secondary)
                    }
                    Text("\(loader?.totalItems ?? 0)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if loader?.isLoading == true { ProgressView().controlSize(.mini) }
                }
                .padding(.horizontal, 4)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let loader {
                            ForEach(loader.records) { record in
                                NavigationLink(value: context.route(for: record)) {
                                    RecordCard(context: context, record: record, excluding: [groupField.id])
                                }
                                .buttonStyle(.plain)
                                .task { await loader.loadMoreIfNeeded(after: record) }
                            }
                            if let error = loader.error {
                                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .refreshable { await loader?.reload(revalidate: true) }
            }
            .padding(10)
            .frame(width: 290)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 20))
            .task(id: columnQuery) {
                let next = RecordLoader(api: context.api, doc: context.doc, table: context.table.name,
                                        query: columnQuery, perPage: 30)
                loader = next
                await next.reload()
            }
        }
    }
}

// MARK: - Calendar, as an agenda

struct AgendaView: View {
    let context: TableContext
    let loader: RecordLoader
    let dateField: FieldSchema

    private struct Day: Identifiable {
        let id: String
        let key: String
        let title: String
        var records: [CrowRecord]
    }

    private var days: [Day] {
        var result: [Day] = []
        for record in loader.records {
            let (key, title) = dayKey(record[dateField].string)
            if result.last?.key == key {
                result[result.count - 1].records.append(record)
            } else {
                result.append(Day(id: key + "#\(result.count)", key: key, title: title, records: [record]))
            }
        }
        return result
    }

    private func dayKey(_ value: String?) -> (String, String) {
        guard let value, !value.isEmpty else { return ("none", "No \(dateField.name)") }
        let date: Date? = dateField.type == .date ? CrowFormat.localDate(value)?.date : CrowFormat.instant(value)
        guard let date else { return (value, value) }
        let key = date.formatted(.iso8601.year().month().day())
        return (key, date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
    }

    var body: some View {
        List {
            ForEach(days) { day in
                Section(day.title) {
                    ForEach(day.records) { record in
                        NavigationLink(value: context.route(for: record)) {
                            AgendaRow(context: context, record: record, dateField: dateField)
                        }
                        .task { await loader.loadMoreIfNeeded(after: record) }
                    }
                }
            }
            Section {
                RecordCountFooter(loader: loader).frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        .refreshable { await loader.reload(revalidate: true) }
    }
}

private struct AgendaRow: View {
    let context: TableContext
    let record: CrowRecord
    let dateField: FieldSchema

    var body: some View {
        let cover = context.coverField
        HStack(spacing: 12) {
            if let cover, let url = record[cover].string.flatMap(URL.init(string:)) {
                RemoteImage(url: url).frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(CrowFormat.label(of: record, in: context.table)).font(.body.weight(.medium))
                let chips = context.table.fields.filter { $0.type == .select && !record[$0].isEmpty }.prefix(2)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(chips)) { field in
                            FieldValueView(field: field, record: record, schema: context.schema)
                        }
                    }
                }
            }
            Spacer()
            if let value = record[dateField].string, dateField.type == .date, CrowFormat.localDate(value)?.hasTime == true,
               let date = CrowFormat.localDate(value)?.date {
                Text(date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

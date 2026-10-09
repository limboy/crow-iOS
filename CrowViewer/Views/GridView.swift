import SwiftUI

/// The spreadsheet view: a pinned header row, scrolling both ways.
struct GridView: View {
    let context: TableContext
    let loader: RecordLoader

    private var fields: [FieldSchema] { context.visibleFields }
    private var rowHeight: CGFloat { context.view.rowHeight }
    private static let indexWidth: CGFloat = 48
    @State private var viewport: CGSize = .zero

    var body: some View {
        let fields = fields
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(loader.records.enumerated()), id: \.element.id) { index, record in
                        NavigationLink(value: context.route(for: record)) {
                            row(index: index, record: record, fields: fields)
                        }
                        .buttonStyle(GridRowButtonStyle())
                        .task { await loader.loadMoreIfNeeded(after: record) }
                    }
                    footer
                } header: {
                    header(fields)
                }
            }
            // A 2D scroll view centers content smaller than itself; keep it pinned to the top left.
            .frame(minWidth: viewport.width, minHeight: viewport.height, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
        .onScrollGeometryChange(for: CGSize.self) { $0.containerSize } action: { _, size in
            viewport = size
        }
        .refreshable { await loader.reload() }
    }

    private func header(_ fields: [FieldSchema]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.indexWidth)
            ForEach(fields) { field in
                Label(field.name, systemImage: field.type.symbol)
                    .labelStyle(HeaderLabelStyle())
                    .frame(width: Self.width(of: field, primary: field.id == fields.first?.id), alignment: .leading)
                    .padding(.horizontal, 10)
                    .overlay(alignment: .trailing) { VLine() }
            }
        }
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) { HLine() }
    }

    private func row(index: Int, record: CrowRecord, fields: [FieldSchema]) -> some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: Self.indexWidth)
            ForEach(fields) { field in
                let primary = field.id == fields.first?.id
                // An empty value renders no view at all, so the cell's size comes from Color.clear.
                Color.clear
                    .frame(width: Self.width(of: field, primary: primary) + 20)
                    .overlay(alignment: field.type == .number ? .trailing : .leading) {
                        FieldValueView(field: field, record: record, schema: context.schema,
                                       lineLimit: rowHeight > 44 ? Int((rowHeight - 16) / 18) : 1,
                                       thumbnail: rowHeight - 14)
                            .font(primary ? .subheadline.weight(.semibold) : .subheadline)
                            .padding(.horizontal, 10)
                    }
                    .clipped()
                    .overlay(alignment: .trailing) { VLine() }
            }
        }
        .frame(height: rowHeight)
        .contentShape(.rect)
        .overlay(alignment: .bottom) { HLine() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(loader.totalItems) record\(loader.totalItems == 1 ? "" : "s")")
            if loader.isLoading { ProgressView().controlSize(.small) }
            if loader.error != nil {
                Button("Retry") { Task { await loader.loadNextPage() } }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.leading, Self.indexWidth + 10)
        .frame(height: 44)
    }

    static func width(of field: FieldSchema, primary: Bool) -> CGFloat {
        if primary { return 180 }
        switch field.type {
        case .checkbox: return 72
        case .rating: return 110
        case .number: return 100
        case .image, .video, .audio: return 90
        case .date, .createdTime, .lastModifiedTime: return 140
        case .select: return 130
        case .multiSelect, .relation, .url, .attachment: return 190
        case .text, .unknown: return 220
        }
    }
}

private struct HeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.caption2).foregroundStyle(.secondary)
            configuration.title.font(.caption.weight(.semibold)).lineLimit(1)
        }
    }
}

private struct GridRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.12) : .clear)
    }
}

private struct VLine: View {
    var body: some View { Rectangle().fill(.separator).frame(width: 0.5) }
}

private struct HLine: View {
    var body: some View { Rectangle().fill(.separator).frame(height: 0.5) }
}

import AVKit
import SwiftUI

/// Every field of one record, with media players and links to related records.
struct RecordDetailView: View {
    let api: CrowAPI
    let doc: String
    let table: String
    let recordId: String

    @State private var schema: DocumentSchema?
    @State private var record: CrowRecord?
    @State private var error: Error?
    @State private var zoomedImage: URL?

    private var tableSchema: TableSchema? { schema?.table(named: table) }

    var body: some View {
        Group {
            if let record, let tableSchema {
                content(record, tableSchema)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't Load Record", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await load() } }.buttonStyle(.glassProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(record.map { CrowFormat.label(of: $0, in: tableSchema) } ?? "")
        .navigationSubtitle(table)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if record != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: webURL)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $zoomedImage) { url in
            ImageViewer(url: url)
        }
    }

    /// The same record on crow-service's own web pages.
    private var webURL: URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#;"))
        let path = [doc, table, recordId].map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        return URL(string: api.baseURL.absoluteString + "/" + path.joined(separator: "/")) ?? api.baseURL
    }

    private func load() async {
        do {
            let schema = try await api.document(doc)
            let fields = schema.table(named: table)?.fields ?? []
            let expand = fields.filter { $0.type == .relation }.map(\.name)
            record = try await api.record(doc: doc, table: table, id: recordId, expand: expand)
            self.schema = schema
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    // MARK: - Layout

    private func content(_ record: CrowRecord, _ table: TableSchema) -> some View {
        let hero = table.fields.first { $0.type == .image && !record[$0].isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let hero, let url = record[hero].string.flatMap(URL.init(string:)) {
                    Button { zoomedImage = url } label: {
                        RemoteImage(url: url, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .clipShape(.rect(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }

                Text(CrowFormat.label(of: record, in: table))
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)
                    .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(table.fields.filter { $0.id != hero?.id }) { field in
                        FieldSection(field: field) {
                            detailValue(field, record)
                        }
                        Divider()
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let created = CrowFormat.instant(record.createdAt) {
                        Text("Created \(created.formatted(date: .abbreviated, time: .shortened))")
                    }
                    if record.updatedAt != record.createdAt, let updated = CrowFormat.instant(record.updatedAt) {
                        Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await load() }
    }

    @ViewBuilder private func detailValue(_ field: FieldSchema, _ record: CrowRecord) -> some View {
        let value = record[field]
        if value.isEmpty && field.type != .checkbox {
            Text("Empty").foregroundStyle(.tertiary)
        } else {
            switch field.type {
            case .text, .unknown:
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let swatch = value.string.flatMap(Color.init(hex:)) {
                        RoundedRectangle(cornerRadius: 6).fill(swatch)
                            .frame(width: 44, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))
                    }
                    Text(value.text).textSelection(.enabled)
                }
            case .url:
                if let s = value.string, let url = URL(string: s) {
                    Link(destination: url) {
                        Label(s, systemImage: "arrow.up.right.square").multilineTextAlignment(.leading)
                    }
                } else {
                    Text(value.text)
                }
            case .image:
                if let url = value.string.flatMap(URL.init(string:)) {
                    Button { zoomedImage = url } label: {
                        RemoteImage(url: url, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                            .clipShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            case .video:
                if let url = value["url"]?.string.flatMap(URL.init(string:)) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 14))
                    if let name = value["name"]?.string {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .audio:
                if let url = value.string.flatMap(URL.init(string:)) {
                    AudioPlayerView(url: url)
                }
            case .attachment:
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((value.array ?? []).enumerated()), id: \.offset) { _, file in
                        if let url = file["url"]?.string.flatMap(URL.init(string:)) {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "doc.fill").foregroundStyle(.tint)
                                    Text(file["name"]?.string ?? url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    if let size = file["size"]?.number {
                                        Text(CrowFormat.fileSize(size)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            case .relation:
                relationList(field, record)
            case .rating:
                RatingView(rating: Int(value.number ?? 0)).font(.title3)
            case .checkbox:
                Label(value.bool == true ? "Checked" : "Unchecked",
                      systemImage: value.bool == true ? "checkmark.square.fill" : "square")
                    .foregroundStyle(value.bool == true ? Color.accentColor : .secondary)
            case .select, .multiSelect:
                FieldValueView(field: field, record: record, schema: schema, lineLimit: 10)
            case .number, .date, .createdTime, .lastModifiedTime:
                FieldValueView(field: field, record: record, schema: schema).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private func relationList(_ field: FieldSchema, _ record: CrowRecord) -> some View {
        let targetName = field.relation?.table
        let target = schema?.table(named: targetName)
        let linked = record.expand?[field.name] ?? []
        VStack(spacing: 8) {
            ForEach(linked) { other in
                if let targetName {
                    NavigationLink(value: Route.record(doc: doc, table: targetName, id: other.id)) {
                        HStack {
                            Text(CrowFormat.label(of: other, in: target)).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FieldSection<Content: View>: View {
    let field: FieldSchema
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(field.name, systemImage: field.type.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }
}

private struct AudioPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        Button {
            let player = player ?? AVPlayer(url: url)
            self.player = player
            if isPlaying { player.pause() } else { player.play() }
            isPlaying.toggle()
        } label: {
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
        }
        .buttonStyle(.glass)
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard (note.object as? AVPlayerItem) === player?.currentItem else { return }
            isPlaying = false
            player?.seek(to: .zero)
        }
        .onDisappear { player?.pause(); isPlaying = false }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// A full-screen image with pinch to zoom.
private struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            RemoteImage(url: url, contentMode: .fit)
                .scaleEffect(scale * pinch)
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in scale = min(max(scale * value.magnification, 1), 6) }
                )
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5 } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

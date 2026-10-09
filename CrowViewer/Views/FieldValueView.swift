import SwiftUI

/// A record's value for one field, as a grid cell or card line.
struct FieldValueView: View {
    let field: FieldSchema
    let record: CrowRecord
    var schema: DocumentSchema?
    /// Cells stay on one line; cards may wrap a little.
    var lineLimit = 1
    var thumbnail: CGFloat = 28

    private var value: JSONValue { record[field] }

    var body: some View {
        switch field.type {
        case .select:
            if let name = value.string {
                ChoiceChip(name: name, choice: field.choice(named: name))
            }
        case .multiSelect:
            let names = value.array?.compactMap(\.string) ?? []
            if !names.isEmpty {
                ChipRow(names: names, field: field, wraps: lineLimit > 1)
            }
        case .checkbox:
            Image(systemName: value.bool == true ? "checkmark.square.fill" : "square")
                .foregroundStyle(value.bool == true ? Color.accentColor : Color.secondary.opacity(0.5))
                .accessibilityLabel(value.bool == true ? "Checked" : "Unchecked")
        case .rating:
            if let n = value.number, n > 0 { RatingView(rating: Int(n)) }
        case .number:
            if let n = value.number {
                Text(n.formatted()).monospacedDigit()
            }
        case .date:
            if let s = value.string { Text(CrowFormat.dateText(s)).lineLimit(1) }
        case .createdTime, .lastModifiedTime:
            if let s = value.string { Text(CrowFormat.timestampText(s, format: field.dateFormat)).lineLimit(1) }
        case .url:
            if let s = value.string { Text(s).foregroundStyle(.tint).lineLimit(1) }
        case .image:
            if let s = value.string, let url = URL(string: s) {
                RemoteImage(url: url).frame(width: thumbnail, height: thumbnail).clipShape(.rect(cornerRadius: 5))
            }
        case .video:
            if let poster = value["poster"]?.string, let url = URL(string: poster) {
                RemoteImage(url: url).frame(width: thumbnail, height: thumbnail).clipShape(.rect(cornerRadius: 5))
                    .overlay { Image(systemName: "play.fill").font(.caption2).foregroundStyle(.white).shadow(radius: 2) }
            } else if !value.isEmpty {
                Label(value["name"]?.string ?? "Video", systemImage: "film").lineLimit(1)
            }
        case .audio:
            if !value.isEmpty { Label("Audio", systemImage: "waveform").foregroundStyle(.secondary) }
        case .attachment:
            let files = value.array ?? []
            if !files.isEmpty {
                Label(files.count == 1 ? files[0]["name"]?.string ?? "1 file" : "\(files.count) files", systemImage: "paperclip")
                    .lineLimit(1)
            }
        case .relation:
            let labels = relationLabels
            if !labels.isEmpty {
                ChipRow(names: labels, field: nil, wraps: lineLimit > 1)
            }
        case .text, .unknown:
            if let s = value.string, !s.isEmpty {
                HStack(spacing: 6) {
                    if let swatch = Color(hex: s) {
                        RoundedRectangle(cornerRadius: 4).fill(swatch)
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15)))
                    }
                    Text(s).lineLimit(lineLimit)
                }
            } else if field.type == .unknown, !value.isEmpty {
                Text(value.text).lineLimit(lineLimit)
            }
        }
    }

    private var relationLabels: [String] {
        let ids = value.array?.compactMap(\.string) ?? []
        guard let linked = record.expand?[field.name] else {
            return ids.isEmpty ? [] : [ids.count == 1 ? "1 link" : "\(ids.count) links"]
        }
        let target = schema?.table(named: field.relation?.table)
        return linked.map { CrowFormat.label(of: $0, in: target) }
    }
}

struct ChoiceChip: View {
    let name: String
    var choice: Choice?
    var tint: Color? = nil

    var body: some View {
        let color = tint ?? choice?.tint ?? .gray
        Text(name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.16), in: .capsule)
    }
}

struct ChipRow: View {
    let names: [String]
    let field: FieldSchema?
    var wraps = false

    var body: some View {
        if wraps {
            FlowLayout(spacing: 4) { chips }
        } else {
            HStack(spacing: 4) { chips }.fixedSize()
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(Array(names.enumerated()), id: \.offset) { _, name in
            ChoiceChip(name: name, choice: field?.choice(named: name), tint: field == nil ? .secondary : nil)
        }
    }
}

struct RatingView: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .foregroundStyle(i <= rating ? Color.orange : Color.secondary.opacity(0.35))
            }
        }
        .font(.caption)
        .accessibilityLabel("\(rating) of 5 stars")
    }
}

struct RemoteImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    var body: some View {
        CachedAsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            default:
                Rectangle().fill(.quaternary)
            }
        }
    }
}

/// Lays chips out in rows, wrapping as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

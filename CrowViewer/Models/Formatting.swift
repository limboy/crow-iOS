import SwiftUI

extension Choice {
    /// Crow's ten choice colors.
    var tint: Color { Self.tint(for: color) }

    static func tint(for name: String) -> Color {
        switch name {
        case "red": .red
        case "orange": .orange
        case "amber": Color(red: 0.85, green: 0.6, blue: 0.05)
        case "green": .green
        case "teal": .teal
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        default: .gray
        }
    }
}

extension Color {
    /// `#RGB` / `#RRGGBB` text, which documents often store in a text field.
    init?(hex text: String) {
        var hex = text.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum CrowFormat {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func instant(_ text: String) -> Date? { iso.date(from: text) ?? isoPlain.date(from: text) }

    /// A `date` field: `YYYY-MM-DD` or `YYYY-MM-DDTHH:mm` local wall-clock time.
    static func localDate(_ text: String) -> (date: Date, hasTime: Bool)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let d = f.date(from: text) { return (d, true) }
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: text) { return (d, false) }
        return nil
    }

    static func dateText(_ text: String) -> String {
        guard let (date, hasTime) = localDate(text) else { return text }
        return hasTime
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// `createdTime` / `lastModifiedTime`, honoring the field's `dateFormat`.
    static func timestampText(_ text: String, format: String?) -> String {
        guard let date = instant(text) else { return text }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let format = format ?? "slash"
        let sep = format.hasPrefix("dash") ? "-" : "/"
        f.dateFormat = "yyyy\(sep)MM\(sep)dd" + (format.hasSuffix("Time") || format.hasSuffix("TimeZone") ? " HH:mm" : "")
        var out = f.string(from: date)
        if format.hasSuffix("TimeZone") {
            let seconds = TimeZone.current.secondsFromGMT(for: date)
            let hours = seconds / 3600, minutes = abs(seconds / 60) % 60
            out += " (GMT\(hours >= 0 ? "+" : "")\(hours)\(minutes > 0 ? String(format: ":%02d", minutes) : ""))"
        }
        return out
    }

    static func fileSize(_ bytes: Double) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }

    /// The label a linked record reads as: its table's first field, like the app.
    static func label(of record: CrowRecord, in table: TableSchema?) -> String {
        guard let primary = table?.fields.first, ![.relation, .video, .attachment].contains(primary.type) else {
            return "Untitled"
        }
        let value = record[primary]
        if value.isEmpty { return "Untitled" }
        if primary.type == .checkbox { return "Checked" }
        if [.image, .audio].contains(primary.type) { return "Untitled" }
        return value.text
    }
}

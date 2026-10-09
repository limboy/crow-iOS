import Foundation

// Shapes returned by crow-service's /api. See crow-service/README.md.

struct DocumentList: Decodable { let items: [DocumentSummary] }

struct DocumentSummary: Decodable, Identifiable, Hashable {
    let name: String
    let projectId: String
    let updatedAt: String?
    /// Changes whenever the document does. Sent by newer crow-service.
    let version: String?
    let tables: [TableSummary]

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, updatedAt, version, tables
        case projectId = "id"
    }
}

struct TableSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let recordCount: Int
}

struct DocumentSchema: Decodable, Hashable {
    let name: String
    let tables: [TableSchema]

    func table(named name: String?) -> TableSchema? {
        guard let name else { return nil }
        return tables.first { $0.name == name } ?? tables.first { $0.name.lowercased() == name.lowercased() }
    }
}

struct TableSchema: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let recordCount: Int
    let fields: [FieldSchema]
    let views: [ViewSchema]

    func field(id: String?) -> FieldSchema? { fields.first { $0.id == id } }
    func field(named name: String) -> FieldSchema? { fields.first { $0.name == name } }
}

enum FieldType: String, Decodable, Hashable {
    case text, number, select, multiSelect, date, checkbox, url, image, audio, video
    case relation, rating, attachment, createdTime, lastModifiedTime
    case unknown

    init(from decoder: Decoder) throws {
        self = FieldType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .select: "chevron.down.circle"
        case .multiSelect: "list.bullet"
        case .date: "calendar"
        case .checkbox: "checkmark.square"
        case .url: "link"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .relation: "arrow.up.right.square"
        case .rating: "star"
        case .attachment: "paperclip"
        case .createdTime, .lastModifiedTime: "clock"
        case .unknown: "questionmark.square.dashed"
        }
    }

    var isSortable: Bool { ![.image, .audio, .video, .attachment, .relation, .unknown].contains(self) }
}

struct Choice: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let color: String
}

struct RelationInfo: Decodable, Hashable {
    let table: String?
    let multiple: Bool
}

struct FieldSchema: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let type: FieldType
    let choices: [Choice]?
    let relation: RelationInfo?
    let dateFormat: String?

    func choice(named name: String) -> Choice? { choices?.first { $0.name == name } }
}

enum ViewType: String, Hashable {
    case table, kanban, gallery, calendar, dashboard
}

struct ViewSchema: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let type: String
    /// Not sent by crow-service today; used when present, otherwise the app infers settings.
    let config: JSONValue?

    var viewType: ViewType? { ViewType(rawValue: type) }

    var symbol: String {
        switch viewType {
        case .table: "tablecells"
        case .kanban: "rectangle.split.3x1"
        case .gallery: "square.grid.2x2"
        case .calendar: "calendar"
        case .dashboard: "chart.bar.xaxis"
        case nil: "questionmark.square.dashed"
        }
    }

    func configString(_ key: String) -> String? { config?[key]?.string }
    var hiddenFieldIds: Set<String> { Set(config?["hiddenFieldIds"]?.array?.compactMap(\.string) ?? []) }
}

struct RecordPage: Decodable {
    let page: Int
    let perPage: Int
    let totalItems: Int
    let totalPages: Int
    let items: [CrowRecord]
}

struct CrowRecord: Decodable, Identifiable, Hashable {
    let id: String
    let createdAt: String
    let updatedAt: String
    let fields: [String: JSONValue]
    let expand: [String: [CrowRecord]]?

    subscript(field: FieldSchema) -> JSONValue { fields[field.name] ?? .null }
}

struct APIError: Decodable, Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

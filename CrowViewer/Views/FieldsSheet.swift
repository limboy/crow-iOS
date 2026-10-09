import SwiftUI

/// How a view looks on this device. Every value left `nil` falls back to the saved view's config,
/// so a fresh install shows views exactly as Crow saved them. Remembered per document, table and view.
struct ViewPrefs: Codable, Equatable {
    var hiddenFields: Set<String>?
    /// Gallery columns; nil fits as many as the width allows.
    var columns: Int?
    /// The image field shown on cards: a field id, `ViewPrefs.noCover`, or nil for the view's own.
    var coverFieldId: String?
    /// Image shape as `"w:h"`, or `ViewPrefs.fitImage` for each image's own shape.
    var imageAspect: String?

    static let noCover = "none"
    static let fitImage = "fit"

    var isCustomized: Bool { self != ViewPrefs() }

    private static func key(doc: String, table: TableSchema, view: ViewSchema) -> String {
        "viewPrefs/\(doc)/\(table.id)/\(view.id)"
    }

    static func load(doc: String, table: TableSchema, view: ViewSchema) -> ViewPrefs {
        guard let data = UserDefaults.standard.data(forKey: key(doc: doc, table: table, view: view)),
              let prefs = try? JSONDecoder().decode(ViewPrefs.self, from: data) else { return ViewPrefs() }
        return prefs
    }

    func save(doc: String, table: TableSchema, view: ViewSchema) {
        let key = Self.key(doc: doc, table: table, view: view)
        if isCustomized, let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Image shapes offered for card covers, as width:height.
private let imageShapes: [(label: String, value: String)] = [
    ("Wide 16:9", "16:9"),
    ("Landscape 4:3", "4:3"),
    ("Square 1:1", "1:1"),
    ("Portrait 3:4", "3:4"),
    ("Tall 3:5", "3:5"),
    ("Original", ViewPrefs.fitImage)
]

/// Customizes a view: which fields show and, for card views, how the cards are laid out.
struct FieldsSheet: View {
    let context: TableContext
    @Binding var prefs: ViewPrefs

    @Environment(\.dismiss) private var dismiss

    private var table: TableSchema { context.table }
    private var view: ViewSchema { context.view }
    private var primary: FieldSchema? { table.fields.first }
    private var others: [FieldSchema] { Array(table.fields.dropFirst()) }
    private var hidden: Set<String> { context.hiddenFields }
    private var isCardView: Bool { view.viewType == .gallery || view.viewType == .kanban }

    var body: some View {
        NavigationStack {
            List {
                if isCardView { layoutSection }
                if let primary {
                    Section {
                        Label(primary.name, systemImage: primary.type.symbol)
                            .badge(Text("Always shown"))
                    } footer: {
                        Text("The first field names each record.")
                    }
                }
                fieldsSection
                if prefs.isCustomized {
                    Section {
                        Button("Reset to Saved View", systemImage: "arrow.uturn.backward") { prefs = ViewPrefs() }
                    } footer: {
                        Text("Goes back to how \"\(view.name)\" looks in Crow.")
                    }
                }
            }
            .navigationTitle(isCardView ? "Customize" : "Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Layout

    @ViewBuilder private var layoutSection: some View {
        let imageFields = table.fields.filter { [.image, .video].contains($0.type) }
        Section("Layout") {
            if view.viewType == .gallery {
                Picker("Columns", selection: $prefs.columns) {
                    Text("Auto").tag(Int?.none)
                    ForEach(1...3, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
            }
            Picker("Image", selection: coverBinding) {
                Text("None").tag(ViewPrefs.noCover)
                ForEach(imageFields) { field in
                    Label(field.name, systemImage: field.type.symbol).tag(field.id)
                }
            }
            if context.coverField != nil {
                Picker("Image Shape", selection: aspectBinding) {
                    ForEach(imageShapes, id: \.value) { Text($0.label).tag($0.value) }
                    if !imageShapes.contains(where: { $0.value == aspectBinding.wrappedValue }) {
                        Text(aspectBinding.wrappedValue).tag(aspectBinding.wrappedValue)
                    }
                }
            }
        }
    }

    /// Reads the effective cover; writing the view's own default stores nil so it keeps following Crow.
    private var coverBinding: Binding<String> {
        Binding(
            get: { context.coverField?.id ?? ViewPrefs.noCover },
            set: { id in
                prefs.coverFieldId = id == view.coverField(in: table)?.id ? nil : id
            }
        )
    }

    private var aspectBinding: Binding<String> {
        Binding(
            get: { prefs.imageAspect ?? view.configString("imageAspectRatio") ?? (view.viewType == .kanban ? "16:9" : "4:3") },
            set: { prefs.imageAspect = $0 }
        )
    }

    // MARK: - Fields

    private var fieldsSection: some View {
        Section {
            ForEach(others) { field in
                Toggle(isOn: Binding(
                    get: { !hidden.contains(field.id) },
                    set: { shown in
                        var next = hidden
                        if shown { next.remove(field.id) } else { next.insert(field.id) }
                        prefs.hiddenFields = next
                    }
                )) {
                    Label(field.name, systemImage: field.type.symbol)
                }
            }
        } header: {
            HStack {
                Text("\(others.count - others.filter { hidden.contains($0.id) }.count) of \(others.count) shown")
                Spacer()
                Button("Show All") { prefs.hiddenFields = hidden.subtracting(others.map(\.id)) }
                    .disabled(others.allSatisfy { !hidden.contains($0.id) })
                Text("·").foregroundStyle(.tertiary)
                Button("Hide All") { prefs.hiddenFields = hidden.union(others.map(\.id)) }
                    .disabled(others.allSatisfy { hidden.contains($0.id) })
            }
            .font(.footnote)
            .textCase(nil)
        } footer: {
            if isCardView {
                Text("Cards leave out fields that are empty for that record, and the field used as the image.")
            }
        }
    }
}

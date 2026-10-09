import SwiftUI

/// One document: a table at a time, shown through one of its saved views.
struct DocumentView: View {
    let api: CrowAPI
    let name: String

    @State private var schema: DocumentSchema?
    @State private var error: Error?
    @SceneStorage("table") private var tableName = ""
    @State private var viewId: String?

    @State private var searchText = ""
    @State private var search = ""
    @State private var sortOverride: SortOption?
    @State private var filter: FilterOption?
    @State private var prefs = ViewPrefs()
    @State private var showingFields = false

    var body: some View {
        Group {
            if let schema, let table {
                TableContent(api: api, doc: name, schema: schema, table: table, view: view,
                             prefs: prefs, query: query(for: table))
                    .id(table.id)
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't Open \(name)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await loadSchema() } }.buttonStyle(.glassProminent)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(table?.name ?? name)
        .navigationSubtitle(table == nil ? "" : name)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(TableSwitcher(tables: schema?.tables ?? [], current: table?.id, select: select(table:)))
        .toolbar { toolbar }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search records")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { search = searchText.trimmingCharacters(in: .whitespaces) }
        }
        .task { await loadSchema() }
        .onChange(of: prefsKey, initial: true) { loadPrefs() }
        .sheet(isPresented: $showingFields) {
            if let schema, let table {
                FieldsSheet(
                    context: TableContext(api: api, doc: name, schema: schema, table: table, view: view, prefs: prefs),
                    prefs: Binding(get: { prefs }, set: { savePrefs($0) })
                )
            }
        }
    }

    // MARK: - Selection

    private var table: TableSchema? {
        guard let schema else { return nil }
        return schema.tables.first { $0.name == tableName } ?? schema.tables.first
    }

    private var views: [ViewSchema] {
        let saved = table?.views ?? []
        return saved.isEmpty ? [ViewSchema(id: "_grid", name: "Grid", type: "table", config: nil)] : saved
    }

    private var view: ViewSchema {
        views.first { $0.id == viewId } ?? views.first { $0.viewType != nil && $0.viewType != .dashboard } ?? views[0]
    }

    private func select(table t: TableSchema) {
        tableName = t.name
        viewId = nil
        sortOverride = nil
        filter = nil
    }

    private func query(for table: TableSchema) -> CrowAPI.RecordQuery {
        var q = CrowAPI.RecordQuery()
        q.search = search
        q.expand = table.fields.filter { $0.type == .relation }.map(\.name)
        if let sortOverride {
            q.sort = [sortOverride.descending ? "-\(sortOverride.field)" : sortOverride.field]
        } else {
            q.sort = view.sorts(in: table)
        }
        if let filter { q.whereClause = [filter.field: filter.value] }
        return q
    }

    private var prefsKey: String { "\(table?.id ?? "")/\(view.id)" }

    private func loadPrefs() {
        guard let table else { return }
        prefs = ViewPrefs.load(doc: name, table: table, view: view)
    }

    private func savePrefs(_ next: ViewPrefs) {
        guard let table else { return }
        prefs = next
        next.save(doc: name, table: table, view: view)
    }

    private func loadSchema() async {
        do {
            schema = try await api.document(name)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let table {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("View", selection: Binding(get: { view.id }, set: { viewId = $0 })) {
                        ForEach(views) { v in
                            Label(v.name, systemImage: v.symbol).tag(v.id)
                        }
                    }
                } label: {
                    Label("View", systemImage: view.symbol)
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if view.viewType != .dashboard {
                        Button([.gallery, .kanban].contains(view.viewType) ? "Customize Cards" : "Fields",
                               systemImage: "eye") { showingFields = true }
                        Divider()
                    }
                    sortMenu(table)
                    filterMenu(table)
                } label: {
                    Label("Sort & Filter", systemImage: "line.3.horizontal.decrease")
                        .symbolVariant(sortOverride != nil || filter != nil ? .fill : .none)
                }
            }
        }
    }

    @ViewBuilder private func sortMenu(_ table: TableSchema) -> some View {
        Menu {
            Button {
                sortOverride = nil
            } label: {
                Label(view.sorts(in: table).isEmpty ? "Document Order" : "View's Sort", systemImage: sortOverride == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(table.fields.filter(\.type.isSortable)) { field in
                Menu {
                    ForEach([false, true], id: \.self) { desc in
                        let option = SortOption(field: field.name, descending: desc)
                        Button {
                            sortOverride = option
                        } label: {
                            Label(desc ? "Descending" : "Ascending",
                                  systemImage: sortOverride == option ? "checkmark" : (desc ? "arrow.down" : "arrow.up"))
                        }
                    }
                } label: {
                    Label(field.name, systemImage: sortOverride?.field == field.name ? "checkmark" : field.type.symbol)
                }
            }
        } label: {
            Label(sortOverride.map { "Sorted by \($0.field)" } ?? "Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder private func filterMenu(_ table: TableSchema) -> some View {
        let fields = table.fields.filter { [.select, .multiSelect, .checkbox].contains($0.type) }
        if !fields.isEmpty {
            Menu {
                if filter != nil {
                    Button("Clear Filter", systemImage: "xmark.circle", role: .destructive) { filter = nil }
                    Divider()
                }
                ForEach(fields) { field in
                    Menu {
                        if field.type == .checkbox {
                            filterButton(FilterOption(field: field.name, value: .bool(true), label: "Checked"))
                        } else {
                            ForEach(field.choices ?? []) { choice in
                                filterButton(FilterOption(field: field.name, value: .string(choice.name), label: choice.name))
                            }
                            filterButton(FilterOption(field: field.name, value: .null, label: "Empty"))
                        }
                    } label: {
                        Label(field.name, systemImage: filter?.field == field.name ? "checkmark" : field.type.symbol)
                    }
                }
            } label: {
                Label(filter.map { "\($0.field): \($0.label)" } ?? "Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func filterButton(_ option: FilterOption) -> some View {
        Button {
            filter = filter == option ? nil : option
        } label: {
            Label(option.label, systemImage: filter == option ? "checkmark" : "")
        }
    }
}

struct SortOption: Hashable {
    let field: String
    let descending: Bool
}

struct FilterOption: Hashable {
    let field: String
    let value: JSONValue
    let label: String
}

// MARK: - View config, falling back to sensible guesses when the server doesn't send it

extension ViewSchema {
    func sorts(in table: TableSchema) -> [String] {
        (config?["sorts"]?.array ?? []).compactMap { sort in
            guard let field = table.field(id: sort["fieldId"]?.string) else { return nil }
            return sort["direction"]?.string == "desc" ? "-\(field.name)" : field.name
        }
    }

    func groupField(in table: TableSchema) -> FieldSchema? {
        if let field = table.field(id: configString("groupByFieldId")), [.select, .multiSelect].contains(field.type) { return field }
        return table.fields.first { $0.type == .select } ?? table.fields.first { $0.type == .multiSelect }
    }

    func coverField(in table: TableSchema) -> FieldSchema? {
        let key = viewType == .kanban ? "imageFieldId" : "coverFieldId"
        if let field = table.field(id: configString(key)), [.image, .video].contains(field.type) { return field }
        return table.fields.first { $0.type == .image } ?? table.fields.first { $0.type == .video }
    }

    func dateField(in table: TableSchema) -> FieldSchema? {
        let dated: [FieldType] = [.date, .createdTime, .lastModifiedTime]
        if let field = table.field(id: configString("dateFieldId")), dated.contains(field.type) { return field }
        return table.fields.first { dated.contains($0.type) }
    }

    /// `imageAspectRatio` like `"3:5"`, as width ÷ height.
    var coverAspectRatio: CGFloat {
        let parts = (configString("imageAspectRatio") ?? "").split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return viewType == .kanban ? 16.0 / 9.0 : 4.0 / 3.0 }
        return parts[0] / parts[1]
    }

    var rowHeight: CGFloat {
        switch configString("rowHeight") {
        case "medium": 64
        case "tall": 92
        case "extraTall": 128
        default: 44
        }
    }
}

/// Picks the renderer for the selected view.
private struct TableContent: View {
    let api: CrowAPI
    let doc: String
    let schema: DocumentSchema
    let table: TableSchema
    let view: ViewSchema
    let prefs: ViewPrefs
    let query: CrowAPI.RecordQuery

    var body: some View {
        let context = TableContext(api: api, doc: doc, schema: schema, table: table, view: view, prefs: prefs)
        switch view.viewType {
        case .kanban:
            if let group = view.groupField(in: table) {
                KanbanView(context: context, groupField: group, query: query)
            } else {
                ContentUnavailableView("No Field to Group By", systemImage: "rectangle.split.3x1",
                                       description: Text("A board needs a single- or multi-select field."))
            }
        case .gallery:
            LoadedRecords(context: context, query: query) { loader in GalleryView(context: context, loader: loader) }
        case .calendar:
            if let dateField = view.dateField(in: table) {
                LoadedRecords(context: context, query: agendaQuery(dateField)) { loader in
                    AgendaView(context: context, loader: loader, dateField: dateField)
                }
            } else {
                LoadedRecords(context: context, query: query) { loader in GridView(context: context, loader: loader) }
            }
        case .dashboard:
            DashboardView(context: context)
        default:
            LoadedRecords(context: context, query: query) { loader in GridView(context: context, loader: loader) }
        }
    }

    private func agendaQuery(_ dateField: FieldSchema) -> CrowAPI.RecordQuery {
        var q = query
        if q.sort.isEmpty { q.sort = [dateField.name] }
        return q
    }
}

struct TableContext {
    let api: CrowAPI
    let doc: String
    let schema: DocumentSchema
    let table: TableSchema
    let view: ViewSchema
    let prefs: ViewPrefs

    var hiddenFields: Set<String> { prefs.hiddenFields ?? view.hiddenFieldIds }

    /// The primary field always shows; the rest follow the field picker.
    var visibleFields: [FieldSchema] {
        table.fields.enumerated().filter { $0.offset == 0 || !hiddenFields.contains($0.element.id) }.map(\.element)
    }

    /// The image shown on cards, if any.
    var coverField: FieldSchema? {
        switch prefs.coverFieldId {
        case ViewPrefs.noCover: nil
        case let id?: table.field(id: id) ?? view.coverField(in: table)
        case nil: view.coverField(in: table)
        }
    }

    /// Cover width ÷ height, or nil to show each image at its own shape.
    var coverAspectRatio: CGFloat? {
        guard let aspect = prefs.imageAspect else { return view.coverAspectRatio }
        if aspect == ViewPrefs.fitImage { return nil }
        let parts = aspect.split(separator: ":").compactMap { Double($0) }
        return parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : view.coverAspectRatio
    }

    func route(for record: CrowRecord) -> Route { .record(doc: doc, table: table.name, id: record.id) }
}

/// Owns a RecordLoader for the current query and rebuilds it whenever the query changes.
struct LoadedRecords<Content: View>: View {
    let context: TableContext
    let query: CrowAPI.RecordQuery
    @ViewBuilder let content: (RecordLoader) -> Content

    @State private var loader: RecordLoader?

    var body: some View {
        Group {
            if let loader {
                if let error = loader.error, loader.records.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Load Records", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Retry") { Task { await loader.reload() } }.buttonStyle(.glassProminent)
                    }
                } else if loader.hasLoaded, loader.records.isEmpty {
                    if query.search.isEmpty {
                        ContentUnavailableView("No Records", systemImage: "tray")
                    } else {
                        ContentUnavailableView.search(text: query.search)
                    }
                } else if !loader.hasLoaded {
                    ProgressView()
                } else {
                    content(loader)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: query) {
            let next = RecordLoader(api: context.api, doc: context.doc, table: context.table.name, query: query)
            if loader == nil || loader?.query != query { loader = next } else { return }
            await next.reload()
        }
    }
}

/// Lets the title switch tables, when there's more than one.
private struct TableSwitcher: ViewModifier {
    let tables: [TableSchema]
    let current: String?
    let select: (TableSchema) -> Void

    func body(content: Content) -> some View {
        if tables.count > 1 {
            content.toolbarTitleMenu {
                ForEach(tables) { t in
                    Button { select(t) } label: {
                        Label("\(t.name) (\(t.recordCount))", systemImage: t.id == current ? "checkmark" : "tablecells")
                    }
                }
            }
        } else {
            content
        }
    }
}

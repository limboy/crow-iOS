import SwiftUI

/// Every document the server has, with its tables.
struct DocumentsView: View {
    @Binding var server: String
    @State private var documents: [DocumentSummary] = []
    @State private var error: Error?
    @State private var hasLoaded = false
    @State private var showingSettings = false

    private var api: CrowAPI? { CrowAPI(server: server) }

    var body: some View {
        List {
            ForEach(documents) { doc in
                NavigationLink(value: Route.document(doc.name)) {
                    DocumentRow(document: doc)
                }
            }
        }
        // List leaves a tall gap above its first section; the title already separates it.
        .contentMargins(.top, 8, for: .scrollContent)
        .overlay { emptyState }
        .navigationTitle("Crow")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Server", systemImage: "server.rack") { showingSettings = true }
            }
        }
        .refreshable { await load() }
        .task(id: server) { await load() }
        .sheet(isPresented: $showingSettings) {
            ServerSettingsView(server: $server)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if let error, documents.isEmpty {
            ContentUnavailableView {
                Label("Can't Reach Server", systemImage: "wifi.exclamationmark")
            } description: {
                Text("\(server)\n\(error.localizedDescription)")
            } actions: {
                Button("Retry") { Task { await load() } }.buttonStyle(.glassProminent)
                Button("Change Server") { showingSettings = true }
            }
        } else if api == nil {
            ContentUnavailableView {
                Label("No Server", systemImage: "server.rack")
            } description: {
                Text("Enter the address of a crow service.")
            } actions: {
                Button("Set Server") { showingSettings = true }.buttonStyle(.glassProminent)
            }
        } else if hasLoaded, documents.isEmpty {
            ContentUnavailableView("No Documents", systemImage: "tray",
                                   description: Text("The server's folder has no .crow documents."))
        } else if !hasLoaded {
            ProgressView()
        }
    }

    private func load() async {
        guard let api else { documents = []; return }
        do {
            documents = try await api.documents()
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
        hasLoaded = true
    }
}

private struct DocumentRow: View {
    let document: DocumentSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tablecells.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.gradient, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(document.name).font(.headline)
                Text(document.tables.map { "\($0.name) · \($0.recordCount)" }.joined(separator: "   "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let updated = document.updatedAt.flatMap(CrowFormat.instant) {
                    Text("Edited \(updated, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ServerSettingsView: View {
    @Binding var server: String
    @State private var draft = ""
    @State private var status: Status = .idle
    @Environment(\.dismiss) private var dismiss

    enum Status: Equatable { case idle, checking, ok(Int), failed(String) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.10:8090", text: $draft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await check() } }
                } header: {
                    Text("Server Address")
                } footer: {
                    Text("Where crowd is running. On a device, use your Mac's local IP address rather than localhost.")
                }
                Section {
                    Button { Task { await check() } } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            switch status {
                            case .idle: EmptyView()
                            case .checking: ProgressView()
                            case .ok(let n):
                                Label("\(n) document\(n == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failed:
                                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    if case .failed(let message) = status {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        server = CrowAPI(server: draft)?.baseURL.absoluteString ?? draft
                        dismiss()
                    }
                    .disabled(CrowAPI(server: draft) == nil)
                }
            }
            .onAppear { draft = server }
        }
        .presentationDetents([.medium, .large])
    }

    private func check() async {
        guard let api = CrowAPI(server: draft) else {
            status = .failed("That isn't a valid address.")
            return
        }
        status = .checking
        do {
            status = .ok(try await api.documents().count)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

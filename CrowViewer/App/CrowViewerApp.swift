import SwiftUI

@main
struct CrowViewerApp: App {
    init() {
        // Media is served with Cache-Control, so a roomy URL cache keeps images instant on revisit.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

enum Route: Hashable {
    case document(String)
    case record(doc: String, table: String, id: String)
}

struct RootView: View {
    @AppStorage("server") private var server = "http://localhost:8090"
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            DocumentsView(server: $server)
                .navigationDestination(for: Route.self) { route in
                    if let api = CrowAPI(server: server) {
                        switch route {
                        case .document(let name):
                            DocumentView(api: api, name: name)
                        case .record(let doc, let table, let id):
                            RecordDetailView(api: api, doc: doc, table: table, recordId: id)
                        }
                    }
                }
        }
        .onChange(of: server) { path = NavigationPath() }
    }
}

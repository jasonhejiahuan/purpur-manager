import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppPreferences.self) private var preferences
    @State private var showingAddServer = false

    var body: some View {
        @Bindable var appModel = appModel
        NavigationSplitView {
            ServerSidebarView(showingAddServer: $showingAddServer)
                .navigationSplitViewColumnWidth(min: 220, ideal: preferences.sidebarWidth, max: 360)
        } detail: {
            ZStack {
                AppBackground()
                if let runtime = appModel.selectedRuntime {
                    ServerDetailView(runtime: runtime)
                } else {
                    ContentUnavailableView("No Server Selected", systemImage: "server.rack", description: Text("Add a Purpur/Paper management endpoint to begin."))
                        .toolbar {
                            Button("Add Server", systemImage: "plus") { showingAddServer = true }
                        }
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            ServerEditorView(mode: .add)
                .environment(appModel)
        }
        .alert("Purpur Manager", isPresented: Binding(get: { appModel.globalError != nil }, set: { if !$0 { appModel.globalError = nil } })) {
            Button("OK") { appModel.globalError = nil }
        } message: {
            Text(appModel.globalError ?? "Unknown error")
        }
    }
}

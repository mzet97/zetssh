import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SessionViewModel()
    @State private var selectedSessionId: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel:         viewModel,
                selectedSessionId: $selectedSessionId
            )
        } detail: {
            let session = viewModel.sessions.first { $0.id == selectedSessionId }
            SessionDetailView(session: session)
        }
        .alert("Erro", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
}

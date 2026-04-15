import SwiftUI

struct ContentView: View {
    @StateObject private var sessionVM = SessionViewModel()
    @StateObject private var tabsVM   = TabsViewModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: sessionVM, tabsVM: tabsVM)
        } detail: {
            MultiSessionView(tabsVM: tabsVM)
        }
        .alert("Erro", isPresented: Binding(
            get: { sessionVM.errorMessage != nil },
            set: { if !$0 { sessionVM.errorMessage = nil } }
        )) {
            Button("OK") { sessionVM.errorMessage = nil }
        } message: {
            Text(sessionVM.errorMessage ?? "")
        }
    }
}

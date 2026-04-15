import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var tabsVM: TabsViewModel

    /// Local highlight state — purely visual, does not drive detail content.
    @State private var highlightedSessionId: UUID?
    @State private var showingAddSession = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $highlightedSessionId) {
                Section("Sessions") {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink(value: session.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name).font(.headline)
                                Text("\(session.username)@\(session.host):\(session.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Deletar", role: .destructive) {
                                deleteSession(session)
                            }
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .onChange(of: highlightedSessionId) { _, newId in
                guard let id = newId,
                      let session = viewModel.sessions.first(where: { $0.id == id })
                else { return }
                tabsVM.open(session: session)
            }
            .onDeleteCommand {
                guard let id = highlightedSessionId,
                      let session = viewModel.sessions.first(where: { $0.id == id })
                else { return }
                deleteSession(session)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button { showingAddSession = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain).padding(8)

                Spacer()

                Button {
                    guard let id = highlightedSessionId,
                          let session = viewModel.sessions.first(where: { $0.id == id })
                    else { return }
                    deleteSession(session)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain).padding(8)
                .disabled(highlightedSessionId == nil)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("ZetSSH")
        .sheet(isPresented: $showingAddSession) {
            SessionFormView { newSession, credentials in
                viewModel.save(newSession, credentials: credentials)
            }
        }
    }

    // MARK: - Helpers

    private func deleteSession(_ session: Session) {
        if let tab = tabsVM.tabs.first(where: { $0.session.id == session.id }) {
            tabsVM.close(tabId: tab.id)
        }
        viewModel.delete(session)
        if highlightedSessionId == session.id { highlightedSessionId = nil }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            deleteSession(viewModel.sessions[index])
        }
    }
}

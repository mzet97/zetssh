import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Binding var selectedSessionId: UUID?
    @State private var showingAddSession = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSessionId) {
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
                                viewModel.delete(session)
                                if selectedSessionId == session.id { selectedSessionId = nil }
                            }
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .onDeleteCommand {
                if let id = selectedSessionId,
                   let session = viewModel.sessions.first(where: { $0.id == id }) {
                    viewModel.delete(session)
                    selectedSessionId = nil
                }
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
                    if let id = selectedSessionId,
                       let session = viewModel.sessions.first(where: { $0.id == id }) {
                        viewModel.delete(session)
                        selectedSessionId = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain).padding(8)
                .disabled(selectedSessionId == nil)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("ZetSSH")
        .sheet(isPresented: $showingAddSession) {
            SessionFormView { newSession, password in
                viewModel.save(newSession, password: password)
            }
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = viewModel.sessions[index]
            viewModel.delete(session)
            if selectedSessionId == session.id { selectedSessionId = nil }
        }
    }
}

import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabsVM: TabsViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(tabsVM.tabs.enumerated()), id: \.element.id) { index, tab in
                    if index > 0 {
                        Divider().frame(height: 20)
                    }
                    tabButton(for: tab)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 34)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func tabButton(for tab: ActiveSession) -> some View {
        let isSelected = tabsVM.selectedTabId == tab.id

        HStack(spacing: 4) {
            Circle()
                .fill(tab.connectionState == .connected ? Color.green :
                      tab.connectionState == .connecting ? Color.yellow :
                      tab.connectionState == .disconnected ? Color.red : Color.clear)
                .frame(width: 6, height: 6)

            Text(tab.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)

            Button {
                tabsVM.close(tabId: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fechar aba")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            isSelected
                ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .frame(height: 2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            tabsVM.selectedTabId = tab.id
        }
    }
}

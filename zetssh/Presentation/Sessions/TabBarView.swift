import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabsVM: TabsViewModel
    var onAddTab: (() -> Void)?

    @State private var showingAddSession = false
    @StateObject private var sessionVM = SessionViewModel()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabsVM.tabs) { tab in
                    tabButton(for: tab)
                }

                Button {
                    onAddTab?()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KineticColors.outline)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .padding(.bottom, 4)
                .help("Open new session")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 40)
        .padding(.horizontal, 8)
        .background(KineticColors.surfaceDim)
        .overlay(alignment: .bottom) {
            GhostDivider()
        }
    }

    // MARK: - Tab Button

    @ViewBuilder
    private func tabButton(for tab: ActiveSession) -> some View {
        let isSelected = tabsVM.selectedTabId == tab.id
        let isConnected = tab.connectionState == .connected

        HStack(spacing: 8) {
            Circle()
                .fill(isSelected ? KineticColors.primary : KineticColors.outline)
                .frame(width: 6, height: 6)

            Text(tab.label)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? KineticColors.onSurface : KineticColors.onSurfaceVariant)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                tabsVM.close(tabId: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(KineticColors.outline)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0)
            .help("Close tab")
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 180)
.frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? KineticColors.surfaceContainer : .clear)
        )
        .clipShape(
            .rect(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabsVM.selectedTabId = tab.id
        }
        .onHover { isHovered in
            // Visual hover feedback is handled by SwiftUI hit testing
        }
    }
}

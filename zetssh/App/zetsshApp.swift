import SwiftUI
import Sparkle

@main
struct zetsshApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        _ = AppDatabase.shared
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Verificar Atualizações...") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }
    }
}

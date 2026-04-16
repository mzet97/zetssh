import SwiftUI
import Sparkle

// MARK: - AppDelegate

/// Ensures the app process fully terminates when the last window is closed,
/// instead of staying alive in the background (default macOS behaviour).
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Force-close all windows so SwiftUI dismantles every SSHTerminalView,
        // which in turn calls RealSSHEngine.disconnect() → closes channels
        // and shuts down the NIO EventLoopGroup.
        NSApp.windows.forEach { $0.close() }
    }
}

// MARK: - App

@main
struct zetsshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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

//
//  zetsshApp.swift
//  zetssh
//
//  Created by Matheus Zeitune on 14/04/26.
//

import SwiftUI

@main
struct zetsshApp: App {
    init() {
        // Garante que o banco está OK antes da UI montar
        _ = AppDatabase.shared
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
        }
    }
}

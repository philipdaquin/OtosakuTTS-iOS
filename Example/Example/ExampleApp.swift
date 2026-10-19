//
//  ExampleApp.swift
//  Example
//

import SwiftUI

@main
struct ExampleApp: App {
#if os(macOS)
    @StateObject private var sparkleUpdater = SparkleUpdateController()
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
#if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
        }
#endif
    }
}
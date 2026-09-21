import SwiftUI
import AppKit

@main
struct GraftbenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 1040, minHeight: 660)
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Repository…") {
                    if let url = chooseRepositoryFolder() {
                        Task { await app.openRepository(at: url) }
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await app.refreshActive() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Fetch") { Task { await app.selectedRepository?.fetch() } }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Pull") { Task { await app.selectedRepository?.pull() } }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Push") { Task { await app.selectedRepository?.push() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

/// Ensures the app activates and shows its window even when launched from the
/// command line during development.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = ProcessInfo.processInfo.environment["GRAFTBENCH_SELFTEST"] {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await SelfTest.run(path: path)
                await MainActor.run { NSApp.terminate(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        if let icon = Brand.appIcon { NSApp.applicationIconImage = icon }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

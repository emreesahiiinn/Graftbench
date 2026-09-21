import SwiftUI
import Combine
import Sparkle

/// Bridges Sparkle's updater into SwiftUI.
///
/// Sparkle handles everything once it is configured (see `Packaging/Info.plist`
/// `SUFeedURL` + `SUPublicEDKey` and the repo's `appcast.xml`): it checks the
/// appcast, downloads the new DMG, verifies its EdDSA signature and installs it.
/// On first launch it also asks the user whether to check for updates
/// automatically. This wrapper just exposes a `checkForUpdates()` action and a
/// `canCheckForUpdates` flag so the "Check for Updates…" menu item can enable
/// and disable itself.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

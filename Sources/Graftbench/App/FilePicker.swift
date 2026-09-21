import AppKit

/// Present a folder chooser for opening a git repository.
@MainActor
func chooseRepositoryFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    panel.message = "Choose a git repository folder"
    panel.canCreateDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
}

/// Reveal a path in Finder.
@MainActor
func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

/// Open a path with the user's configured terminal / default handler.
@MainActor
func openInFinder(_ url: URL) {
    NSWorkspace.shared.open(url)
}

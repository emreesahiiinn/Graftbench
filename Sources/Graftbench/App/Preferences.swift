import Foundation
import Observation

/// A repository the user has opened before.
struct RecentRepository: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    var lastOpened: Date

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// Standard macOS locations Graftbench uses to store its data — just like a
/// well-behaved native app.
enum AppPaths {
    static let applicationSupport: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("Graftbench", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let cache: URL = {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first ?? applicationSupport
        let dir = base.appendingPathComponent("Graftbench", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// App-wide user preferences, persisted to `UserDefaults`.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    var recentRepositories: [RecentRepository] = []
    var gitExecutablePath: String?
    var historyPageSize: Int = 200
    var useRebaseOnPull: Bool = false
    var appearance: AppAppearance = .system
    var ignoreWhitespaceInDiff: Bool = false
    var signCommits: Bool = false
    var diffMode: DiffDisplayMode = .unified
    var diffWordWrap: Bool = false
    var diffShowInvisibles: Bool = false
    var diffTabWidth: Int = 4
    var diffHideHunkHeaders: Bool = false
    var diffFullFile: Bool = false
    var accentTheme: AccentTheme = .blue
    var translucentWindow: Bool = false

    private let defaults = UserDefaults.standard
    private let recentsKey = "recentRepositories.v1"
    private let gitPathKey = "gitExecutablePath"
    private let rebaseKey = "useRebaseOnPull"
    private let appearanceKey = "appearance"
    private let whitespaceKey = "ignoreWhitespaceInDiff"
    private let signKey = "signCommits"
    private let diffModeKey = "diffMode"
    private let wrapKey = "diffWordWrap"
    private let invisiblesKey = "diffShowInvisibles"
    private let tabWidthKey = "diffTabWidth"
    private let hideHunkKey = "diffHideHunkHeaders"
    private let fullFileKey = "diffFullFile"
    private let accentKey = "accentTheme"
    private let translucentKey = "translucentWindow"

    private init() {
        if let data = defaults.data(forKey: recentsKey),
           let decoded = try? JSONDecoder().decode([RecentRepository].self, from: data) {
            recentRepositories = decoded
        }
        gitExecutablePath = defaults.string(forKey: gitPathKey)
        useRebaseOnPull = defaults.bool(forKey: rebaseKey)
        ignoreWhitespaceInDiff = defaults.bool(forKey: whitespaceKey)
        signCommits = defaults.bool(forKey: signKey)
        diffWordWrap = defaults.bool(forKey: wrapKey)
        diffShowInvisibles = defaults.bool(forKey: invisiblesKey)
        diffTabWidth = defaults.object(forKey: tabWidthKey) as? Int ?? 4
        diffHideHunkHeaders = defaults.bool(forKey: hideHunkKey)
        diffFullFile = defaults.bool(forKey: fullFileKey)
        translucentWindow = defaults.bool(forKey: translucentKey)
        if let rawMode = defaults.string(forKey: diffModeKey),
           let mode = DiffDisplayMode(rawValue: rawMode) {
            diffMode = mode
        }
        if let rawAccent = defaults.string(forKey: accentKey),
           let accent = AccentTheme(rawValue: rawAccent) {
            accentTheme = accent
        }
        Theme.applyAccent(accentTheme)
        if let raw = defaults.string(forKey: appearanceKey),
           let value = AppAppearance(rawValue: raw) {
            appearance = value
        }
        GitProcess.overridePath = gitExecutablePath
    }

    func setIgnoreWhitespaceInDiff(_ value: Bool) {
        ignoreWhitespaceInDiff = value
        defaults.set(value, forKey: whitespaceKey)
    }

    func setSignCommits(_ value: Bool) {
        signCommits = value
        defaults.set(value, forKey: signKey)
    }

    func setDiffMode(_ value: DiffDisplayMode) {
        diffMode = value
        defaults.set(value.rawValue, forKey: diffModeKey)
    }
    func setDiffWordWrap(_ value: Bool) {
        diffWordWrap = value
        defaults.set(value, forKey: wrapKey)
    }
    func setDiffShowInvisibles(_ value: Bool) {
        diffShowInvisibles = value
        defaults.set(value, forKey: invisiblesKey)
    }
    func setDiffTabWidth(_ value: Int) {
        diffTabWidth = value
        defaults.set(value, forKey: tabWidthKey)
    }
    func setDiffHideHunkHeaders(_ value: Bool) {
        diffHideHunkHeaders = value
        defaults.set(value, forKey: hideHunkKey)
    }
    func setDiffFullFile(_ value: Bool) {
        diffFullFile = value
        defaults.set(value, forKey: fullFileKey)
    }
    func setAccentTheme(_ value: AccentTheme) {
        accentTheme = value
        defaults.set(value.rawValue, forKey: accentKey)
        Theme.applyAccent(value)
    }
    func setTranslucentWindow(_ value: Bool) {
        translucentWindow = value
        defaults.set(value, forKey: translucentKey)
    }

    func setAppearance(_ value: AppAppearance) {
        appearance = value
        defaults.set(value.rawValue, forKey: appearanceKey)
    }

    func noteOpened(url: URL, name: String) {
        let path = url.path
        recentRepositories.removeAll { $0.path == path }
        recentRepositories.insert(RecentRepository(path: path, name: name, lastOpened: .now), at: 0)
        if recentRepositories.count > 20 {
            recentRepositories = Array(recentRepositories.prefix(20))
        }
        saveRecents()
    }

    func removeRecent(_ recent: RecentRepository) {
        recentRepositories.removeAll { $0.id == recent.id }
        saveRecents()
    }

    func setGitExecutablePath(_ path: String?) {
        gitExecutablePath = path
        defaults.set(path, forKey: gitPathKey)
        GitProcess.overridePath = path
    }

    func setUseRebaseOnPull(_ value: Bool) {
        useRebaseOnPull = value
        defaults.set(value, forKey: rebaseKey)
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recentRepositories) {
            defaults.set(data, forKey: recentsKey)
        }
    }
}

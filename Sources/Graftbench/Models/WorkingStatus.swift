import Foundation

/// The state of a file on one side (index or worktree) in porcelain v2 terms.
enum FileState: Sendable, Hashable {
    case unmodified
    case modified
    case added
    case deleted
    case renamed
    case copied
    case typeChanged
    case unmerged
    case untracked
    case ignored

    init(porcelainCode c: Character) {
        switch c {
        case ".": self = .unmodified
        case "M": self = .modified
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        case "C": self = .copied
        case "T": self = .typeChanged
        case "U": self = .unmerged
        default:  self = .modified
        }
    }
}

/// One entry in the working copy status.
struct StatusEntry: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let originalPath: String?       // for renames/copies
    let indexState: FileState       // X — staged side
    let worktreeState: FileState    // Y — unstaged side
    let isConflicted: Bool
    let isUntracked: Bool
    let isIgnored: Bool
    let isSubmodule: Bool

    /// The change is (at least partly) present in the index.
    var isStaged: Bool {
        !isUntracked && !isConflicted && indexState != .unmodified
    }

    /// There are changes in the worktree not yet staged (includes untracked).
    var hasWorktreeChanges: Bool {
        isUntracked || isConflicted || worktreeState != .unmodified
    }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    /// The most meaningful single state for display / icon selection.
    var primaryState: FileState {
        if isConflicted { return .unmerged }
        if isUntracked { return .untracked }
        if isIgnored { return .ignored }
        if indexState != .unmodified { return indexState }
        return worktreeState
    }
}

/// A snapshot of the working copy.
struct WorkingStatus: Sendable {
    var branch: String?
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0
    var isDetached: Bool = false
    var entries: [StatusEntry] = []

    var staged: [StatusEntry] { entries.filter(\.isStaged) }
    var unstaged: [StatusEntry] { entries.filter { $0.hasWorktreeChanges && !$0.isConflicted } }
    var conflicted: [StatusEntry] { entries.filter(\.isConflicted) }

    var isClean: Bool { entries.isEmpty }
    var totalChangeCount: Int { entries.count }

    static let empty = WorkingStatus()
}

import Foundation

/// A local or remote branch.
struct Branch: Identifiable, Hashable, Sendable {
    var id: String { fullRef }
    let fullRef: String         // refs/heads/main or refs/remotes/origin/main
    let name: String            // "main" or "origin/main"
    let shortName: String       // "main" (remote name stripped for remote branches)
    let isCurrent: Bool
    let isRemote: Bool
    let targetSHA: String
    let upstream: String?       // short upstream ref, e.g. "origin/main"
    let ahead: Int
    let behind: Int
    let lastCommitDate: Date?
    let lastCommitSubject: String

    /// For a remote branch "origin/main" -> "origin".
    var remoteName: String? {
        guard isRemote else { return nil }
        return name.split(separator: "/").first.map(String.init)
    }

    let upstreamGone: Bool     // upstream was configured but deleted on the remote
    var isTracking: Bool { upstream != nil }
}

/// A configured remote (origin, upstream…).
struct Remote: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let fetchURL: String
    let pushURL: String
}

/// An annotated or lightweight tag.
struct Tag: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let targetSHA: String
    let date: Date?
    let message: String
}

/// A git submodule.
struct Submodule: Identifiable, Hashable, Sendable {
    enum State: Sendable { case clean, modified, notInitialized, conflicts }
    var id: String { path }
    let name: String
    let path: String
    let sha: String
    let describe: String
    let state: State
}

/// A stash entry.
struct Stash: Identifiable, Hashable, Sendable {
    var id: String { selector }
    let index: Int
    let selector: String        // "stash@{0}"
    let message: String
    let date: Date?
    let branch: String?         // branch the stash was created on, if parseable
}

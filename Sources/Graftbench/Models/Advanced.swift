import Foundation

struct ReflogEntry: Identifiable, Hashable, Sendable {
    var id: String { selector }
    let shortSHA: String
    let selector: String    // e.g. HEAD@{0}
    let subject: String
    let author: String
    let date: Date?
}

struct Worktree: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let sha: String
    let branch: String?     // short branch name, nil if detached
    let isMain: Bool

    var name: String { (path as NSString).lastPathComponent }
}

struct GrepMatch: Identifiable, Hashable, Sendable {
    let id = UUID()
    let path: String
    let line: Int
    let text: String
}

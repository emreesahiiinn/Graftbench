import Foundation

/// How a file diff is presented.
enum DiffDisplayMode: String, CaseIterable, Sendable {
    case unified
    case split

    var symbol: String {
        switch self {
        case .unified: return "text.alignleft"
        case .split: return "rectangle.split.2x1"
        }
    }
}

/// A parsed unified diff for a single file.
struct FileDiff: Identifiable, Hashable, Sendable {
    let id: String
    let oldPath: String?
    let newPath: String?
    let isBinary: Bool
    let isNew: Bool
    let isDeleted: Bool
    let isRenamed: Bool
    let hunks: [DiffHunk]

    var displayPath: String { newPath ?? oldPath ?? "(unknown)" }

    var primaryState: FileState {
        if isNew { return .added }
        if isDeleted { return .deleted }
        if isRenamed { return .renamed }
        return .modified
    }

    var addedLines: Int {
        hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count }
    }
    var removedLines: Int {
        hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count }
    }

    static func placeholder(path: String) -> FileDiff {
        FileDiff(id: path, oldPath: path, newPath: path, isBinary: false,
                 isNew: false, isDeleted: false, isRenamed: false, hunks: [])
    }
}

/// A hunk (`@@ -a,b +c,d @@`) within a file diff.
struct DiffHunk: Identifiable, Hashable, Sendable {
    let id = UUID()
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

/// A single line inside a hunk.
struct DiffLine: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case context
        case addition
        case deletion
        case noNewline
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
    /// Character range (into `text`) that actually changed vs the paired line.
    var emphasis: Range<Int>? = nil
}

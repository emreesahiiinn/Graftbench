import Foundation

/// One line of `git blame` output.
struct BlameLine: Identifiable, Hashable, Sendable {
    var id: Int { lineNumber }
    let lineNumber: Int
    let sha: String
    let author: String
    let content: String

    var shortSHA: String { String(sha.prefix(7)) }
}

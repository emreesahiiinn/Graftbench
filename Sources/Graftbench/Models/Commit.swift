import Foundation

/// A single commit in the repository history.
struct Commit: Identifiable, Hashable, Sendable {
    let id: String              // full 40-char SHA
    let shortSHA: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let committerName: String
    let committerEmail: String
    let commitDate: Date
    let subject: String
    let body: String
    let refs: [CommitRef]

    var isMerge: Bool { parents.count > 1 }
    var isRoot: Bool { parents.isEmpty }

    var fullMessage: String {
        body.isEmpty ? subject : "\(subject)\n\n\(body)"
    }
}

/// A ref pointing at a commit (branch tip, tag, HEAD…), parsed from `%D`.
struct CommitRef: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
        case head              // the symbolic HEAD marker
        case localBranch
        case remoteBranch
        case tag
        case stash
    }

    var id: String { "\(kind)-\(name)" }
    let kind: Kind
    let name: String            // display name, e.g. "main", "origin/main", "v1.2.0"
    let isCurrent: Bool         // true when HEAD points here

    /// Parse the comma-separated `%D` decoration string from `git log`.
    static func parse(_ decoration: String) -> [CommitRef] {
        let trimmed = decoration.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var refs: [CommitRef] = []
        var headIsAtBranch = false

        for rawToken in trimmed.components(separatedBy: ", ") {
            let token = rawToken.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty else { continue }

            if token.hasPrefix("HEAD -> ") {
                // HEAD -> main : current local branch
                let branch = String(token.dropFirst("HEAD -> ".count))
                headIsAtBranch = true
                refs.append(CommitRef(kind: .localBranch, name: branch, isCurrent: true))
            } else if token == "HEAD" {
                // detached HEAD
                refs.append(CommitRef(kind: .head, name: "HEAD", isCurrent: true))
            } else if token.hasPrefix("tag: ") {
                let tag = String(token.dropFirst("tag: ".count))
                refs.append(CommitRef(kind: .tag, name: tag, isCurrent: false))
            } else if token.contains("/") {
                refs.append(CommitRef(kind: .remoteBranch, name: token, isCurrent: false))
            } else {
                refs.append(CommitRef(kind: .localBranch, name: token, isCurrent: false))
            }
        }

        // If HEAD is attached, the current branch is already flagged above.
        _ = headIsAtBranch
        return refs
    }
}

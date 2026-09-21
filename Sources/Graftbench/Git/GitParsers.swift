import Foundation

// MARK: - Structured output parsers

extension GitClient {
    static func parseLog(_ output: String) -> [Commit] {
        let records = output.components(separatedBy: recordSeparator)
        var commits: [Commit] = []
        commits.reserveCapacity(records.count)

        for rawRecord in records {
            let record = rawRecord.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            if record.isEmpty { continue }

            let fields = record.components(separatedBy: unitSeparator)
            guard fields.count >= 12 else { continue }

            let parents = fields[2].split(separator: " ").map(String.init)
            let authorDate = Date(timeIntervalSince1970: TimeInterval(fields[5]) ?? 0)
            let commitDate = Date(timeIntervalSince1970: TimeInterval(fields[8]) ?? 0)

            let commit = Commit(
                id: fields[0],
                shortSHA: fields[1],
                parents: parents,
                authorName: fields[3],
                authorEmail: fields[4],
                authorDate: authorDate,
                committerName: fields[6],
                committerEmail: fields[7],
                commitDate: commitDate,
                subject: fields[9],
                body: fields[10].trimmingCharacters(in: .whitespacesAndNewlines),
                refs: CommitRef.parse(fields[11])
            )
            commits.append(commit)
        }
        return commits
    }

    static func parseStatus(_ output: String) -> WorkingStatus {
        var status = WorkingStatus()
        let tokens = output.components(separatedBy: "\u{0}")
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            defer { index += 1 }
            if token.isEmpty { continue }

            if token.hasPrefix("# ") {
                parseStatusHeader(token, into: &status)
                continue
            }

            guard let marker = token.first else { continue }
            switch marker {
            case "1":
                if let entry = parseOrdinaryEntry(token) { status.entries.append(entry) }
            case "2":
                // Renamed/copied: the original path is the following NUL token.
                var originalPath: String?
                if index + 1 < tokens.count {
                    originalPath = tokens[index + 1]
                    index += 1
                }
                if let entry = parseRenamedEntry(token, originalPath: originalPath) {
                    status.entries.append(entry)
                }
            case "u":
                if let entry = parseUnmergedEntry(token) { status.entries.append(entry) }
            case "?":
                let path = String(token.dropFirst(2))
                status.entries.append(StatusEntry(
                    path: path, originalPath: nil,
                    indexState: .unmodified, worktreeState: .untracked,
                    isConflicted: false, isUntracked: true, isIgnored: false, isSubmodule: false))
            case "!":
                let path = String(token.dropFirst(2))
                status.entries.append(StatusEntry(
                    path: path, originalPath: nil,
                    indexState: .unmodified, worktreeState: .ignored,
                    isConflicted: false, isUntracked: false, isIgnored: true, isSubmodule: false))
            default:
                continue
            }
        }

        status.entries.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return status
    }

    private static func parseStatusHeader(_ token: String, into status: inout WorkingStatus) {
        if token.hasPrefix("# branch.head ") {
            let name = String(token.dropFirst("# branch.head ".count))
            if name == "(detached)" {
                status.isDetached = true
            } else {
                status.branch = name
            }
        } else if token.hasPrefix("# branch.upstream ") {
            status.upstream = String(token.dropFirst("# branch.upstream ".count))
        } else if token.hasPrefix("# branch.ab ") {
            let rest = String(token.dropFirst("# branch.ab ".count))
            let parts = rest.split(separator: " ")
            if parts.count == 2 {
                status.ahead = abs(Int(parts[0]) ?? 0)
                status.behind = abs(Int(parts[1]) ?? 0)
            }
        }
    }

    private static func parseOrdinaryEntry(_ token: String) -> StatusEntry? {
        let pieces = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard pieces.count >= 9 else { return nil }
        let xy = Array(pieces[1])
        guard xy.count == 2 else { return nil }
        let sub = String(pieces[2])
        let path = String(pieces[8])
        return StatusEntry(
            path: path, originalPath: nil,
            indexState: FileState(porcelainCode: xy[0]),
            worktreeState: FileState(porcelainCode: xy[1]),
            isConflicted: false, isUntracked: false, isIgnored: false,
            isSubmodule: sub.first == "S")
    }

    private static func parseRenamedEntry(_ token: String, originalPath: String?) -> StatusEntry? {
        let pieces = token.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard pieces.count >= 10 else { return nil }
        let xy = Array(pieces[1])
        guard xy.count == 2 else { return nil }
        let sub = String(pieces[2])
        let path = String(pieces[9])
        return StatusEntry(
            path: path, originalPath: originalPath,
            indexState: FileState(porcelainCode: xy[0]),
            worktreeState: FileState(porcelainCode: xy[1]),
            isConflicted: false, isUntracked: false, isIgnored: false,
            isSubmodule: sub.first == "S")
    }

    private static func parseUnmergedEntry(_ token: String) -> StatusEntry? {
        let pieces = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard pieces.count >= 11 else { return nil }
        let xy = Array(pieces[1])
        guard xy.count == 2 else { return nil }
        let path = String(pieces[10])
        return StatusEntry(
            path: path, originalPath: nil,
            indexState: FileState(porcelainCode: xy[0]),
            worktreeState: FileState(porcelainCode: xy[1]),
            isConflicted: true, isUntracked: false, isIgnored: false, isSubmodule: false)
    }

    static func parseBranches(_ output: String) -> [Branch] {
        var branches: [Branch] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 7 else { continue }

            let refName = fields[1]
            if refName.hasSuffix("/HEAD") { continue }        // skip symbolic origin/HEAD

            let isRemote = refName.hasPrefix("refs/remotes/")
            let isCurrent = fields[0].trimmingCharacters(in: .whitespaces) == "*"

            let name: String
            if isRemote {
                name = String(refName.dropFirst("refs/remotes/".count))
            } else if refName.hasPrefix("refs/heads/") {
                name = String(refName.dropFirst("refs/heads/".count))
            } else {
                name = refName
            }

            let shortName: String
            if isRemote {
                let parts = name.split(separator: "/")
                shortName = parts.dropFirst().joined(separator: "/")
            } else {
                shortName = name
            }

            var ahead = 0, behind = 0, gone = false
            let track = fields[4]
            if track.contains("gone") {
                gone = true
            } else {
                for part in track.components(separatedBy: ", ") {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if p.hasPrefix("ahead ") { ahead = Int(p.dropFirst(6)) ?? 0 }
                    else if p.hasPrefix("behind ") { behind = Int(p.dropFirst(7)) ?? 0 }
                }
            }

            let upstream = fields[3].isEmpty ? nil : fields[3]
            let date = TimeInterval(fields[5]).map { Date(timeIntervalSince1970: $0) }

            branches.append(Branch(
                fullRef: refName, name: name, shortName: shortName,
                isCurrent: isCurrent, isRemote: isRemote, targetSHA: fields[2],
                upstream: upstream, ahead: ahead, behind: behind,
                lastCommitDate: date, lastCommitSubject: fields[6],
                upstreamGone: gone))
        }
        return branches
    }

    static func parseRemotes(_ output: String) -> [Remote] {
        var fetch: [String: String] = [:]
        var push: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2 else { continue }
            let name = String(parts[0])
            let urlAndType = parts[1]
            if urlAndType.hasSuffix("(fetch)") {
                fetch[name] = String(urlAndType.dropLast(" (fetch)".count))
            } else if urlAndType.hasSuffix("(push)") {
                push[name] = String(urlAndType.dropLast(" (push)".count))
            }
        }
        return fetch.keys.sorted().map { name in
            Remote(name: name, fetchURL: fetch[name] ?? "", pushURL: push[name] ?? fetch[name] ?? "")
        }
    }

    static func parseTags(_ output: String) -> [Tag] {
        var tags: [Tag] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 4 else { continue }
            let date = TimeInterval(fields[2]).map { Date(timeIntervalSince1970: $0) }
            tags.append(Tag(name: fields[0], targetSHA: fields[1], date: date, message: fields[3]))
        }
        return tags
    }

    static func parseStashes(_ output: String) -> [Stash] {
        var stashes: [Stash] = []
        for (offset, line) in output.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 4 else { continue }
            let date = TimeInterval(fields[2]).map { Date(timeIntervalSince1970: $0) }
            let subject = fields[3]
            var branch: String?
            // Reflog subject looks like "WIP on main: 1a2b3c Message" or "On main: msg".
            if let range = subject.range(of: " on ", options: .caseInsensitive) ?? subject.range(of: "On ") {
                let after = subject[range.upperBound...]
                if let colon = after.firstIndex(of: ":") {
                    branch = String(after[..<colon]).trimmingCharacters(in: .whitespaces)
                }
            }
            stashes.append(Stash(index: offset, selector: fields[0], message: subject, date: date, branch: branch))
        }
        return stashes
    }

    static func parseSubmodules(_ output: String) -> [Submodule] {
        var result: [Submodule] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let statusChar = line.first else { continue }
            let rest = line.dropFirst()
            let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let sha = String(parts[0])
            let path = String(parts[1])
            let describe = parts.count >= 3 ? String(parts[2]) : ""
            let state: Submodule.State
            switch statusChar {
            case "-": state = .notInitialized
            case "+": state = .modified
            case "U": state = .conflicts
            default: state = .clean
            }
            result.append(Submodule(name: (path as NSString).lastPathComponent,
                                    path: path, sha: sha, describe: describe, state: state))
        }
        return result
    }

    static func parseReflog(_ output: String) -> [ReflogEntry] {
        var result: [ReflogEntry] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 5 else { continue }
            let date = TimeInterval(fields[4]).map { Date(timeIntervalSince1970: $0) }
            result.append(ReflogEntry(shortSHA: fields[0], selector: fields[1],
                                      subject: fields[2], author: fields[3], date: date))
        }
        return result
    }

    static func parseWorktrees(_ output: String) -> [Worktree] {
        var result: [Worktree] = []
        var path: String?
        var sha = ""
        var branch: String?

        func flush() {
            guard let p = path else { return }
            result.append(Worktree(path: p, sha: sha, branch: branch, isMain: result.isEmpty))
            path = nil; sha = ""; branch = nil
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("worktree ") {
                flush()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                sha = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "detached" {
                branch = nil
            } else if line.isEmpty {
                flush()
            }
        }
        flush()
        return result
    }

    static func parseGrep(_ output: String, limit: Int) -> [GrepMatch] {
        var result: [GrepMatch] = []
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let lineNumber = Int(parts[1]) else { continue }
            result.append(GrepMatch(path: String(parts[0]), line: lineNumber, text: String(parts[2])))
            if result.count >= limit { break }
        }
        return result
    }

    static func parseBlame(_ output: String) -> [BlameLine] {
        var lines: [BlameLine] = []
        var authorsBySha: [String: String] = [:]
        var currentSha = ""
        var currentFinalLine = 0

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("\t") {
                lines.append(BlameLine(lineNumber: currentFinalLine, sha: currentSha,
                                       author: authorsBySha[currentSha] ?? "", content: String(line.dropFirst())))
            } else if line.hasPrefix("author ") {
                authorsBySha[currentSha] = String(line.dropFirst("author ".count))
            } else {
                let parts = line.split(separator: " ")
                if let first = parts.first, first.count == 40, first.allSatisfy({ $0.isHexDigit }), parts.count >= 3 {
                    currentSha = String(first)
                    currentFinalLine = Int(parts[2]) ?? currentFinalLine
                }
            }
        }
        return lines
    }
}

import Foundation

/// High-level, async git operations for a single repository working tree.
///
/// Every method shells out to the real `git` binary, which guarantees exact
/// parity with the command line: credential helpers, hooks, LFS, submodules and
/// signing all "just work" because we are driving the same tool the user does.
struct GitClient: Sendable {
    /// Absolute path to the repository's top-level working directory.
    let root: URL

    static let unitSeparator = "\u{1f}"
    static let recordSeparator = "\u{1e}"

    init(root: URL) {
        self.root = root
    }

    // MARK: - Discovery

    /// Resolve the top-level working directory for a path inside a repository.
    static func discover(at url: URL) async throws -> URL {
        let output = try await GitProcess.run(["-C", url.path, "rev-parse", "--show-toplevel"])
        guard output.isSuccess else { throw GitError.notARepository(url) }
        let top = output.trimmedOutput
        guard !top.isEmpty else { throw GitError.notARepository(url) }
        return URL(fileURLWithPath: top, isDirectory: true)
    }

    // MARK: - Command runners

    @discardableResult
    func run(_ arguments: [String], input: Data? = nil, environment: [String: String] = [:]) async throws -> String {
        let output = try await GitProcess.run(arguments, in: root, input: input, extraEnvironment: environment)
        guard output.isSuccess else {
            let message = output.standardError.isEmpty ? output.standardOutput : output.standardError
            throw GitError.commandFailed(command: arguments.first ?? "git",
                                         exitCode: output.exitCode,
                                         message: message)
        }
        return output.standardOutput
    }

    func runRaw(_ arguments: [String], input: Data? = nil) async throws -> GitOutput {
        try await GitProcess.run(arguments, in: root, input: input)
    }

    // MARK: - Status

    func status() async throws -> WorkingStatus {
        let output = try await run(["status", "--porcelain=v2", "--branch", "-z"])
        return Self.parseStatus(output)
    }

    // MARK: - History

    /// Load commits. Pass revision selectors like `["--all"]` or a branch name.
    func log(revisions: [String], limit: Int, skip: Int = 0, pathspec: [String] = []) async throws -> [Commit] {
        let format = [
            "%H", "%h", "%P", "%an", "%ae", "%at",
            "%cn", "%ce", "%ct", "%s", "%b", "%D"
        ].joined(separator: "%x1f") + "%x1e"

        var arguments = ["log", "--no-color", "--date-order",
                         "--pretty=format:\(format)",
                         "-n", String(limit)]
        if skip > 0 { arguments += ["--skip", String(skip)] }
        arguments += revisions
        if !pathspec.isEmpty { arguments += ["--"] + pathspec }

        let output = try await run(arguments)
        return Self.parseLog(output)
    }

    // MARK: - Refs

    func branches() async throws -> [Branch] {
        let format = [
            "%(HEAD)", "%(refname)", "%(objectname)",
            "%(upstream:short)", "%(upstream:track,nobracket)",
            "%(committerdate:unix)", "%(contents:subject)"
        ].joined(separator: "%1f")

        let output = try await run([
            "for-each-ref",
            "--format=\(format)",
            "refs/heads", "refs/remotes"
        ])
        return Self.parseBranches(output)
    }

    func remotes() async throws -> [Remote] {
        let output = try await run(["remote", "-v"])
        return Self.parseRemotes(output)
    }

    func tags() async throws -> [Tag] {
        let format = [
            "%(refname:short)", "%(objectname)",
            "%(creatordate:unix)", "%(contents:subject)"
        ].joined(separator: "%1f")
        let output = try await run(["for-each-ref", "--sort=-creatordate",
                                    "--format=\(format)", "refs/tags"])
        return Self.parseTags(output)
    }

    func stashes() async throws -> [Stash] {
        let format = ["%gd", "%H", "%ct", "%gs"].joined(separator: "%1f")
        let output = try await run(["stash", "list", "--format=\(format)"])
        return Self.parseStashes(output)
    }

    // MARK: - Diffs

    func diff(path: String, staged: Bool, ignoreWhitespace: Bool = false, fullContext: Bool = false) async throws -> FileDiff {
        var arguments = ["diff", "--no-color", "--find-renames"]
        if ignoreWhitespace { arguments.append("-w") }
        if fullContext { arguments.append("-U100000") }
        if staged { arguments.append("--cached") }
        arguments += ["--", path]
        let output = try await run(arguments)
        return DiffParser.parse(output).first ?? FileDiff.placeholder(path: path)
    }

    /// Diff for an untracked file (rendered fully as additions).
    func untrackedDiff(path: String) async throws -> FileDiff {
        let output = try await runRaw(["diff", "--no-color", "--no-index", "--", "/dev/null", path])
        // `--no-index` returns exit code 1 when files differ; that's expected.
        return DiffParser.parse(output.standardOutput).first ?? FileDiff.placeholder(path: path)
    }

    /// All file diffs introduced by a commit (relative to its first parent).
    func commitDiff(sha: String, firstParent: String?, ignoreWhitespace: Bool = false, fullContext: Bool = false) async throws -> [FileDiff] {
        var opts: [String] = []
        if ignoreWhitespace { opts.append("-w") }
        if fullContext { opts.append("-U100000") }
        let output: String
        if let parent = firstParent {
            output = try await run(["diff", "--no-color", "--find-renames"] + opts + [parent, sha])
        } else {
            output = try await run(["show", "--no-color", "--find-renames", "--format="] + opts + [sha])
        }
        return DiffParser.parse(output)
    }

    // MARK: - Staging

    func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["add", "-A", "--"] + paths)
    }

    func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["restore", "--staged", "--"] + paths)
    }

    func stageAll() async throws {
        try await run(["add", "-A"])
    }

    func unstageAll() async throws {
        try await run(["reset", "--quiet", "HEAD", "--"])
    }

    /// Discard worktree changes to tracked files. Untracked files are deleted.
    func discard(paths: [String], untracked: Bool) async throws {
        guard !paths.isEmpty else { return }
        if untracked {
            try await run(["clean", "-f", "-d", "--"] + paths)
        } else {
            try await run(["restore", "--worktree", "--"] + paths)
        }
    }

    // MARK: - Commit

    func commit(message: String, amend: Bool, sign: Bool = false) async throws {
        var arguments = ["commit", "-F", "-"]
        if amend { arguments.append("--amend") }
        if sign { arguments.append("-S") }
        try await run(arguments, input: Data(message.utf8))
    }

    // MARK: - Sync

    func fetch(remote: String?, prune: Bool) async throws {
        // Note: fetch/pull/push do not accept --no-color; git already omits
        // color for non-TTY (piped) output.
        var arguments = ["fetch"]
        if prune { arguments.append("--prune") }
        if let remote { arguments.append(remote) } else { arguments.append("--all") }
        try await run(arguments)
    }

    func pull(rebase: Bool) async throws {
        var arguments = ["pull"]
        arguments.append(rebase ? "--rebase" : "--no-rebase")
        try await run(arguments)
    }

    func push(remote: String?, branch: String?, setUpstream: Bool, force: Bool) async throws {
        var arguments = ["push"]
        if force { arguments.append("--force-with-lease") }
        if setUpstream { arguments.append("-u") }
        if let remote { arguments.append(remote) }
        if let branch { arguments.append(branch) }
        try await run(arguments)
    }

    // MARK: - Branch operations

    func checkout(branch: String) async throws {
        try await run(["switch", branch])
    }

    func checkoutRemoteTracking(local: String, remoteRef: String) async throws {
        try await run(["switch", "-c", local, "--track", remoteRef])
    }

    func createBranch(name: String, checkout: Bool) async throws {
        if checkout {
            try await run(["switch", "-c", name])
        } else {
            try await run(["branch", name])
        }
    }

    func deleteBranch(name: String, force: Bool) async throws {
        try await run(["branch", force ? "-D" : "-d", name])
    }

    // MARK: - Stash operations

    func stashPush(message: String?, includeUntracked: Bool) async throws {
        var arguments = ["stash", "push"]
        if includeUntracked { arguments.append("-u") }
        if let message, !message.isEmpty { arguments += ["-m", message] }
        try await run(arguments)
    }

    func stashApply(selector: String, pop: Bool) async throws {
        try await run(["stash", pop ? "pop" : "apply", selector])
    }

    func stashDrop(selector: String) async throws {
        try await run(["stash", "drop", selector])
    }

    // MARK: - Commit operations (cherry-pick, revert, reset…)

    func revParse(_ revision: String) async throws -> String {
        let output = try await run(["rev-parse", revision])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func checkoutDetached(sha: String) async throws {
        try await run(["checkout", sha])
    }

    func cherryPick(sha: String) async throws {
        try await run(["cherry-pick", sha])
    }

    func revert(sha: String) async throws {
        try await run(["revert", "--no-edit", sha])
    }

    func reset(to ref: String, mode: String) async throws {
        try await run(["reset", "--\(mode)", ref])
    }

    func branch(name: String, at ref: String) async throws {
        try await run(["branch", name, ref])
    }

    func tag(name: String, at ref: String, message: String?) async throws {
        if let message, !message.isEmpty {
            try await run(["tag", "-a", "-m", message, name, ref])
        } else {
            try await run(["tag", name, ref])
        }
    }

    /// Switch back to the previous branch/commit (git switch -).
    func switchToPrevious() async throws {
        try await run(["switch", "-"])
    }

    func merge(branch: String, noFastForward: Bool) async throws {
        var arguments = ["merge"]
        if noFastForward { arguments.append("--no-ff") }
        arguments.append(branch)
        try await run(arguments)
    }

    // MARK: - Hunk staging (line-level via patch)

    /// Apply a single hunk to the index or worktree.
    /// - toIndex: true stages/unstages (uses --cached); false touches the worktree.
    /// - reverse: true unstages / discards.
    func applyHunk(path: String, oldPath: String?, hunk: DiffHunk, toIndex: Bool, reverse: Bool) async throws {
        let patch = Self.buildHunkPatch(path: path, oldPath: oldPath, hunk: hunk)
        var arguments = ["apply", "--recount", "--whitespace=nowarn"]
        if toIndex { arguments.append("--cached") }
        if reverse { arguments.append("--reverse") }
        try await run(arguments, input: Data(patch.utf8))
    }

    /// Stage/unstage only the selected lines across a file's hunks.
    func applySelectedLines(path: String, oldPath: String?, hunks: [DiffHunk],
                            selectedIDs: Set<UUID>, reverse: Bool) async throws {
        guard let patch = Self.buildSelectedPatch(path: path, oldPath: oldPath,
                                                  hunks: hunks, selectedIDs: selectedIDs) else { return }
        var arguments = ["apply", "--cached", "--recount", "--whitespace=nowarn"]
        if reverse { arguments.append("--reverse") }
        try await run(arguments, input: Data(patch.utf8))
    }

    /// Build a patch that keeps only the selected +/- lines; unselected deletions
    /// become context and unselected additions are dropped. Applied with --recount.
    static func buildSelectedPatch(path: String, oldPath: String?,
                                   hunks: [DiffHunk], selectedIDs: Set<UUID>) -> String? {
        var body = ""
        var any = false
        for hunk in hunks {
            guard hunk.lines.contains(where: { selectedIDs.contains($0.id) }) else { continue }
            any = true
            body += "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@\n"
            for line in hunk.lines {
                switch line.kind {
                case .context:
                    body += " \(line.text)\n"
                case .deletion:
                    body += selectedIDs.contains(line.id) ? "-\(line.text)\n" : " \(line.text)\n"
                case .addition:
                    if selectedIDs.contains(line.id) { body += "+\(line.text)\n" }
                case .noNewline:
                    body += "\\ No newline at end of file\n"
                }
            }
        }
        guard any else { return nil }
        let old = oldPath ?? path
        return "diff --git a/\(old) b/\(path)\n--- a/\(old)\n+++ b/\(path)\n" + body
    }

    /// Reconstruct a minimal, appliable unified-diff patch for one hunk.
    static func buildHunkPatch(path: String, oldPath: String?, hunk: DiffHunk) -> String {
        let old = oldPath ?? path
        var text = "diff --git a/\(old) b/\(path)\n"
        text += "--- a/\(old)\n"
        text += "+++ b/\(path)\n"
        text += "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@\n"
        for line in hunk.lines {
            switch line.kind {
            case .context: text += " \(line.text)\n"
            case .addition: text += "+\(line.text)\n"
            case .deletion: text += "-\(line.text)\n"
            case .noNewline: text += "\\ No newline at end of file\n"
            }
        }
        return text
    }

    // MARK: - Submodules

    func submodules() async throws -> [Submodule] {
        let output = try await runRaw(["submodule", "status", "--recursive"])
        return Self.parseSubmodules(output.standardOutput)
    }

    // MARK: - File history & blame

    func fileHistory(path: String, limit: Int) async throws -> [Commit] {
        try await log(revisions: ["--follow", "HEAD"], limit: limit, pathspec: [path])
    }

    func blame(path: String) async throws -> [BlameLine] {
        let output = try await run(["blame", "--porcelain", "--", path])
        return Self.parseBlame(output)
    }

    /// The diff a commit made to a single file.
    func fileDiffAt(sha: String, path: String) async throws -> FileDiff {
        let output = try await run(["show", "--no-color", "--format=", sha, "--", path])
        return DiffParser.parse(output).first ?? FileDiff.placeholder(path: path)
    }

    // MARK: - Conflict resolution

    func checkoutSide(path: String, theirs: Bool) async throws {
        try await run(["checkout", theirs ? "--theirs" : "--ours", "--", path])
        try await run(["add", "--", path])
    }

    func markResolved(path: String) async throws {
        try await run(["add", "--", path])
    }

    func mergeAbort() async throws {
        try await run(["merge", "--abort"])
    }

    // MARK: - Interactive rebase

    /// Run an interactive rebase onto `base`, driving the todo non-interactively.
    /// `messages`, if non-empty, are consumed in order by the commit-message editor
    /// (one per reword, in todo order).
    func interactiveRebase(onto base: String, todo: String, messages: [String] = []) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-rebase-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let todoURL = dir.appendingPathComponent("todo.txt")
        try todo.write(to: todoURL, atomically: true, encoding: .utf8)

        // git invokes the sequence editor as `sh -c "<GIT_SEQUENCE_EDITOR> <todofile>"`,
        // so `cp "$OUR_TODO"` overwrites the todo file with ours.
        var environment = [
            "OUR_TODO": todoURL.path,
            "GIT_SEQUENCE_EDITOR": "cp \"$OUR_TODO\""
        ]

        if messages.isEmpty {
            environment["GIT_EDITOR"] = "true"   // accept default messages
        } else {
            let msgsDir = dir.appendingPathComponent("msgs", isDirectory: true)
            try FileManager.default.createDirectory(at: msgsDir, withIntermediateDirectories: true)
            for (index, message) in messages.enumerated() {
                try message.write(to: msgsDir.appendingPathComponent("\(index).txt"),
                                  atomically: true, encoding: .utf8)
            }
            let idxURL = dir.appendingPathComponent("idx")
            try "0".write(to: idxURL, atomically: true, encoding: .utf8)

            let scriptURL = dir.appendingPathComponent("editor.sh")
            let script = """
            #!/bin/sh
            i=$(cat "$MSG_IDX")
            cp "$MSGS_DIR/$i.txt" "$1"
            echo $((i + 1)) > "$MSG_IDX"
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            environment["MSG_IDX"] = idxURL.path
            environment["MSGS_DIR"] = msgsDir.path
            environment["GIT_EDITOR"] = scriptURL.path
        }

        try await run(["rebase", "-i", base], environment: environment)
    }

    func rebaseAbort() async throws {
        try await run(["rebase", "--abort"])
    }

    func rebaseContinue() async throws {
        try await run(["rebase", "--continue"], environment: ["GIT_EDITOR": "true"])
    }

    // MARK: - Clone

    static func clone(url: String, into destination: URL) async throws {
        let parent = destination.deletingLastPathComponent()
        let name = destination.lastPathComponent
        let output = try await GitProcess.run(["-C", parent.path, "clone", "--progress", url, name])
        guard output.isSuccess else {
            throw GitError.commandFailed(command: "clone", exitCode: output.exitCode,
                                         message: output.standardError.isEmpty ? output.standardOutput : output.standardError)
        }
    }

    // MARK: - Config (identity etc.)

    func config(_ key: String, global: Bool = false) async throws -> String? {
        var arguments = ["config"]
        if global { arguments.append("--global") }
        arguments += ["--get", key]
        let output = try await runRaw(arguments)
        guard output.isSuccess else { return nil }
        let value = output.trimmedOutput
        return value.isEmpty ? nil : value
    }

    func setConfig(_ key: String, _ value: String, global: Bool) async throws {
        var arguments = ["config"]
        if global { arguments.append("--global") }
        arguments += [key, value]
        try await run(arguments)
    }

    // MARK: - Credentials

    /// Store credentials via the configured credential helper (osxkeychain).
    func credentialApprove(_ input: String) async throws {
        try await run(["credential", "approve"], input: Data(input.utf8))
    }

    /// Repository-independent credential storage (used by clone).
    static func credentialApprove(_ input: String) async throws {
        let output = try await GitProcess.run(["credential", "approve"], input: Data(input.utf8))
        guard output.isSuccess else {
            throw GitError.commandFailed(command: "credential", exitCode: output.exitCode, message: output.standardError)
        }
    }

    static func ensureCredentialHelper() async throws {
        let output = try await GitProcess.run(["config", "--global", "--get", "credential.helper"])
        if output.trimmedOutput.isEmpty {
            _ = try await GitProcess.run(["config", "--global", "credential.helper", "osxkeychain"])
        }
    }

    /// Parse a remote URL into (scheme, host).
    static func remoteInfo(_ url: String) -> (scheme: String, host: String)? {
        if url.hasPrefix("http://") || url.hasPrefix("https://"),
           let parsed = URL(string: url), let host = parsed.host {
            return (parsed.scheme ?? "https", host)
        }
        if url.hasPrefix("ssh://"), let parsed = URL(string: url), let host = parsed.host {
            return ("ssh", host)
        }
        // scp-like: git@host:path
        if let at = url.firstIndex(of: "@") {
            let rest = url[url.index(after: at)...]
            if let colon = rest.firstIndex(of: ":") {
                return ("ssh", String(rest[..<colon]))
            }
        }
        return nil
    }

    // MARK: - Remotes

    func addRemote(name: String, url: String) async throws {
        try await run(["remote", "add", name, url])
    }
    func removeRemote(name: String) async throws {
        try await run(["remote", "remove", name])
    }
    func setRemoteURL(name: String, url: String) async throws {
        try await run(["remote", "set-url", name, url])
    }

    // MARK: - Stash diff

    func stashDiff(selector: String) async throws -> [FileDiff] {
        let output = try await run(["stash", "show", "-p", "--no-color", selector])
        return DiffParser.parse(output)
    }

    // MARK: - Merge & rebase variants

    func mergeSquash(branch: String) async throws {
        try await run(["merge", "--squash", branch])
    }
    func rebase(onto branch: String) async throws {
        try await run(["rebase", branch])
    }

    // MARK: - Branch / tag management

    func renameBranch(old: String, new: String) async throws {
        try await run(["branch", "-m", old, new])
    }

    /// Rename a branch on a remote: push the tracked commit to the new name,
    /// then delete the old one (git has no direct remote-rename).
    func renameRemoteBranch(remote: String, old: String, new: String) async throws {
        try await run(["push", remote, "refs/remotes/\(remote)/\(old):refs/heads/\(new)"])
        try await run(["push", remote, "--delete", old])
    }
    func setUpstream(branch: String, upstream: String) async throws {
        try await run(["branch", "--set-upstream-to=\(upstream)", branch])
    }
    func pushSetUpstream(remote: String, branch: String) async throws {
        try await run(["push", "-u", remote, branch])
    }
    func pushTags(remote: String) async throws {
        try await run(["push", remote, "--tags"])
    }
    func deleteRemoteBranch(remote: String, branch: String) async throws {
        try await run(["push", remote, "--delete", branch])
    }
    func deleteTag(name: String) async throws {
        try await run(["tag", "-d", name])
    }
    func pushTag(remote: String, name: String) async throws {
        try await run(["push", remote, "refs/tags/\(name)"])
    }
    func deleteRemoteTag(remote: String, name: String) async throws {
        try await run(["push", remote, "--delete", "refs/tags/\(name)"])
    }

    // MARK: - Amend helper

    func lastCommitMessage() async throws -> String {
        try await run(["log", "-1", "--pretty=%B"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Submodule actions

    func submoduleUpdate(initialize: Bool, recursive: Bool) async throws {
        var arguments = ["submodule", "update"]
        if initialize { arguments.append("--init") }
        if recursive { arguments.append("--recursive") }
        try await run(arguments)
    }

    // MARK: - Reflog

    func reflog(limit: Int) async throws -> [ReflogEntry] {
        let format = ["%h", "%gd", "%gs", "%an", "%ct"].joined(separator: "%x1f")
        let output = try await run(["reflog", "--format=\(format)", "-n", String(limit)])
        return Self.parseReflog(output)
    }

    // MARK: - Worktrees

    func worktrees() async throws -> [Worktree] {
        let output = try await run(["worktree", "list", "--porcelain"])
        return Self.parseWorktrees(output)
    }
    func addWorktree(path: String, branch: String) async throws {
        try await run(["worktree", "add", path, branch])
    }
    func removeWorktree(path: String) async throws {
        try await run(["worktree", "remove", path])
    }

    // MARK: - Bisect

    func bisectStart() async throws { try await run(["bisect", "start"]) }
    func bisectGood() async throws { try await run(["bisect", "good"]) }
    func bisectBad() async throws { try await run(["bisect", "bad"]) }
    func bisectReset() async throws { try await run(["bisect", "reset"]) }

    // MARK: - Search

    func grep(_ query: String, limit: Int = 200) async throws -> [GrepMatch] {
        guard !query.isEmpty else { return [] }
        let output = try await runRaw(["grep", "-n", "-I", "--no-color", "-e", query])
        // grep exits 1 when no matches — treat as empty, not an error.
        return Self.parseGrep(output.standardOutput, limit: limit)
    }

    // MARK: - Compare two commits

    func diffBetween(_ a: String, _ b: String, ignoreWhitespace: Bool = false) async throws -> [FileDiff] {
        var arguments = ["diff", "--no-color", "--find-renames"]
        if ignoreWhitespace { arguments.append("-w") }
        arguments += [a, b]
        return DiffParser.parse(try await run(arguments))
    }

    // MARK: - Blob (for image diff)

    func blob(ref: String, path: String) async throws -> Data {
        let output = try await runRaw(["show", "\(ref):\(path)"])
        return output.outputData
    }

    // MARK: - ⭐️ Signature feature: pull a single file from upstream

    /// Update just one file to the version on `ref` (e.g. "origin/main"),
    /// leaving every other local change untouched. This is the "pull one file"
    /// workflow that Fork does not offer.
    func updateFile(path: String, fromRef ref: String) async throws {
        try await run(["checkout", ref, "--", path])
    }

    // MARK: - ⭐️ Signature feature: stop tracking / ignore local changes

    /// Stop tracking a file but keep it on disk (`git rm --cached`).
    func stopTracking(path: String) async throws {
        try await run(["rm", "--cached", "--", path])
    }

    /// Toggle skip-worktree — tell git to ignore local edits to a tracked file.
    func setSkipWorktree(path: String, enabled: Bool) async throws {
        try await run(["update-index", enabled ? "--skip-worktree" : "--no-skip-worktree", "--", path])
    }

    /// Toggle assume-unchanged for a tracked file.
    func setAssumeUnchanged(path: String, enabled: Bool) async throws {
        try await run(["update-index", enabled ? "--assume-unchanged" : "--no-assume-unchanged", "--", path])
    }

    /// Read the per-file flags reported by `git ls-files -v`.
    /// Returns a map of path -> lowercase status letter (`s` = skip-worktree,
    /// `h` = assume-unchanged).
    func hiddenTrackingFlags() async throws -> [String: Character] {
        let output = try await run(["ls-files", "-v"])
        var flags: [String: Character] = [:]
        for line in output.split(separator: "\n") {
            guard let first = line.first else { continue }
            // Lowercase letters mark skip-worktree (S) / assume-unchanged (h) etc.
            if first == "S" || first == "s" || first == "h" {
                let path = String(line.dropFirst(2))
                flags[path] = Character(first.lowercased())
            }
        }
        return flags
    }

    /// Append a path to the repository's .gitignore (creating it if needed).
    func addToGitignore(pattern: String) async throws {
        let ignoreURL = root.appendingPathComponent(".gitignore")
        var contents = (try? String(contentsOf: ignoreURL, encoding: .utf8)) ?? ""
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents.append("\n") }
        // Avoid duplicate entries.
        let existing = Set(contents.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        guard !existing.contains(pattern) else { return }
        contents.append(pattern + "\n")
        try contents.write(to: ignoreURL, atomically: true, encoding: .utf8)
    }
}

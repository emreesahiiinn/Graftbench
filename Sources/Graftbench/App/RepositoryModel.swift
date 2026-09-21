import Foundation
import Observation

/// An item selectable in the sidebar. Drives what the center pane shows.
enum SidebarItem: Hashable {
    case workingCopy
    case allBranches
    case localBranch(String)
    case remoteBranch(String)
    case tag(String)
    case stash(String)
}

/// A reference to a specific change on a specific side of the index.
struct ChangeRef: Hashable {
    let path: String
    let staged: Bool
}

/// A single-level undoable git operation (Tower-style Undo).
struct UndoableOperation {
    let label: String
    let perform: () async throws -> Void
}

/// An authentication challenge raised when a remote operation needs credentials.
struct AuthChallenge: Identifiable {
    let id = UUID()
    let scheme: String
    let host: String
}

/// The tabs available in the commit detail (bottom) panel.
enum DetailTab: String, CaseIterable, Hashable {
    case commit = "Commit"
    case changes = "Changes"
    case fileTree = "File Tree"

    var symbol: String {
        switch self {
        case .commit: return "text.justify.left"
        case .changes: return "plusminus"
        case .fileTree: return "folder"
        }
    }
}

/// Observable state and operations for a single open repository.
@MainActor
@Observable
final class RepositoryModel: Identifiable {
    let id = UUID()
    let root: URL
    let client: GitClient
    var name: String

    // Loaded data
    var commits: [Commit] = []
    var graph: CommitGraph = .empty
    var status: WorkingStatus = .empty
    var branches: [Branch] = []
    var remotes: [Remote] = []
    var tags: [Tag] = []
    var stashes: [Stash] = []
    var submodules: [Submodule] = []
    var worktrees: [Worktree] = []
    var hiddenFlags: [String: Character] = [:]

    // Selection
    var sidebarSelection: SidebarItem = .workingCopy
    var selectedCommitID: String?
    var commitDiffs: [FileDiff] = []
    var selectedCommitFileID: FileDiff.ID?
    var selectedChange: ChangeRef?
    var changeDiff: FileDiff?
    var selectedLineIDs: Set<UUID> = []

    // Commit composer
    var commitMessage: String = ""
    var amend: Bool = false

    // History search
    var historyFilter: String = ""
    var historyLimit: Int = 200
    var compareMarked: String?

    // Detail panel (bottom pane)
    var detailTab: DetailTab = .changes
    var isDetailCollapsed = false

    // UI state
    var isLoading = false
    var isBusy = false
    var lastError: String?
    var toast: String?
    var undoable: UndoableOperation?
    var authChallenge: AuthChallenge?

    @ObservationIgnored private var watcher: RepositoryWatcher?
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var authRetry: (() async -> Void)?

    // Derived
    var localBranches: [Branch] { branches.filter { !$0.isRemote } }
    var remoteBranches: [Branch] { branches.filter { $0.isRemote } }
    var currentBranch: Branch? { branches.first { $0.isCurrent } }
    var selectedCommit: Commit? {
        guard let id = selectedCommitID else { return nil }
        return commits.first { $0.id == id }
    }
    var canPush: Bool { (currentBranch?.ahead ?? 0) > 0 || currentBranch?.upstream == nil }
    var canPull: Bool { (currentBranch?.behind ?? 0) > 0 }

    var isRebasing: Bool {
        let git = root.appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: git.appendingPathComponent("rebase-merge").path)
            || FileManager.default.fileExists(atPath: git.appendingPathComponent("rebase-apply").path)
    }

    var isBisecting: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git/BISECT_LOG").path)
    }

    var isFiltering: Bool {
        !historyFilter.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var visibleCommits: [Commit] {
        let query = historyFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return commits }
        return commits.filter {
            $0.subject.lowercased().contains(query)
            || $0.authorName.lowercased().contains(query)
            || $0.shortSHA.contains(query)
            || $0.id.hasPrefix(query)
        }
    }

    init(root: URL) {
        self.root = root
        self.client = GitClient(root: root)
        self.name = root.lastPathComponent
    }

    // MARK: - Loading

    func initialLoad() async {
        isLoading = true
        await reloadEverything()
        sidebarSelection = status.isClean ? .allBranches : .workingCopy
        isLoading = false
        startWatching()
    }

    // MARK: - Auto refresh (file-system watching)

    func startWatching() {
        guard watcher == nil else { return }
        watcher = RepositoryWatcher(root: root) { [weak self] in
            Task { @MainActor in self?.scheduleAutoRefresh() }
        }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            if self.isBusy { return }
            await self.reloadEverything()
            await self.refreshSelectedDiff()
        }
    }

    func reloadEverything() async {
        async let statusTask = client.status()
        async let branchesTask = client.branches()
        async let remotesTask = client.remotes()
        async let tagsTask = client.tags()
        async let stashesTask = client.stashes()
        async let submodulesTask = client.submodules()
        async let worktreesTask = client.worktrees()
        async let flagsTask = client.hiddenTrackingFlags()

        status = (try? await statusTask) ?? .empty
        branches = (try? await branchesTask) ?? []
        remotes = (try? await remotesTask) ?? []
        tags = (try? await tagsTask) ?? []
        stashes = (try? await stashesTask) ?? []
        submodules = (try? await submodulesTask) ?? []
        worktrees = (try? await worktreesTask) ?? []
        hiddenFlags = (try? await flagsTask) ?? [:]

        await loadHistory()
    }

    func loadHistory() async {
        let scope: SidebarItem = (sidebarSelection == .workingCopy) ? .allBranches : sidebarSelection
        do {
            let commits = try await client.log(revisions: revisions(for: scope), limit: historyLimit)
            self.commits = commits
            self.graph = GraphLayout.compute(commits: commits)
        } catch {
            self.commits = []
            self.graph = .empty
        }
    }

    var canLoadMoreHistory: Bool { commits.count >= historyLimit }

    func loadMoreHistory() async {
        historyLimit += 200
        await loadHistory()
    }

    private func revisions(for item: SidebarItem) -> [String] {
        switch item {
        case .workingCopy, .allBranches:
            return ["--branches", "--tags", "--remotes", "HEAD"]
        case let .localBranch(name), let .remoteBranch(name), let .tag(name), let .stash(name):
            return [name]
        }
    }

    // MARK: - Selection

    func select(_ item: SidebarItem) async {
        sidebarSelection = item
        historyLimit = 200
        if item == .workingCopy {
            await refreshStatusOnly()
        } else {
            await loadHistory()
            if let first = commits.first {
                await selectCommit(first.id)
            }
        }
    }

    func refreshStatusOnly() async {
        status = (try? await client.status()) ?? status
        hiddenFlags = (try? await client.hiddenTrackingFlags()) ?? hiddenFlags
        await refreshSelectedDiff()
    }

    func selectCommit(_ sha: String) async {
        selectedCommitID = sha
        selectedCommitFileID = nil
        guard let commit = commits.first(where: { $0.id == sha }) else {
            commitDiffs = []
            return
        }
        do {
            let diffs = try await client.commitDiff(sha: sha, firstParent: commit.parents.first,
                                                    ignoreWhitespace: Preferences.shared.ignoreWhitespaceInDiff,
                                                    fullContext: Preferences.shared.diffFullFile)
            commitDiffs = diffs
            selectedCommitFileID = diffs.first?.id
        } catch {
            commitDiffs = []
            lastError = shortError(error)
        }
    }

    func selectChange(_ ref: ChangeRef) async {
        selectedLineIDs.removeAll()
        selectedChange = ref
        guard let entry = status.entries.first(where: { $0.path == ref.path }) else {
            changeDiff = nil
            return
        }
        let ws = Preferences.shared.ignoreWhitespaceInDiff
        let full = Preferences.shared.diffFullFile
        do {
            if ref.staged {
                changeDiff = try await client.diff(path: ref.path, staged: true, ignoreWhitespace: ws, fullContext: full)
            } else if entry.isUntracked {
                changeDiff = try await client.untrackedDiff(path: ref.path)
            } else {
                changeDiff = try await client.diff(path: ref.path, staged: false, ignoreWhitespace: ws, fullContext: full)
            }
        } catch {
            changeDiff = nil
            lastError = shortError(error)
        }
    }

    private func refreshSelectedDiff() async {
        if let ref = selectedChange,
           status.entries.contains(where: { $0.path == ref.path }) {
            await selectChange(ref)
        } else {
            selectedChange = nil
            changeDiff = nil
        }
    }

    /// Rebuild the currently shown diff (e.g. after toggling ignore-whitespace).
    func reloadCurrentDiff() async {
        if sidebarSelection == .workingCopy, let ref = selectedChange {
            await selectChange(ref)
        } else if let sha = selectedCommitID {
            await selectCommit(sha)
        }
    }

    // MARK: - Mutation helper

    private func perform(refresh: Bool = true, _ action: @escaping () async throws -> Void) async {
        isBusy = true
        lastError = nil
        undoable = nil
        do {
            try await action()
            if refresh {
                await reloadEverything()
                await refreshSelectedDiff()
            }
        } catch {
            if let gitError = error as? GitError, gitError.isAuthenticationFailure {
                if let info = primaryRemoteInfo(), info.scheme == "https" {
                    authChallenge = AuthChallenge(scheme: "https", host: info.host)
                    authRetry = { [weak self] in await self?.perform(refresh: refresh, action) }
                } else {
                    lastError = "SSH authentication failed. Add your key with `ssh-add`, or check your access to the remote."
                }
            } else {
                lastError = shortError(error)
            }
        }
        isBusy = false
    }

    private func primaryRemoteInfo() -> (scheme: String, host: String)? {
        guard let remote = remotes.first else { return nil }
        let url = remote.pushURL.isEmpty ? remote.fetchURL : remote.pushURL
        return GitClient.remoteInfo(url)
    }

    func submitCredentials(username: String, secret: String) async {
        guard let challenge = authChallenge else { return }
        authChallenge = nil
        // Ensure a credential helper exists so the secret is stored & reused.
        let helper = (try? await client.config("credential.helper")).flatMap { $0 }
        if helper == nil || (helper?.isEmpty ?? true) {
            try? await client.setConfig("credential.helper", "osxkeychain", global: true)
        }
        let input = "protocol=\(challenge.scheme)\nhost=\(challenge.host)\nusername=\(username)\npassword=\(secret)\n\n"
        try? await client.credentialApprove(input)
        let retry = authRetry
        authRetry = nil
        await retry?()
    }

    func cancelAuth() {
        authChallenge = nil
        authRetry = nil
        lastError = "Authentication cancelled."
    }

    private func shortError(_ error: Error) -> String {
        (error as? GitError)?.shortMessage ?? error.localizedDescription
    }

    // MARK: - Staging & commit

    func stage(paths: [String]) async { await perform { try await self.client.stage(paths: paths) } }
    func unstage(paths: [String]) async { await perform { try await self.client.unstage(paths: paths) } }
    func stageAll() async { await perform { try await self.client.stageAll() } }
    func unstageAll() async { await perform { try await self.client.unstageAll() } }

    func discard(_ entry: StatusEntry) async {
        await perform { try await self.client.discard(paths: [entry.path], untracked: entry.isUntracked) }
    }

    func commit() async {
        let trimmed = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { lastError = "Nothing to commit — the message is empty."; return }
        let amending = amend
        let preHead = amending ? nil : (try? await client.revParse("HEAD"))
        await perform { try await self.client.commit(message: self.commitMessage, amend: amending, sign: Preferences.shared.signCommits) }
        if lastError == nil {
            commitMessage = ""
            amend = false
            if let preHead {
                setUndo("Commit") { try await self.client.reset(to: preHead, mode: "soft") }
            }
            toast = "Committed"
        }
    }

    func commitAndPush() async {
        await commit()
        if lastError == nil { await push() }
    }

    // MARK: - Sync

    func fetch() async {
        await perform { try await self.client.fetch(remote: nil, prune: true) }
        if lastError == nil { toast = "Fetched" }
    }

    func fetch(remote: String) async {
        await perform { try await self.client.fetch(remote: remote, prune: true) }
        if lastError == nil { toast = "Fetched \(remote)" }
    }

    func pull() async {
        await pull(rebase: Preferences.shared.useRebaseOnPull)
    }

    func pull(rebase: Bool) async {
        await perform { try await self.client.pull(rebase: rebase) }
        if lastError == nil { toast = rebase ? "Pulled (rebase)" : "Pulled" }
    }

    func push(force: Bool = false) async {
        let hasUpstream = currentBranch?.upstream != nil
        let remote = remotes.first?.name
        let branch = currentBranch?.name
        await perform {
            try await self.client.push(remote: hasUpstream ? nil : remote,
                                       branch: hasUpstream ? nil : branch,
                                       setUpstream: !hasUpstream,
                                       force: force)
        }
        if lastError == nil { toast = force ? "Force-pushed" : "Pushed" }
    }

    func pushAllTags() async {
        guard let remote = remotes.first?.name else { lastError = "No remote configured."; return }
        await perform { try await self.client.pushTags(remote: remote) }
        if lastError == nil { toast = "Pushed all tags" }
    }

    // MARK: - Branches

    func checkout(_ branch: Branch) async {
        let previous = currentBranch?.name
        if branch.isRemote {
            await perform { try await self.client.checkoutRemoteTracking(local: branch.shortName, remoteRef: branch.name) }
        } else {
            await perform { try await self.client.checkout(branch: branch.name) }
        }
        if lastError == nil {
            if let previous { setUndo("Checkout") { try await self.client.checkout(branch: previous) } }
            toast = "Switched to \(branch.shortName)"
        }
    }

    func createBranch(name: String, at commit: Commit? = nil, checkout: Bool) async {
        await perform {
            if let commit {
                try await self.client.branch(name: name, at: commit.id)
                if checkout { try await self.client.checkout(branch: name) }
            } else {
                try await self.client.createBranch(name: name, checkout: checkout)
            }
        }
        if lastError == nil {
            setUndo("Create Branch") { try await self.client.deleteBranch(name: name, force: true) }
            toast = "Created branch \(name)"
        }
    }

    func deleteBranch(_ branch: Branch, force: Bool) async {
        let name = branch.name
        let sha = branch.targetSHA
        await perform { try await self.client.deleteBranch(name: name, force: force) }
        if lastError == nil {
            setUndo("Delete Branch") { try await self.client.branch(name: name, at: sha) }
            toast = "Deleted \(name)"
        }
    }

    func createTag(name: String, message: String?, at commit: Commit? = nil) async {
        let ref = commit?.id ?? "HEAD"
        await perform { try await self.client.tag(name: name, at: ref, message: message) }
        if lastError == nil {
            setUndo("Create Tag") { try await self.client.run(["tag", "-d", name]) }
            toast = "Created tag \(name)"
        }
    }

    func merge(_ branch: Branch) async {
        let preHead = try? await client.revParse("HEAD")
        await perform { try await self.client.merge(branch: branch.name, noFastForward: false) }
        if lastError == nil {
            if let preHead { setUndo("Merge") { try await self.client.reset(to: preHead, mode: "hard") } }
            toast = "Merged \(branch.shortName)"
        }
    }

    // MARK: - Commit operations

    func checkoutCommit(_ commit: Commit) async {
        let previous = currentBranch?.name
        await perform { try await self.client.checkoutDetached(sha: commit.id) }
        if lastError == nil {
            if let previous { setUndo("Checkout") { try await self.client.checkout(branch: previous) } }
            toast = "Checked out \(commit.shortSHA)"
        }
    }

    func cherryPick(_ commit: Commit) async {
        await cherryPick(sha: commit.id)
    }

    func cherryPick(sha: String) async {
        let preHead = try? await client.revParse("HEAD")
        await perform { try await self.client.cherryPick(sha: sha) }
        if lastError == nil {
            if let preHead { setUndo("Cherry-Pick") { try await self.client.reset(to: preHead, mode: "hard") } }
            toast = "Cherry-picked \(String(sha.prefix(7)))"
        }
    }

    func revertCommit(_ commit: Commit) async {
        let preHead = try? await client.revParse("HEAD")
        await perform { try await self.client.revert(sha: commit.id) }
        if lastError == nil {
            if let preHead { setUndo("Revert") { try await self.client.reset(to: preHead, mode: "hard") } }
            toast = "Reverted \(commit.shortSHA)"
        }
    }

    func reset(to commit: Commit, mode: String) async {
        let preHead = try? await client.revParse("HEAD")
        await perform { try await self.client.reset(to: commit.id, mode: mode) }
        if lastError == nil {
            if mode != "hard", let preHead {
                setUndo("Reset") { try await self.client.reset(to: preHead, mode: "soft") }
            }
            toast = "Reset to \(commit.shortSHA)"
        }
    }

    // MARK: - Undo (Tower-style)

    private func setUndo(_ label: String, _ perform: @escaping () async throws -> Void) {
        undoable = UndoableOperation(label: label, perform: perform)
    }

    func undoLast() async {
        guard let operation = undoable else { return }
        undoable = nil
        await perform { try await operation.perform() }
        if lastError == nil { toast = "Undone: \(operation.label)" }
    }

    // MARK: - Hunk staging

    func stageHunk(_ hunk: DiffHunk) async {
        guard let ref = selectedChange, !ref.staged, let diff = changeDiff else { return }
        await perform {
            try await self.client.applyHunk(path: diff.newPath ?? ref.path, oldPath: diff.oldPath,
                                            hunk: hunk, toIndex: true, reverse: false)
        }
    }

    func unstageHunk(_ hunk: DiffHunk) async {
        guard let ref = selectedChange, ref.staged, let diff = changeDiff else { return }
        await perform {
            try await self.client.applyHunk(path: diff.newPath ?? ref.path, oldPath: diff.oldPath,
                                            hunk: hunk, toIndex: true, reverse: true)
        }
    }

    func discardHunk(_ hunk: DiffHunk) async {
        guard let ref = selectedChange, !ref.staged, let diff = changeDiff else { return }
        await perform {
            try await self.client.applyHunk(path: diff.newPath ?? ref.path, oldPath: diff.oldPath,
                                            hunk: hunk, toIndex: false, reverse: true)
        }
    }

    // MARK: - Line staging

    func toggleLine(_ line: DiffLine) {
        if selectedLineIDs.contains(line.id) { selectedLineIDs.remove(line.id) }
        else { selectedLineIDs.insert(line.id) }
    }

    func clearLineSelection() { selectedLineIDs.removeAll() }

    func stageSelectedLines() async {
        guard let ref = selectedChange, !ref.staged, let diff = changeDiff, !selectedLineIDs.isEmpty else { return }
        let ids = selectedLineIDs
        await perform {
            try await self.client.applySelectedLines(path: diff.newPath ?? ref.path, oldPath: diff.oldPath,
                                                     hunks: diff.hunks, selectedIDs: ids, reverse: false)
        }
        selectedLineIDs.removeAll()
    }

    func unstageSelectedLines() async {
        guard let ref = selectedChange, ref.staged, let diff = changeDiff, !selectedLineIDs.isEmpty else { return }
        let ids = selectedLineIDs
        await perform {
            try await self.client.applySelectedLines(path: diff.newPath ?? ref.path, oldPath: diff.oldPath,
                                                     hunks: diff.hunks, selectedIDs: ids, reverse: true)
        }
        selectedLineIDs.removeAll()
    }

    // MARK: - Stash

    func stashPush(message: String?, includeUntracked: Bool) async {
        await perform { try await self.client.stashPush(message: message, includeUntracked: includeUntracked) }
        if lastError == nil { toast = "Stashed changes" }
    }

    func stashApply(_ stash: Stash, pop: Bool) async {
        await perform { try await self.client.stashApply(selector: stash.selector, pop: pop) }
    }

    func stashDrop(_ stash: Stash) async {
        await perform { try await self.client.stashDrop(selector: stash.selector) }
    }

    // MARK: - Conflict resolution

    func resolveUsingOurs(_ entry: StatusEntry) async {
        await perform { try await self.client.checkoutSide(path: entry.path, theirs: false) }
        if lastError == nil { toast = "Kept ours: \(entry.fileName)" }
    }

    func resolveUsingTheirs(_ entry: StatusEntry) async {
        await perform { try await self.client.checkoutSide(path: entry.path, theirs: true) }
        if lastError == nil { toast = "Took theirs: \(entry.fileName)" }
    }

    func markResolved(_ entry: StatusEntry) async {
        await perform { try await self.client.markResolved(path: entry.path) }
    }

    func abortMerge() async {
        await perform { try await self.client.mergeAbort() }
    }

    // MARK: - Interactive rebase

    func commitsToRebase(base: String) async -> [Commit] {
        (try? await client.log(revisions: ["\(base)..HEAD"], limit: 300)) ?? []
    }

    func runInteractiveRebase(base: String, todo: String, messages: [String] = []) async {
        await perform { try await self.client.interactiveRebase(onto: base, todo: todo, messages: messages) }
        if lastError == nil { toast = "Rebase complete" }
    }

    func abortRebase() async {
        await perform { try await self.client.rebaseAbort() }
    }

    func continueRebase() async {
        await perform { try await self.client.rebaseContinue() }
    }

    // MARK: - Merge & rebase variants

    func mergeSquash(_ branch: Branch) async {
        await perform { try await self.client.mergeSquash(branch: branch.name) }
        if lastError == nil { toast = "Squash-merged \(branch.shortName)" }
    }

    func rebaseOnto(_ branch: Branch) async {
        let preHead = try? await client.revParse("HEAD")
        await perform { try await self.client.rebase(onto: branch.name) }
        if lastError == nil {
            if let preHead { setUndo("Rebase") { try await self.client.reset(to: preHead, mode: "hard") } }
            toast = "Rebased onto \(branch.shortName)"
        }
    }

    // MARK: - Branch / tag management

    func renameBranch(_ branch: Branch, to newName: String) async {
        await perform { try await self.client.renameBranch(old: branch.name, new: newName) }
        if lastError == nil { toast = "Renamed to \(newName)" }
    }

    func renameRemoteBranch(_ branch: Branch, to newName: String) async {
        guard let remote = branch.remoteName else { return }
        await perform {
            try await self.client.renameRemoteBranch(remote: remote, old: branch.shortName, new: newName)
        }
        if lastError == nil { toast = "Renamed remote branch to \(newName)" }
    }

    /// Route rename to the right operation depending on branch kind.
    func rename(_ branch: Branch, to newName: String) async {
        if branch.isRemote { await renameRemoteBranch(branch, to: newName) }
        else { await renameBranch(branch, to: newName) }
    }

    func setUpstream(_ branch: Branch, upstream: String) async {
        await perform { try await self.client.setUpstream(branch: branch.name, upstream: upstream) }
    }

    func pushBranch(_ branch: Branch) async {
        guard let remote = remotes.first?.name else { lastError = "No remote configured."; return }
        await perform { try await self.client.pushSetUpstream(remote: remote, branch: branch.name) }
        if lastError == nil { toast = "Pushed \(branch.name)" }
    }

    func deleteRemoteBranch(_ branch: Branch) async {
        guard let remote = branch.remoteName else { return }
        await perform { try await self.client.deleteRemoteBranch(remote: remote, branch: branch.shortName) }
        if lastError == nil { toast = "Deleted \(branch.name)" }
    }

    func pushTag(_ tag: Tag) async {
        guard let remote = remotes.first?.name else { lastError = "No remote configured."; return }
        await perform { try await self.client.pushTag(remote: remote, name: tag.name) }
        if lastError == nil { toast = "Pushed tag \(tag.name)" }
    }

    func deleteTag(_ tag: Tag) async {
        await perform { try await self.client.deleteTag(name: tag.name) }
        if lastError == nil { toast = "Deleted tag \(tag.name)" }
    }

    func deleteRemoteTag(_ tag: Tag) async {
        guard let remote = remotes.first?.name else { return }
        await perform { try await self.client.deleteRemoteTag(remote: remote, name: tag.name) }
    }

    // MARK: - Remotes

    func addRemote(name: String, url: String) async {
        await perform { try await self.client.addRemote(name: name, url: url) }
    }
    func removeRemote(_ remote: Remote) async {
        await perform { try await self.client.removeRemote(name: remote.name) }
    }
    func setRemoteURL(_ remote: Remote, url: String) async {
        await perform { try await self.client.setRemoteURL(name: remote.name, url: url) }
    }

    // MARK: - Submodules

    func updateSubmodules() async {
        await perform { try await self.client.submoduleUpdate(initialize: true, recursive: true) }
        if lastError == nil { toast = "Submodules updated" }
    }

    // MARK: - Worktrees

    func addWorktree(path: String, branch: String) async {
        await perform { try await self.client.addWorktree(path: path, branch: branch) }
        if lastError == nil { toast = "Worktree added" }
    }
    func removeWorktree(_ worktree: Worktree) async {
        await perform { try await self.client.removeWorktree(path: worktree.path) }
        if lastError == nil { toast = "Worktree removed" }
    }

    // MARK: - Bisect

    func bisectStart() async {
        await perform { try await self.client.bisectStart() }
        if lastError == nil { toast = "Bisect started — mark commits good/bad" }
    }
    func bisectGood() async { await perform { try await self.client.bisectGood() } }
    func bisectBad() async { await perform { try await self.client.bisectBad() } }
    func bisectReset() async {
        await perform { try await self.client.bisectReset() }
        if lastError == nil { toast = "Bisect reset" }
    }

    // MARK: - Identity & amend

    func gitIdentity() async -> (name: String, email: String) {
        let name = (try? await client.config("user.name")).flatMap { $0 } ?? ""
        let email = (try? await client.config("user.email")).flatMap { $0 } ?? ""
        return (name, email)
    }

    func setGitIdentity(name: String, email: String, global: Bool) async {
        await perform(refresh: false) {
            try await self.client.setConfig("user.name", name, global: global)
            try await self.client.setConfig("user.email", email, global: global)
        }
        if lastError == nil { toast = "Identity saved" }
    }

    func setAmend(_ on: Bool) async {
        amend = on
        if on, commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commitMessage = (try? await client.lastCommitMessage()) ?? ""
        }
    }

    // MARK: - ⭐️ Signature: pull a single file from upstream

    func pullFileFromUpstream(_ entry: StatusEntry) async {
        guard let upstream = status.upstream ?? currentBranch?.upstream else {
            lastError = "No upstream is configured for this branch."
            return
        }
        let remote = upstream.split(separator: "/").first.map(String.init)
        await perform {
            try await self.client.fetch(remote: remote, prune: false)
            try await self.client.updateFile(path: entry.path, fromRef: upstream)
        }
        if lastError == nil { toast = "Pulled \(entry.fileName) from \(upstream)" }
    }

    // MARK: - ⭐️ Signature: stop tracking / ignore local changes

    func stopTracking(_ entry: StatusEntry, addToGitignore: Bool) async {
        await perform {
            try await self.client.stopTracking(path: entry.path)
            if addToGitignore { try await self.client.addToGitignore(pattern: entry.path) }
        }
        if lastError == nil { toast = "Stopped tracking \(entry.fileName)" }
    }

    var skipWorktreePaths: Set<String> {
        Set(hiddenFlags.filter { $0.value == "s" }.keys)
    }
    var assumeUnchangedPaths: Set<String> {
        Set(hiddenFlags.filter { $0.value == "h" }.keys)
    }

    func toggleSkipWorktree(_ entry: StatusEntry) async {
        let currently = hiddenFlags[entry.path] == "s"
        await perform { try await self.client.setSkipWorktree(path: entry.path, enabled: !currently) }
        if lastError == nil { toast = currently ? "Tracking local changes again" : "Ignoring local changes" }
    }

    func toggleAssumeUnchanged(_ entry: StatusEntry) async {
        let currently = hiddenFlags[entry.path] == "h"
        await perform { try await self.client.setAssumeUnchanged(path: entry.path, enabled: !currently) }
    }

    func addToGitignore(_ entry: StatusEntry) async {
        await perform { try await self.client.addToGitignore(pattern: entry.path) }
        if lastError == nil { toast = "Added \(entry.fileName) to .gitignore" }
    }
}

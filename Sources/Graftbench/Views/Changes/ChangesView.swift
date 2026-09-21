import SwiftUI
import AppKit

enum FileSheet: Identifiable {
    case history(String)
    case blame(String)
    case conflicts(String)
    var id: String {
        switch self {
        case .history(let path): return "history:\(path)"
        case .blame(let path): return "blame:\(path)"
        case .conflicts(let path): return "conflicts:\(path)"
        }
    }
}

struct ChangesView: View {
    @Bindable var repo: RepositoryModel
    @State private var discardTarget: StatusEntry?
    @State private var pullFileTarget: StatusEntry?
    @State private var activeFileSheet: FileSheet?

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                filesPane
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 560)
                diffPane
                    .frame(minWidth: 340)
            }
            if !repo.selectedLineIDs.isEmpty {
                lineSelectionBar
            }
            Divider()
            commitComposer
        }
        .surface()
        .confirmationDialog(
            "Discard changes to \(discardTarget?.fileName ?? "")?",
            isPresented: Binding(get: { discardTarget != nil }, set: { if !$0 { discardTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                if let target = discardTarget { Task { await repo.discard(target) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Pull \(pullFileTarget?.fileName ?? "") from upstream?",
            isPresented: Binding(get: { pullFileTarget != nil }, set: { if !$0 { pullFileTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Pull This File") {
                if let target = pullFileTarget { Task { await repo.pullFileFromUpstream(target) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Fetches the upstream and replaces only this file with the remote version. Your other local changes are untouched.")
        }
        .sheet(item: $activeFileSheet) { sheet in
            switch sheet {
            case .history(let path): FileHistoryView(client: repo.client, path: path)
            case .blame(let path): BlameView(client: repo.client, path: path)
            case .conflicts(let path):
                if let entry = repo.status.entries.first(where: { $0.path == path }) {
                    ConflictResolverView(repo: repo, entry: entry)
                }
            }
        }
    }

    // MARK: Files pane

    private var filesPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard").foregroundStyle(Theme.accent)
                Text("Local Changes").font(.system(size: 12, weight: .semibold))
                Spacer()
                if repo.isRebasing {
                    Button("Abort Rebase") { Task { await repo.abortRebase() } }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.stateDeleted)
                    Button("Continue Rebase") { Task { await repo.continueRebase() } }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .disabled(!repo.status.conflicted.isEmpty)
                } else if !repo.status.conflicted.isEmpty {
                    Button("Abort Merge") { Task { await repo.abortMerge() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.stateDeleted)
                }
                if !repo.status.isClean {
                    Text("\(repo.status.totalChangeCount)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if repo.status.isClean {
                EmptyStateView(icon: "checkmark.seal.fill",
                               title: "Nothing to commit",
                               subtitle: "Your working tree is clean.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if !repo.status.conflicted.isEmpty {
                            sectionLabel("Conflicts", count: repo.status.conflicted.count, tint: Theme.stateConflict)
                            ForEach(repo.status.conflicted) { row($0, staged: false) }
                        }
                        if !repo.status.unstaged.isEmpty {
                            sectionLabel("Unstaged", count: repo.status.unstaged.count) {
                                Button("Stage All") { Task { await repo.stageAll() } }
                                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                            }
                            ForEach(repo.status.unstaged) { row($0, staged: false) }
                        }
                        if !repo.status.staged.isEmpty {
                            sectionLabel("Staged", count: repo.status.staged.count) {
                                Button("Unstage All") { Task { await repo.unstageAll() } }
                                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                            }
                            ForEach(repo.status.staged) { row($0, staged: true) }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .surface()
    }

    private func row(_ entry: StatusEntry, staged: Bool) -> some View {
        let ref = ChangeRef(path: entry.path, staged: staged)
        return ChangeFileRow(
            entry: entry,
            staged: staged,
            isSelected: repo.selectedChange == ref,
            isSkipWorktree: repo.skipWorktreePaths.contains(entry.path),
            isAssumeUnchanged: repo.assumeUnchangedPaths.contains(entry.path),
            onToggleStage: {
                Task {
                    if staged { await repo.unstage(paths: [entry.path]) }
                    else { await repo.stage(paths: [entry.path]) }
                }
            }
        )
        .onTapGesture { Task { await repo.selectChange(ref) } }
        .contextMenu { contextMenu(for: entry, staged: staged) }
    }

    // MARK: Diff pane

    @ViewBuilder
    private var diffPane: some View {
        if let diff = repo.changeDiff {
            if ImageDiffView.isImage(diff.displayPath), let ref = repo.selectedChange {
                let untracked = repo.status.entries.first(where: { $0.path == ref.path })?.isUntracked ?? false
                ImageDiffView(client: repo.client,
                              oldRef: untracked ? nil : "HEAD",
                              oldPath: untracked ? nil : ref.path,
                              newFileURL: repo.root.appendingPathComponent(ref.path))
            } else {
                let canSelect = hunkActions() != nil
                DiffView(diff: diff, hunkActions: hunkActions(),
                         selectedLines: canSelect ? repo.selectedLineIDs : [],
                         onToggleLine: canSelect ? { repo.toggleLine($0) } : nil,
                         onReload: { Task { await repo.reloadCurrentDiff() } })
            }
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass",
                           title: "Select a file",
                           subtitle: "Pick a changed file to see its diff.")
        }
    }

    private var lineSelectionBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(Theme.accent)
            Text("\(repo.selectedLineIDs.count) line\(repo.selectedLineIDs.count == 1 ? "" : "s") selected")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("Clear") { repo.clearLineSelection() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            if repo.selectedChange?.staged == true {
                Button("Unstage Lines") { Task { await repo.unstageSelectedLines() } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            } else {
                Button("Stage Lines") { Task { await repo.stageSelectedLines() } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.accent.opacity(0.08))
    }

    private func hunkActions() -> HunkActions? {
        guard let ref = repo.selectedChange,
              let entry = repo.status.entries.first(where: { $0.path == ref.path }),
              !entry.isConflicted else { return nil }
        if ref.staged {
            return HunkActions(unstage: { hunk in Task { await repo.unstageHunk(hunk) } })
        }
        if entry.isUntracked { return nil }   // untracked → whole-file staging only
        return HunkActions(
            stage: { hunk in Task { await repo.stageHunk(hunk) } },
            discard: { hunk in Task { await repo.discardHunk(hunk) } }
        )
    }

    // MARK: Context menu (incl. signature features)

    @ViewBuilder
    private func contextMenu(for entry: StatusEntry, staged: Bool) -> some View {
        if entry.isConflicted {
            Button("Resolve Conflicts…") { activeFileSheet = .conflicts(entry.path) }
            Divider()
            Button("Keep Ours") { Task { await repo.resolveUsingOurs(entry) } }
            Button("Take Theirs") { Task { await repo.resolveUsingTheirs(entry) } }
            Button("Mark Resolved") { Task { await repo.markResolved(entry) } }
            Divider()
        }
        if staged {
            Button("Unstage") { Task { await repo.unstage(paths: [entry.path]) } }
        } else {
            Button("Stage") { Task { await repo.stage(paths: [entry.path]) } }
        }
        if !entry.isUntracked {
            Button("Discard Changes…", role: .destructive) { discardTarget = entry }
        }
        Divider()
        Button {
            pullFileTarget = entry
        } label: {
            Label("Pull This File from Upstream", systemImage: "arrow.down.doc")
        }
        .disabled(entry.isUntracked)
        Menu {
            Button("Stop Tracking (keep local file)") {
                Task { await repo.stopTracking(entry, addToGitignore: false) }
            }
            Button("Stop Tracking & Add to .gitignore") {
                Task { await repo.stopTracking(entry, addToGitignore: true) }
            }
            Divider()
            Button(repo.skipWorktreePaths.contains(entry.path)
                   ? "Resume Tracking Local Changes (skip-worktree)"
                   : "Ignore Local Changes (skip-worktree)") {
                Task { await repo.toggleSkipWorktree(entry) }
            }
            Button(repo.assumeUnchangedPaths.contains(entry.path)
                   ? "Undo Assume-Unchanged"
                   : "Assume Unchanged") {
                Task { await repo.toggleAssumeUnchanged(entry) }
            }
            Divider()
            Button("Add to .gitignore") { Task { await repo.addToGitignore(entry) } }
        } label: {
            Label("Tracking", systemImage: "eye.slash")
        }
        if !entry.isUntracked {
            Divider()
            Button("View File History…") { activeFileSheet = .history(entry.path) }
            Button("Blame…") { activeFileSheet = .blame(entry.path) }
        }
        Divider()
        Button("Reveal in Finder") {
            revealInFinder(repo.root.appendingPathComponent(entry.path))
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path, forType: .string)
        }
    }

    // MARK: Commit composer

    private var commitComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if repo.commitMessage.isEmpty {
                    Text("Commit message")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $repo.commitMessage)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1))
            )

            HStack {
                Toggle("Amend", isOn: Binding(
                    get: { repo.amend },
                    set: { on in Task { await repo.setAmend(on) } }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
                Menu {
                    Button("Commit & Push") { Task { await repo.commitAndPush() } }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)
                .disabled(!canCommit)
                Button {
                    Task { await repo.commit() }
                } label: {
                    Label(commitButtonTitle, systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!canCommit)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var commitButtonTitle: String {
        if let branch = repo.currentBranch?.name { return "Commit to \(branch)" }
        return "Commit"
    }

    private var canCommit: Bool {
        !repo.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!repo.status.staged.isEmpty || repo.amend)
    }

    private func sectionLabel<Trailing: View>(_ title: String, count: Int, tint: Color = .secondary,
                                              @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            Spacer()
            trailing()
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

// MARK: - Change file row

private struct ChangeFileRow: View {
    let entry: StatusEntry
    let staged: Bool
    let isSelected: Bool
    let isSkipWorktree: Bool
    let isAssumeUnchanged: Bool
    let onToggleStage: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(state: entry.primaryState)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(entry.fileName)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isSkipWorktree {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.stateModified)
                            .help("Local changes ignored (skip-worktree)")
                    }
                    if isAssumeUnchanged {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.stateModified)
                            .help("Assume-unchanged")
                    }
                }
                if !entry.directory.isEmpty {
                    Text(entry.directory)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if hovering || isSelected {
                Button(action: onToggleStage) {
                    Image(systemName: staged ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(staged ? Theme.stateDeleted : Theme.stateAdded)
                }
                .buttonStyle(.plain)
                .help(staged ? "Unstage" : "Stage")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : (hovering ? Theme.hoverFill : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Theme.selectionStroke : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

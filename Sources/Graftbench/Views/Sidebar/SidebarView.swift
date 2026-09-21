import SwiftUI

struct SidebarView: View {
    @Bindable var repo: RepositoryModel
    @State private var renameBranchTarget: Branch?
    @State private var stashDiffTarget: Stash?
    private let prefs = Preferences.shared

    var body: some View {
        List {
            Section("Workspace") {
                row(.workingCopy, title: "Local Changes",
                    systemImage: "pencil.and.list.clipboard", tint: Theme.accent,
                    badge: repo.status.totalChangeCount > 0 ? "\(repo.status.totalChangeCount)" : nil)
                row(.allBranches, title: "All Commits",
                    systemImage: "square.stack.3d.up", tint: .secondary)
            }

            Section("Branches") {
                ForEach(repo.localBranches) { branch in
                    branchRow(branch)
                }
            }

            ForEach(repo.remotes) { remote in
                let branches = repo.remoteBranches.filter { $0.remoteName == remote.name }
                if !branches.isEmpty {
                    Section(remote.name) {
                        ForEach(branches) { branch in
                            row(.remoteBranch(branch.name), title: branch.shortName,
                                systemImage: "arrow.triangle.branch", tint: Color(hex: 0x6C9CF0))
                            .contextMenu {
                                Button("Check Out as Local Branch") { Task { await repo.checkout(branch) } }
                                Button("Merge into current") { Task { await repo.merge(branch) } }
                                Button("Rebase current branch on top of this") { Task { await repo.rebaseOnto(branch) } }
                                Divider()
                                Button("Rename on Remote…") { renameBranchTarget = branch }
                                Button("Delete on Remote…", role: .destructive) {
                                    Task { await repo.deleteRemoteBranch(branch) }
                                }
                            }
                        }
                    }
                }
            }

            if !repo.tags.isEmpty {
                Section("Tags") {
                    ForEach(repo.tags) { tag in
                        row(.tag(tag.name), title: tag.name, systemImage: "tag.fill", tint: Theme.stateModified)
                            .contextMenu {
                                Button("Push Tag") { Task { await repo.pushTag(tag) } }
                                Divider()
                                Button("Delete…", role: .destructive) { Task { await repo.deleteTag(tag) } }
                                Button("Delete on Remote…", role: .destructive) { Task { await repo.deleteRemoteTag(tag) } }
                            }
                    }
                }
            }

            if !repo.stashes.isEmpty {
                Section("Stashes") {
                    ForEach(repo.stashes) { stash in
                        row(.stash(stash.selector), title: stash.message, systemImage: "tray.full", tint: .secondary)
                            .contextMenu {
                                Button("Show Diff…") { stashDiffTarget = stash }
                                Divider()
                                Button("Apply") { Task { await repo.stashApply(stash, pop: false) } }
                                Button("Pop") { Task { await repo.stashApply(stash, pop: true) } }
                                Button("Drop", role: .destructive) { Task { await repo.stashDrop(stash) } }
                            }
                    }
                }
            }

            if !repo.submodules.isEmpty {
                Section("Submodules") {
                    ForEach(repo.submodules) { submodule in
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(submoduleColor(submodule.state))
                                .frame(width: 17)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(submodule.name).font(.system(size: 12.5)).lineLimit(1)
                                if !submodule.describe.isEmpty {
                                    Text(submodule.describe).font(.system(size: 9.5))
                                        .foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .contextMenu {
                            Button("Update") { Task { await repo.updateSubmodules() } }
                            Button("Reveal in Finder") {
                                revealInFinder(repo.root.appendingPathComponent(submodule.path))
                            }
                        }
                    }
                }
            }

            if repo.worktrees.count > 1 {
                Section("Worktrees") {
                    ForEach(repo.worktrees) { worktree in
                        HStack(spacing: 8) {
                            Image(systemName: worktree.isMain ? "house" : "square.split.2x1")
                                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 17)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(worktree.branch ?? worktree.name).font(.system(size: 12.5)).lineLimit(1)
                                Text(worktree.path).font(.system(size: 9.5))
                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { revealInFinder(URL(fileURLWithPath: worktree.path)) }
                            if !worktree.isMain {
                                Button("Remove…", role: .destructive) { Task { await repo.removeWorktree(worktree) } }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(prefs.translucentWindow ? .hidden : .automatic)
        .environment(\.defaultMinListRowHeight, 28)
        .sheet(item: $renameBranchTarget) { branch in
            NamePrompt(title: branch.isRemote ? "Rename \(branch.name) on remote" : "Rename \(branch.name)",
                       placeholder: branch.isRemote ? branch.shortName : "new name",
                       actionTitle: "Rename") { name in
                renameBranchTarget = nil
                Task { await repo.rename(branch, to: name) }
            } onCancel: { renameBranchTarget = nil }
        }
        .sheet(item: $stashDiffTarget) { stash in
            StashDiffSheet(client: repo.client, selector: stash.selector, title: stash.message)
        }
    }

    // MARK: Rows

    private func row(_ target: SidebarItem, title: String, systemImage: String,
                     tint: Color, badge: String? = nil) -> some View {
        let selected = repo.sidebarSelection == target
        return Button {
            Task { await repo.select(target) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                    .frame(width: 17)
                Text(title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary.opacity(0.5)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground(selected))
    }

    private func branchRow(_ branch: Branch) -> some View {
        let target = SidebarItem.localBranch(branch.name)
        let selected = repo.sidebarSelection == target
        return Button {
            Task { await repo.select(target) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(branch.isCurrent ? Theme.accent : .secondary)
                    .frame(width: 17)
                Text(branch.name)
                    .font(.system(size: 12.5, weight: branch.isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if branch.isCurrent {
                    Circle().fill(Theme.stateAdded).frame(width: 5, height: 5)
                }
                Spacer(minLength: 4)
                SyncBadge(ahead: branch.ahead, behind: branch.behind)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground(selected))
        .contextMenu {
            let current = repo.currentBranch?.name ?? "current"
            if !branch.isCurrent {
                Button("Check Out") { Task { await repo.checkout(branch) } }
                Button("Merge into \(current)") { Task { await repo.merge(branch) } }
                Button("Squash Merge into \(current)") { Task { await repo.mergeSquash(branch) } }
                Button("Rebase \(current) on top of this") { Task { await repo.rebaseOnto(branch) } }
                Divider()
            }
            Button("Push") { Task { await repo.pushBranch(branch) } }
            if !repo.remoteBranches.isEmpty {
                Menu("Set Upstream") {
                    ForEach(repo.remoteBranches) { remoteBranch in
                        Button(remoteBranch.name) {
                            Task { await repo.setUpstream(branch, upstream: remoteBranch.name) }
                        }
                    }
                }
            }
            Button("Rename…") { renameBranchTarget = branch }
            Divider()
            Button("Delete…", role: .destructive) {
                Task { await repo.deleteBranch(branch, force: false) }
            }
            .disabled(branch.isCurrent)
        }
        .draggable("branch:\(branch.name)")
        .dropDestination(for: String.self) { items, _ in
            guard branch.isCurrent else { return false }
            handleDrop(items)
            return true
        }
    }

    /// Handle a commit or branch dropped onto the current branch.
    private func handleDrop(_ items: [String]) {
        guard let item = items.first else { return }
        if item.hasPrefix("branch:") {
            let name = String(item.dropFirst("branch:".count))
            if let dropped = repo.branches.first(where: { $0.name == name }), !dropped.isCurrent {
                Task { await repo.merge(dropped) }
            }
        } else if item.hasPrefix("commit:") {
            let sha = String(item.dropFirst("commit:".count))
            Task { await repo.cherryPick(sha: sha) }
        }
    }

    @ViewBuilder
    private func rowBackground(_ selected: Bool) -> some View {
        if selected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.selectionFill)
                .padding(.vertical, 1)
        } else {
            Color.clear
        }
    }

    private func submoduleColor(_ state: Submodule.State) -> Color {
        switch state {
        case .clean: return Theme.stateAdded
        case .modified: return Theme.stateModified
        case .notInitialized: return .secondary
        case .conflicts: return Theme.stateConflict
        }
    }
}

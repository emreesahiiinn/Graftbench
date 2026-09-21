import SwiftUI

struct RepositoryView: View {
    @Bindable var repo: RepositoryModel
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    @State private var sidebarVisible = true
    @State private var showPalette = false
    @State private var showDetachedPrompt = false
    @State private var showReflog = false
    @State private var showSearch = false
    @State private var showNewWorktree = false

    var body: some View {
        HSplitView {
            if sidebarVisible {
                SidebarView(repo: repo)
                    .frame(minWidth: 220, idealWidth: 264, maxWidth: 360)
            }
            detail
                .frame(minWidth: 480, maxWidth: .infinity)
        }
        .toolbar { toolbar }
        .overlay(alignment: .bottom) { statusOverlay }
        .overlay {
            if showPalette {
                CommandPalette(repo: repo, app: app, isPresented: $showPalette)
            }
        }
        .sheet(item: $repo.authChallenge) { challenge in
            CredentialSheet(host: challenge.host,
                            onSubmit: { user, secret in Task { await repo.submitCredentials(username: user, secret: secret) } },
                            onCancel: { repo.cancelAuth() })
        }
        .sheet(isPresented: $showReflog) { ReflogView(client: repo.client) }
        .sheet(isPresented: $showSearch) { GlobalSearchView(client: repo.client) }
        .sheet(isPresented: $showNewWorktree) { NewWorktreeSheet(repo: repo, isPresented: $showNewWorktree) }
        .task(id: repo.toast) {
            guard repo.toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            repo.toast = nil
        }
    }

    // MARK: Main area

    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if repo.isBisecting {
                bisectBanner
                Divider()
            }
            if repo.currentBranch == nil && !repo.commits.isEmpty {
                detachedBanner
                Divider()
            }
            detailBody
        }
        .sheet(isPresented: $showDetachedPrompt) {
            NamePrompt(title: "Create Branch at Current Commit",
                       placeholder: "branch name", actionTitle: "Create Branch") { name in
                showDetachedPrompt = false
                Task { await repo.createBranch(name: name, at: nil, checkout: true) }
            } onCancel: { showDetachedPrompt = false }
        }
    }

    private var bisectBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "target").foregroundStyle(Theme.accent)
            Text("Bisecting — is the checked-out commit good or bad?")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("Good") { Task { await repo.bisectGood() } }
                .tint(Theme.stateAdded)
            Button("Bad") { Task { await repo.bisectBad() } }
                .tint(Theme.stateDeleted)
            Button("Reset") { Task { await repo.bisectReset() } }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.accent.opacity(0.10))
    }

    private var detachedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.stateModified)
            Text("You are in 'detached HEAD' state — new commits won't belong to any branch.")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Button("Create Branch Here") { showDetachedPrompt = true }
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.stateModified.opacity(0.12))
    }

    @ViewBuilder
    private var detailBody: some View {
        if repo.sidebarSelection == .workingCopy {
            ChangesView(repo: repo)
        } else if repo.isDetailCollapsed {
            VStack(spacing: 0) {
                HistoryView(repo: repo)
                Divider()
                collapsedDetailBar
            }
        } else {
            VSplitView {
                HistoryView(repo: repo)
                    .frame(minHeight: 180, idealHeight: 360)
                CommitDetailView(repo: repo)
                    .frame(minHeight: 200)
            }
        }
    }

    private var collapsedDetailBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $repo.detailTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .onChange(of: repo.detailTab) { _, _ in repo.isDetailCollapsed = false }
            Spacer()
            Button {
                repo.isDetailCollapsed = false
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show detail panel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { sidebarVisible.toggle() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar")
            branchMenu
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if repo.isBusy { ProgressView().controlSize(.small) }

            TextField("Filter commits", text: $repo.historyFilter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)

            Button {
                showPalette = true
            } label: {
                Label("Quick Actions", systemImage: "command")
            }
            .keyboardShortcut("k", modifiers: .command)
            .help("Quick Actions (⌘K)")

            Menu {
                Button("Fetch All Remotes (prune)") { Task { await repo.fetch() } }
                if !repo.remotes.isEmpty {
                    Divider()
                    ForEach(repo.remotes) { remote in
                        Button("Fetch \(remote.name)") { Task { await repo.fetch(remote: remote.name) } }
                    }
                }
            } label: {
                Label("Fetch", systemImage: "arrow.down.circle")
            } primaryAction: {
                Task { await repo.fetch() }
            }
            .help("Fetch (▾ for options)")

            Menu {
                Button("Pull (Merge)") { Task { await repo.pull(rebase: false) } }
                Button("Pull with Rebase") { Task { await repo.pull(rebase: true) } }
                Divider()
                Button("Fetch All Remotes") { Task { await repo.fetch() } }
            } label: {
                Label(repo.currentBranch.map { $0.behind > 0 ? "Pull \($0.behind)" : "Pull" } ?? "Pull",
                      systemImage: "arrow.down.to.line")
            } primaryAction: {
                Task { await repo.pull() }
            }
            .help("Pull upstream changes (▾ for options)")

            Menu {
                Button("Push") { Task { await repo.push() } }
                Button("Push (Force with lease)") { Task { await repo.push(force: true) } }
                Divider()
                Button("Push All Tags") { Task { await repo.pushAllTags() } }
            } label: {
                Label(repo.currentBranch.map { $0.ahead > 0 ? "Push \($0.ahead)" : "Push" } ?? "Push",
                      systemImage: "arrow.up.to.line")
            } primaryAction: {
                Task { await repo.push() }
            }
            .help("Push (▾ for options)")

            stashMenu
            advancedMenu

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings (⌘,)")
        }
    }

    private var advancedMenu: some View {
        Menu {
            Button("Search in Files…") { showSearch = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Reflog…") { showReflog = true }
            Divider()
            Button("New Worktree…") { showNewWorktree = true }
            Divider()
            if repo.isBisecting {
                Button("Bisect: Reset") { Task { await repo.bisectReset() } }
            } else {
                Button("Bisect: Start") { Task { await repo.bisectStart() } }
            }
        } label: {
            Label("Advanced", systemImage: "wrench.and.screwdriver")
        }
        .help("Reflog, search, worktrees, bisect")
    }

    private var branchMenu: some View {
        Menu {
            Section("Local") {
                ForEach(repo.localBranches) { branch in
                    Button {
                        Task { await repo.checkout(branch) }
                    } label: {
                        Label(branch.name, systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch")
                    }
                }
            }
            if !repo.remoteBranches.isEmpty {
                Section("Remote") {
                    ForEach(repo.remoteBranches) { branch in
                        Button {
                            Task { await repo.checkout(branch) }
                        } label: {
                            Label(branch.name, systemImage: "cloud")
                        }
                    }
                }
            }
        } label: {
            Label(repo.currentBranch?.name ?? "detached", systemImage: "arrow.triangle.branch")
        }
        .help("Switch branch")
    }

    private var stashMenu: some View {
        Menu {
            Button {
                Task { await repo.stashPush(message: nil, includeUntracked: true) }
            } label: {
                Label("Stash All Changes", systemImage: "tray.and.arrow.down")
            }
            .disabled(repo.status.isClean)

            if !repo.stashes.isEmpty {
                Divider()
                ForEach(repo.stashes) { stash in
                    Menu(stash.message) {
                        Button("Apply") { Task { await repo.stashApply(stash, pop: false) } }
                        Button("Pop") { Task { await repo.stashApply(stash, pop: true) } }
                        Button("Drop", role: .destructive) { Task { await repo.stashDrop(stash) } }
                    }
                }
            }
        } label: {
            Label("Stash", systemImage: "tray.full")
        }
        .help("Stashes")
    }

    // MARK: Status overlay

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 8) {
            if let error = repo.lastError {
                banner(text: error, icon: "exclamationmark.triangle.fill", color: Theme.stateDeleted) {
                    repo.lastError = nil
                }
            }
            if let toast = repo.toast {
                banner(text: toast, icon: "checkmark.circle.fill", color: Theme.stateAdded,
                       undo: repo.undoable != nil ? { Task { await repo.undoLast() } } : nil,
                       dismiss: nil)
            }
        }
        .padding(.bottom, 16)
        .animation(.spring(duration: 0.3), value: repo.lastError)
        .animation(.spring(duration: 0.3), value: repo.toast)
    }

    private func banner(text: String, icon: String, color: Color,
                        undo: (() -> Void)? = nil, dismiss: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            if let undo {
                Button("Undo", action: undo)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            if let dismiss {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .frame(maxWidth: 460)
    }
}

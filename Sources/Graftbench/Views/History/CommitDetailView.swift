import SwiftUI

struct CommitDetailView: View {
    @Bindable var repo: RepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            content
        }
        .surface()
    }

    // MARK: Header (tabs + collapse)

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Picker("", selection: $repo.detailTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            if let commit = repo.selectedCommit {
                Text(commit.shortSHA)
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                repo.isDetailCollapsed = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide detail panel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if repo.selectedCommit != nil {
            switch repo.detailTab {
            case .commit:
                HSplitView {
                    VStack(spacing: 0) {
                        if let commit = repo.selectedCommit {
                            CommitMessagePanel(commit: commit)
                        }
                        Divider()
                        fileListPane
                    }
                    .frame(minWidth: 260, idealWidth: 340, maxWidth: 520)
                    diffPane.frame(minWidth: 320)
                }
            case .changes:
                HSplitView {
                    fileListPane.frame(minWidth: 240, idealWidth: 320, maxWidth: 520)
                    diffPane.frame(minWidth: 340)
                }
            case .fileTree:
                HSplitView {
                    FileTreeView(diffs: repo.commitDiffs, selectedID: $repo.selectedCommitFileID)
                        .frame(minWidth: 240, idealWidth: 320, maxWidth: 520)
                    diffPane.frame(minWidth: 340)
                }
            }
        } else {
            EmptyStateView(icon: "circle.dashed",
                           title: "Select a commit",
                           subtitle: "Choose a commit to see its message and changes.")
        }
    }

    private var fileListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(repo.commitDiffs.count) \(repo.commitDiffs.count == 1 ? "File" : "Files")")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("+\(totalAdded)").foregroundStyle(Theme.stateAdded)
                Text("−\(totalRemoved)").foregroundStyle(Theme.stateDeleted)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(repo.commitDiffs) { diff in
                        DiffFileRow(diff: diff, isSelected: repo.selectedCommitFileID == diff.id)
                            .contentShape(Rectangle())
                            .onTapGesture { repo.selectedCommitFileID = diff.id }
                    }
                }
                .padding(6)
            }
        }
        .surface()
    }

    @ViewBuilder
    private var diffPane: some View {
        if let id = repo.selectedCommitFileID,
           let diff = repo.commitDiffs.first(where: { $0.id == id }) {
            if ImageDiffView.isImage(diff.displayPath) {
                ImageDiffView(client: repo.client,
                              oldRef: repo.selectedCommit?.parents.first, oldPath: diff.oldPath,
                              newRef: repo.selectedCommitID, newPath: diff.newPath)
            } else {
                DiffView(diff: diff, onReload: { Task { await repo.reloadCurrentDiff() } })
            }
        } else if repo.commitDiffs.isEmpty {
            EmptyStateView(icon: "doc", title: "No file changes")
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass", title: "Select a file")
        }
    }

    private var totalAdded: Int { repo.commitDiffs.reduce(0) { $0 + $1.addedLines } }
    private var totalRemoved: Int { repo.commitDiffs.reduce(0) { $0 + $1.removedLines } }
}

// MARK: - Commit message panel

private struct CommitMessagePanel: View {
    let commit: Commit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(commit.subject)
                    .font(.system(size: 14, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !commit.body.isEmpty {
                    Text(commit.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    AuthorAvatar(name: commit.authorName, email: commit.authorEmail, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(commit.authorName).font(.system(size: 11.5, weight: .medium))
                        Text(commit.authorEmail).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(RelativeDate.full(commit.commitDate))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                if commit.isMerge || !commit.refs.isEmpty {
                    HStack(spacing: 6) {
                        if commit.isMerge {
                            Label("Merge", systemImage: "arrow.triangle.merge")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(.quaternary.opacity(0.4)))
                        }
                        ForEach(commit.refs) { ref in RefPill(ref: ref) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - File row

struct DiffFileRow: View {
    let diff: FileDiff
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(state: diff.primaryState)
            VStack(alignment: .leading, spacing: 0) {
                Text((diff.displayPath as NSString).lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                let dir = (diff.displayPath as NSString).deletingLastPathComponent
                if !dir.isEmpty {
                    Text(dir)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if !diff.isBinary {
                Text("+\(diff.addedLines)").foregroundStyle(Theme.stateAdded)
                Text("−\(diff.removedLines)").foregroundStyle(Theme.stateDeleted)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Theme.selectionFill : .clear)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Theme.selectionStroke : .clear, lineWidth: 1))
        )
    }
}

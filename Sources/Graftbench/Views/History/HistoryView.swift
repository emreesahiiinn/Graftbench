import SwiftUI
import AppKit

/// The commit-history table (top pane of the history layout).
struct HistoryView: View {
    @Bindable var repo: RepositoryModel
    @State private var branchPromptCommit: Commit?
    @State private var tagPromptCommit: Commit?
    @State private var rebaseBaseCommit: Commit?
    @State private var comparePair: ComparePair?

    private let rowHeight: CGFloat = 30
    private var commits: [Commit] { repo.visibleCommits }

    var body: some View {
        VStack(spacing: 0) {
            if commits.isEmpty {
                EmptyStateView(icon: repo.isFiltering ? "magnifyingglass" : "clock",
                               title: repo.isFiltering ? "No matching commits" : "No commits",
                               subtitle: repo.isFiltering ? "Try a different search." : "This branch has no history yet.")
            } else {
                list
            }
        }
        .surface()
        .sheet(item: $branchPromptCommit) { commit in
            NamePrompt(title: "New Branch at \(commit.shortSHA)",
                       placeholder: "branch name", actionTitle: "Create Branch") { name in
                branchPromptCommit = nil
                Task { await repo.createBranch(name: name, at: commit, checkout: true) }
            } onCancel: { branchPromptCommit = nil }
        }
        .sheet(item: $tagPromptCommit) { commit in
            NamePrompt(title: "New Tag at \(commit.shortSHA)",
                       placeholder: "tag name", actionTitle: "Create Tag") { name in
                tagPromptCommit = nil
                Task { await repo.createTag(name: name, message: nil, at: commit) }
            } onCancel: { tagPromptCommit = nil }
        }
        .sheet(item: $rebaseBaseCommit) { commit in
            InteractiveRebaseView(repo: repo, base: commit)
        }
        .sheet(item: $comparePair) { pair in
            CompareView(client: repo.client, pair: pair)
        }
    }

    private var list: some View {
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                        let graphRow = (!repo.isFiltering && index < repo.graph.rows.count) ? repo.graph.rows[index] : nil
                        CommitRow(
                            commit: commit,
                            graphRow: graphRow,
                            laneCount: repo.graph.laneCount,
                            rowHeight: rowHeight,
                            isSelected: repo.selectedCommitID == commit.id
                        )
                        .id(commit.id)
                        .contentShape(Rectangle())
                        .onTapGesture { Task { await repo.selectCommit(commit.id) } }
                        .contextMenu { commitContextMenu(commit) }
                        .draggable("commit:\(commit.id)")
                    }

                    if !repo.isFiltering && repo.canLoadMoreHistory {
                        Button {
                            Task { await repo.loadMoreHistory() }
                        } label: {
                            Text("Load More")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func commitContextMenu(_ commit: Commit) -> some View {
        Button("Check Out") { Task { await repo.checkoutCommit(commit) } }
        Divider()
        Button("Create Branch Here…") { branchPromptCommit = commit }
        Button("Create Tag Here…") { tagPromptCommit = commit }
        Divider()
        Button("Cherry-Pick") { Task { await repo.cherryPick(commit) } }
        Button("Revert") { Task { await repo.revertCommit(commit) } }
        Button("Interactive Rebase from Here…") { rebaseBaseCommit = commit }
        Divider()
        Button("Mark for Compare") { repo.compareMarked = commit.id }
        if let marked = repo.compareMarked, marked != commit.id {
            Button("Compare \(String(marked.prefix(7))) ↔ this") {
                comparePair = ComparePair(a: marked, b: commit.id)
            }
        }
        Menu("Reset \(repo.currentBranch?.name ?? "Branch") to Here") {
            Button("Soft — keep changes staged") { Task { await repo.reset(to: commit, mode: "soft") } }
            Button("Mixed — keep changes unstaged") { Task { await repo.reset(to: commit, mode: "mixed") } }
            Button("Hard — discard changes", role: .destructive) { Task { await repo.reset(to: commit, mode: "hard") } }
        }
        Divider()
        Button("Copy SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
        Button("Copy Short SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.shortSHA, forType: .string)
        }
    }
}

// MARK: - Commit row (Fork-style columns)

private struct CommitRow: View {
    let commit: Commit
    let graphRow: GraphRow?
    let laneCount: Int
    let rowHeight: CGFloat
    let isSelected: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            if let graphRow {
                GraphRowCanvas(row: graphRow, laneCount: laneCount, isMerge: commit.isMerge)
                    .frame(width: max(CGFloat(laneCount) * Theme.laneWidth, Theme.laneWidth), height: rowHeight)
                    .padding(.leading, 6)
            } else {
                Color.clear.frame(width: 6, height: rowHeight)
            }

            // Message column (flexible)
            HStack(spacing: 5) {
                ForEach(commit.refs.prefix(3)) { ref in
                    RefPill(ref: ref)
                }
                Text(commit.subject)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)

            // Author column
            HStack(spacing: 5) {
                AuthorAvatar(name: commit.authorName, email: commit.authorEmail, size: 16)
                Text(commit.authorName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 150, alignment: .leading)

            // SHA column
            Text(commit.shortSHA)
                .font(Theme.monoSmall)
                .foregroundStyle(Color.secondary.opacity(0.8))
                .frame(width: 66, alignment: .leading)

            // Date column
            Text(RelativeDate.relative(commit.commitDate))
                .font(.system(size: 10.5))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .frame(width: 92, alignment: .trailing)
                .help(RelativeDate.full(commit.commitDate))
        }
        .frame(height: rowHeight)
        .padding(.horizontal, 8)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Theme.selectionFill : (hovering ? Theme.hoverFill : .clear))
                if isSelected {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 2.5)
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Graph canvas

struct GraphRowCanvas: View {
    let row: GraphRow
    let laneCount: Int
    let isMerge: Bool

    private let radius: CGFloat = 4.5

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2

            func columnX(_ column: Int) -> CGFloat {
                Theme.laneWidth / 2 + CGFloat(column) * Theme.laneWidth
            }

            for edge in row.edges {
                let color = Theme.laneColor(edge.colorIndex)
                let path: Path
                switch edge.kind {
                case .passThrough:
                    path = edgePath(from: CGPoint(x: columnX(edge.fromColumn), y: 0),
                                    to: CGPoint(x: columnX(edge.toColumn), y: size.height))
                case .mergeIntoNode:
                    path = edgePath(from: CGPoint(x: columnX(edge.fromColumn), y: 0),
                                    to: CGPoint(x: columnX(edge.toColumn), y: midY))
                case .forkFromNode:
                    path = edgePath(from: CGPoint(x: columnX(edge.fromColumn), y: midY),
                                    to: CGPoint(x: columnX(edge.toColumn), y: size.height))
                }
                context.stroke(path, with: .color(color.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }

            let center = CGPoint(x: columnX(row.column), y: midY)
            let nodeColor = Theme.laneColor(row.colorIndex)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let halo = rect.insetBy(dx: -2, dy: -2)
            context.fill(Circle().path(in: halo), with: .color(Color(nsColor: .windowBackgroundColor)))
            if isMerge {
                context.stroke(Circle().path(in: rect), with: .color(nodeColor), lineWidth: 2.2)
            } else {
                context.fill(Circle().path(in: rect), with: .color(nodeColor))
                context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.85)), lineWidth: 1)
            }
        }
    }

    private func edgePath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        if abs(from.x - to.x) < 0.5 {
            path.addLine(to: to)
        } else {
            let midY = (from.y + to.y) / 2
            path.addCurve(to: to,
                          control1: CGPoint(x: from.x, y: midY),
                          control2: CGPoint(x: to.x, y: midY))
        }
        return path
    }
}

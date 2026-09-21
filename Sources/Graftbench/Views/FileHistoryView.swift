import SwiftUI

/// A commit-by-commit history of a single file, with the file's diff per commit.
struct FileHistoryView: View {
    let client: GitClient
    let path: String
    @Environment(\.dismiss) private var dismiss

    @State private var commits: [Commit] = []
    @State private var selected: String?
    @State private var diff: FileDiff?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent)
                Text("History · \((path as NSString).lastPathComponent)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                EmptyStateView(icon: "clock", title: "No history for this file")
            } else {
                HSplitView {
                    list.frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
                    diffPane.frame(minWidth: 380)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { await load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(commits) { commit in
                    Button {
                        Task { await select(commit) }
                    } label: {
                        HStack(spacing: 8) {
                            AuthorAvatar(name: commit.authorName, email: commit.authorEmail, size: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(commit.subject).font(.system(size: 12)).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(commit.shortSHA).font(Theme.monoSmall).foregroundStyle(.tertiary)
                                    Text(RelativeDate.relative(commit.commitDate))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected == commit.id ? Theme.selectionFill : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var diffPane: some View {
        if let diff {
            DiffView(diff: diff)
        } else {
            EmptyStateView(icon: "doc.text.magnifyingglass", title: "Select a commit")
        }
    }

    private func load() async {
        commits = (try? await client.fileHistory(path: path, limit: 200)) ?? []
        loading = false
        if let first = commits.first { await select(first) }
    }

    private func select(_ commit: Commit) async {
        selected = commit.id
        diff = try? await client.fileDiffAt(sha: commit.id, path: path)
    }
}

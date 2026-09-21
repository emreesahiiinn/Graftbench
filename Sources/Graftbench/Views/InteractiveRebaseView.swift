import SwiftUI

enum RebaseAction: String, CaseIterable, Identifiable {
    case pick, reword, squash, fixup, drop
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .pick: return Theme.stateAdded
        case .reword: return Theme.accent
        case .squash: return Theme.stateModified
        case .fixup: return Theme.stateRenamed
        case .drop: return Theme.stateDeleted
        }
    }
}

struct RebaseItem: Identifiable {
    let id = UUID()
    let commit: Commit
    var action: RebaseAction
    var newMessage: String
}

/// Interactive rebase: reorder (drag), and set pick/squash/fixup/drop per commit.
struct InteractiveRebaseView: View {
    @Bindable var repo: RepositoryModel
    let base: Commit
    @Environment(\.dismiss) private var dismiss

    @State private var items: [RebaseItem] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.accent)
                Text("Interactive Rebase onto \(base.shortSHA)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                EmptyStateView(icon: "arrow.triangle.branch", title: "No commits to rebase")
            } else {
                List {
                    ForEach($items) { $item in
                        RebaseRow(item: $item)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("Drag to reorder · top = oldest")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start Rebase") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(items.isEmpty)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(minWidth: 700, minHeight: 480)
        .task { await load() }
    }

    private func load() async {
        let commits = await repo.commitsToRebase(base: base.id)
        // log is newest-first; a rebase todo lists oldest-first.
        items = commits.reversed().map { RebaseItem(commit: $0, action: .pick, newMessage: $0.subject) }
        loading = false
    }

    private func start() {
        var lines: [String] = []
        for item in items {
            lines.append("\(item.action.rawValue) \(item.commit.id) \(item.commit.subject)")
        }
        let todo = lines.joined(separator: "\n") + "\n"

        // Reword messages are only queued when there are no squashes (squash also
        // invokes the message editor, which would desync the queue).
        let hasSquash = items.contains { $0.action == .squash }
        let rewordMessages = items.filter { $0.action == .reword }.map(\.newMessage)
        let messages = (!hasSquash && !rewordMessages.isEmpty) ? rewordMessages : []

        dismiss()
        Task { await repo.runInteractiveRebase(base: base.id, todo: todo, messages: messages) }
    }
}

private struct RebaseRow: View {
    @Binding var item: RebaseItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Picker("", selection: $item.action) {
                    ForEach(RebaseAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 100)

                Circle().fill(item.action.color).frame(width: 6, height: 6)

                Text(item.commit.shortSHA)
                    .font(Theme.monoSmall)
                    .foregroundStyle(.secondary)

                Text(item.commit.subject)
                    .font(.system(size: 12))
                    .foregroundStyle(item.action == .drop ? .tertiary : .primary)
                    .strikethrough(item.action == .drop)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if item.action == .reword {
                TextField("New commit message", text: $item.newMessage)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 2)
    }
}

import SwiftUI

struct QuickCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let action: () -> Void
}

/// Tower/Sublime-style command palette (⌘K).
struct CommandPalette: View {
    @Bindable var repo: RepositoryModel
    let app: AppModel
    @Binding var isPresented: Bool

    @State private var query = ""
    @FocusState private var focused: Bool

    private var filtered: [QuickCommand] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || ($0.subtitle?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "command").foregroundStyle(.secondary)
                    TextField("Type a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focused)
                        .onSubmit { runFirst() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { command in
                            CommandRow(command: command) {
                                command.action()
                                isPresented = false
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 540)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onExitCommand { isPresented = false }
    }

    private func runFirst() {
        if let first = filtered.first {
            first.action()
            isPresented = false
        }
    }

    private var commands: [QuickCommand] {
        var list: [QuickCommand] = [
            QuickCommand(title: "Fetch", subtitle: "All remotes", icon: "arrow.down.circle") {
                Task { await repo.fetch() }
            },
            QuickCommand(title: "Pull", subtitle: "Merge", icon: "arrow.down.to.line") {
                Task { await repo.pull(rebase: false) }
            },
            QuickCommand(title: "Pull with Rebase", subtitle: nil, icon: "arrow.down.to.line") {
                Task { await repo.pull(rebase: true) }
            },
            QuickCommand(title: "Push", subtitle: nil, icon: "arrow.up.to.line") {
                Task { await repo.push() }
            },
            QuickCommand(title: "Stash All Changes", subtitle: nil, icon: "tray.and.arrow.down") {
                Task { await repo.stashPush(message: nil, includeUntracked: true) }
            },
            QuickCommand(title: "Local Changes", subtitle: "Working copy", icon: "pencil.and.list.clipboard") {
                Task { await repo.select(.workingCopy) }
            },
            QuickCommand(title: "All Commits", subtitle: "History", icon: "square.stack.3d.up") {
                Task { await repo.select(.allBranches) }
            },
            QuickCommand(title: "Open Repository…", subtitle: nil, icon: "folder") {
                if let url = chooseRepositoryFolder() { Task { await app.openRepository(at: url) } }
            }
        ]
        for branch in repo.localBranches where !branch.isCurrent {
            list.append(QuickCommand(title: "Checkout \(branch.name)", subtitle: "Local branch", icon: "arrow.triangle.branch") {
                Task { await repo.checkout(branch) }
            })
            list.append(QuickCommand(title: "Merge \(branch.name) into current", subtitle: nil, icon: "arrow.triangle.merge") {
                Task { await repo.merge(branch) }
            })
        }
        for branch in repo.remoteBranches {
            list.append(QuickCommand(title: "Checkout \(branch.name)", subtitle: "Remote branch", icon: "cloud") {
                Task { await repo.checkout(branch) }
            })
        }
        return list
    }
}

private struct CommandRow: View {
    let command: QuickCommand
    let run: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                Image(systemName: command.icon)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title).font(.system(size: 13))
                    if let subtitle = command.subtitle {
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Theme.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

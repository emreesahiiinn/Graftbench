import SwiftUI

struct NewWorktreeSheet: View {
    @Bindable var repo: RepositoryModel
    @Binding var isPresented: Bool

    @State private var parentDir: URL?
    @State private var name = ""
    @State private var branch = ""

    private var canCreate: Bool { parentDir != nil && !name.isEmpty && !branch.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Worktree").font(.headline)
            Text("Check out a branch into a separate working directory.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            HStack {
                Text(parentDir?.path ?? "Choose a parent folder…")
                    .font(.system(size: 11)).foregroundStyle(parentDir == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { if let dir = chooseRepositoryFolder() { parentDir = dir } }
            }
            TextField("Folder name", text: $name).textFieldStyle(.roundedBorder)

            Picker("Branch", selection: $branch) {
                Text("Select…").tag("")
                ForEach(repo.localBranches) { Text($0.name).tag($0.name) }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let parent = parentDir else { return }
                    let path = parent.appendingPathComponent(name).path
                    let branchName = branch
                    isPresented = false
                    Task { await repo.addWorktree(path: path, branch: branchName) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

import SwiftUI

struct CloneSheet: View {
    let app: AppModel
    @Binding var isPresented: Bool

    @State private var url = ""
    @State private var name = ""
    @State private var parentDir: URL?
    @State private var cloning = false

    private var canClone: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty && parentDir != nil && !name.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clone Repository").font(.headline)

            TextField("Remote URL (https://… or git@…)", text: $url)
                .textFieldStyle(.roundedBorder)
                .onChange(of: url) { _, value in
                    if name.isEmpty { name = Self.deriveName(from: value) }
                }

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(parentDir?.path ?? "Choose a destination folder…")
                    .font(.system(size: 11))
                    .foregroundStyle(parentDir == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    if let dir = chooseRepositoryFolder() { parentDir = dir }
                }
            }

            if cloning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cloning…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Clone") { clone() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(!canClone || cloning)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func clone() {
        guard let parentDir else { return }
        cloning = true
        let cloneURL = url.trimmingCharacters(in: .whitespaces)
        let folderName = name
        Task {
            await app.cloneRepository(url: cloneURL, into: parentDir, name: folderName)
            cloning = false
            isPresented = false
        }
    }

    static func deriveName(from url: String) -> String {
        var last = url.split(separator: "/").last.map(String.init) ?? ""
        if last.hasSuffix(".git") { last = String(last.dropLast(4)) }
        // Handle scp-like git@host:group/repo
        if last.contains(":") { last = last.split(separator: ":").last.map(String.init) ?? last }
        return last
    }
}

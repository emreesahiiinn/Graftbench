import SwiftUI

struct GlobalSearchView: View {
    let client: GitClient
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [GrepMatch] = []
    @State private var searching = false
    @State private var searched = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search in tracked files…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit(run)
                if searching { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
            Divider()

            if searched && results.isEmpty && !searching {
                EmptyStateView(icon: "magnifyingglass", title: "No matches")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(results) { match in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text((match.path as NSString).lastPathComponent)
                                        .font(.system(size: 11, weight: .medium))
                                    Text("\(match.path):\(match.line)")
                                        .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Text(match.text.trimmingCharacters(in: .whitespaces))
                                    .font(Theme.monoSmall).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear { focused = true }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            results = (try? await client.grep(q)) ?? []
            searching = false
            searched = true
        }
    }
}

import SwiftUI

struct StashDiffSheet: View {
    let client: GitClient
    let selector: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var diffs: [FileDiff] = []
    @State private var selectedID: FileDiff.ID?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full").foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffs.isEmpty {
                EmptyStateView(icon: "tray", title: "Empty stash")
            } else {
                HSplitView {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(diffs) { diff in
                                DiffFileRow(diff: diff, isSelected: selectedID == diff.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedID = diff.id }
                            }
                        }
                        .padding(6)
                    }
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 480)

                    if let id = selectedID, let diff = diffs.first(where: { $0.id == id }) {
                        DiffView(diff: diff).frame(minWidth: 380)
                    } else {
                        EmptyStateView(icon: "doc.text.magnifyingglass", title: "Select a file")
                            .frame(minWidth: 380)
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .task {
            diffs = (try? await client.stashDiff(selector: selector)) ?? []
            selectedID = diffs.first?.id
            loading = false
        }
    }
}

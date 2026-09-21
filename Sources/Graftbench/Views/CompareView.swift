import SwiftUI

struct ComparePair: Identifiable {
    let id = UUID()
    let a: String
    let b: String
}

struct CompareView: View {
    let client: GitClient
    let pair: ComparePair
    @Environment(\.dismiss) private var dismiss

    @State private var diffs: [FileDiff] = []
    @State private var selectedID: FileDiff.ID?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(Theme.accent)
                Text("Compare \(String(pair.a.prefix(7))) ↔ \(String(pair.b.prefix(7)))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if diffs.isEmpty {
                EmptyStateView(icon: "equal.circle", title: "No differences")
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
        .frame(minWidth: 840, minHeight: 540)
        .task {
            diffs = (try? await client.diffBetween(pair.a, pair.b,
                                                   ignoreWhitespace: Preferences.shared.ignoreWhitespaceInDiff)) ?? []
            selectedID = diffs.first?.id
            loading = false
        }
    }
}

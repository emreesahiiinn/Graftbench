import SwiftUI

/// Line-by-line authorship (`git blame`) for a file.
struct BlameView: View {
    let client: GitClient
    let path: String
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [BlameLine] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle").foregroundStyle(Theme.accent)
                Text("Blame · \((path as NSString).lastPathComponent)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                EmptyStateView(icon: "person.text.rectangle", title: "No blame data")
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            BlameRow(line: line)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .task {
            lines = (try? await client.blame(path: path)) ?? []
            loading = false
        }
    }
}

private struct BlameRow: View {
    let line: BlameLine

    private var authorColor: Color {
        let palette = Theme.laneColors
        return palette[abs(line.sha.hashValue) % palette.count]
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(line.author)
                .font(.system(size: 10))
                .foregroundStyle(authorColor)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
                .padding(.leading, 8)
            Text(line.shortSHA)
                .font(Theme.monoSmall)
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)
            Text("\(line.lineNumber)")
                .font(Theme.monoSmall)
                .foregroundStyle(Theme.diffGutter)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 8)
            Text(line.content.isEmpty ? " " : line.content)
                .font(Theme.mono)
                .foregroundStyle(.primary.opacity(0.9))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .fixedSize(horizontal: true, vertical: false)
    }
}

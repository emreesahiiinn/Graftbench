import SwiftUI

struct ReflogView: View {
    let client: GitClient
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [ReflogEntry] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.2.circlepath").foregroundStyle(Theme.accent)
                Text("Reflog").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).background(.bar)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(entries) { entry in
                            HStack(spacing: 10) {
                                Text(entry.selector)
                                    .font(Theme.monoSmall).foregroundStyle(Theme.accent)
                                    .frame(width: 92, alignment: .leading)
                                Text(entry.shortSHA).font(Theme.monoSmall).foregroundStyle(.secondary)
                                Text(entry.subject).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 6)
                                if let date = entry.date {
                                    Text(RelativeDate.relative(date)).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .contextMenu {
                                Button("Copy SHA") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.shortSHA, forType: .string)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            entries = (try? await client.reflog(limit: 300)) ?? []
            loading = false
        }
    }
}

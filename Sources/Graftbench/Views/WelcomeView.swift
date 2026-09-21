import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings
    private var prefs = Preferences.shared
    @State private var showClone = false

    var body: some View {
        HStack(spacing: 0) {
            hero
            Divider()
            recents
        }
        .surface()
        .sheet(isPresented: $showClone) {
            CloneSheet(app: app, isPresented: $showClone)
        }
        .sheet(item: Binding(get: { app.cloneAuthChallenge }, set: { app.cloneAuthChallenge = $0 })) { challenge in
            CredentialSheet(host: challenge.host,
                            onSubmit: { user, secret in Task { await app.submitCloneCredentials(username: user, secret: secret) } },
                            onCancel: { app.cancelCloneAuth() })
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Graftbench")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("A faster, sharper Git client for macOS")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if let url = chooseRepositoryFolder() {
                        Task { await app.openRepository(at: url) }
                    }
                } label: {
                    Label("Open Repository…", systemImage: "folder")
                        .frame(maxWidth: 260, alignment: .leading)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button {
                    showClone = true
                } label: {
                    Label("Clone from URL…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: 260, alignment: .leading)
                }
                .controlSize(.large)
                .help("Clone a remote repository")

                Button {
                    openSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                        .frame(maxWidth: 260, alignment: .leading)
                }
                .controlSize(.large)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Appearance, accent color, translucency and more (⌘,)")
            }

            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop a folder here, or press ⌘O")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Text("Created by Emre Şahin ✨")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(40)
        .frame(width: 420, alignment: .leading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)

            if prefs.recentRepositories.isEmpty {
                EmptyStateView(icon: "clock",
                               title: "No recent repositories",
                               subtitle: "Repositories you open will appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(prefs.recentRepositories) { recent in
                            RecentRow(recent: recent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.15))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in await app.openRepository(at: url) }
        }
        return true
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var app
    let recent: RecentRepository
    @State private var hovering = false

    var body: some View {
        Button {
            Task { await app.openRepository(at: recent.url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(recent.exists ? Theme.accent : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(recent.exists ? .primary : .secondary)
                    Text(recent.path)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if hovering {
                    Button {
                        Preferences.shared.removeRecent(recent)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

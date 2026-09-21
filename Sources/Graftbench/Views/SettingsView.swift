import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            IdentitySettings()
                .tabItem { Label("Identity", systemImage: "person.crop.circle") }
            RemotesSettings()
                .tabItem { Label("Remotes", systemImage: "cloud") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 400)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            BrandMark(size: 64)
            Text("Graftbench").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("A faster, sharper Git client for macOS")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Version 0.1.0").font(.system(size: 11)).foregroundStyle(.tertiary)
            Divider().frame(width: 220).padding(.vertical, 4)
            Text("Created by Emre Şahin ✨")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            Text("Free for noncommercial use — PolyForm Noncommercial 1.0.0.\nCommercial use requires a license from the author.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Link("github.com/emreesahiiinn/Graftbench",
                 destination: URL(string: "https://github.com/emreesahiiinn/Graftbench")!)
                .font(.system(size: 11))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct GeneralSettings: View {
    private let prefs = Preferences.shared
    @State private var gitPath = Preferences.shared.gitExecutablePath ?? ""

    var body: some View {
        Form {
            Picker("Appearance", selection: Binding(
                get: { prefs.appearance }, set: { prefs.setAppearance($0) })) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Accent color") {
                HStack(spacing: 6) {
                    ForEach(AccentTheme.allCases) { theme in
                        Button { prefs.setAccentTheme(theme) } label: {
                            Circle().fill(theme.color).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.primary.opacity(prefs.accentTheme == theme ? 0.85 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain).help(theme.title)
                    }
                }
            }
            Toggle("Translucent window", isOn: Binding(
                get: { prefs.translucentWindow }, set: { prefs.setTranslucentWindow($0) }))
            Toggle("Pull with rebase by default", isOn: Binding(
                get: { prefs.useRebaseOnPull }, set: { prefs.setUseRebaseOnPull($0) }))
            Toggle("Ignore whitespace in diffs", isOn: Binding(
                get: { prefs.ignoreWhitespaceInDiff }, set: { prefs.setIgnoreWhitespaceInDiff($0) }))
            Toggle("Sign commits (GPG/SSH)", isOn: Binding(
                get: { prefs.signCommits }, set: { prefs.setSignCommits($0) }))

            Section("Git executable") {
                TextField("Path (optional)", text: $gitPath)
                Text("Leave empty to auto-detect (Homebrew or /usr/bin/git).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Apply") {
                    prefs.setGitExecutablePath(gitPath.isEmpty ? nil : gitPath)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct IdentitySettings: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var email = ""
    @State private var global = true
    @State private var loaded = false

    var body: some View {
        Form {
            if let repo = app.selectedRepository {
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                Toggle("Apply globally (all repositories)", isOn: $global)
                Button("Save") {
                    Task { await repo.setGitIdentity(name: name, email: email, global: global) }
                }
                .disabled(name.isEmpty || email.isEmpty)
            } else {
                Text("Open a repository to edit its identity.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            guard let repo = app.selectedRepository, !loaded else { return }
            let identity = await repo.gitIdentity()
            name = identity.name
            email = identity.email
            loaded = true
        }
    }
}

private struct RemotesSettings: View {
    @Environment(AppModel.self) private var app
    @State private var newName = ""
    @State private var newURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let repo = app.selectedRepository {
                List {
                    ForEach(repo.remotes) { remote in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(remote.name).font(.system(size: 12, weight: .semibold))
                                Text(remote.fetchURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await repo.removeRemote(remote) }
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    TextField("name", text: $newName).frame(width: 110)
                    TextField("https://… or git@…", text: $newURL)
                    Button("Add") {
                        Task {
                            await repo.addRemote(name: newName, url: newURL)
                            newName = ""; newURL = ""
                        }
                    }
                    .disabled(newName.isEmpty || newURL.isEmpty)
                }
            } else {
                Text("Open a repository to manage its remotes.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

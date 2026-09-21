import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    private let prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            RepoTabBar()
            Divider().opacity(0.6)
            content
                .id(prefs.accentTheme)
        }
        .background {
            if prefs.translucentWindow {
                VisualEffectBackground().ignoresSafeArea()
            }
        }
        .background(WindowConfigurator(translucent: prefs.translucentWindow))
        .preferredColorScheme(prefs.appearance.colorScheme)
        .task { await app.performStartupOpen() }
        .alert("Couldn't open repository",
               isPresented: Binding(get: { app.openError != nil },
                                    set: { if !$0 { app.openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.openError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.showingHome {
            WelcomeView()
        } else if let repo = app.selectedRepository {
            RepositoryView(repo: repo)
        } else {
            WelcomeView()
        }
    }
}

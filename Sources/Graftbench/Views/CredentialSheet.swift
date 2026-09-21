import SwiftUI

/// Prompts for HTTPS credentials, then hands them back to be stored in the macOS
/// Keychain (via git's credential helper) and the operation retried.
struct CredentialSheet: View {
    let host: String
    let onSubmit: (_ username: String, _ secret: String) -> Void
    let onCancel: () -> Void

    @State private var username = ""
    @State private var secret = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
                Text("Sign in to \(host)").font(.headline)
            }
            Text("Enter your username and a personal access token (recommended) or password. It's stored securely in your macOS Keychain and reused automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            SecureField("Password / Token", text: $secret)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Sign In", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(username.isEmpty || secret.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !username.isEmpty, !secret.isEmpty else { return }
        onSubmit(username, secret)
    }
}

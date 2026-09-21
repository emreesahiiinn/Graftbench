import Foundation
import Observation

/// Top-level application state: the set of open repositories and the active one.
@MainActor
@Observable
final class AppModel {
    var repositories: [RepositoryModel] = []
    var selectedRepositoryID: RepositoryModel.ID?
    var isHomeSelected = false
    var openError: String?
    var cloneAuthChallenge: AuthChallenge?

    @ObservationIgnored private var cloneRetry: (() async -> Void)?

    var selectedRepository: RepositoryModel? {
        guard let id = selectedRepositoryID else { return repositories.first }
        return repositories.first { $0.id == id } ?? repositories.first
    }

    /// Whether the Home screen should be shown instead of a repository.
    var showingHome: Bool {
        isHomeSelected || repositories.isEmpty
    }

    func showHome() {
        isHomeSelected = true
    }

    func selectRepository(_ repo: RepositoryModel) {
        selectedRepositoryID = repo.id
        isHomeSelected = false
    }

    func openRepository(at url: URL) async {
        do {
            let root = try await GitClient.discover(at: url)
            if let existing = repositories.first(where: { $0.root == root }) {
                selectedRepositoryID = existing.id
                isHomeSelected = false
                return
            }
            let repo = RepositoryModel(root: root)
            repositories.append(repo)
            selectedRepositoryID = repo.id
            isHomeSelected = false
            Preferences.shared.noteOpened(url: root, name: repo.name)
            await repo.initialLoad()
        } catch {
            openError = (error as? GitError)?.shortMessage ?? error.localizedDescription
        }
    }

    func cloneRepository(url: String, into parentDir: URL, name: String) async {
        let destination = parentDir.appendingPathComponent(name, isDirectory: true)
        do {
            try await GitClient.clone(url: url, into: destination)
            await openRepository(at: destination)
        } catch {
            if let gitError = error as? GitError, gitError.isAuthenticationFailure,
               let info = GitClient.remoteInfo(url), info.scheme == "https" {
                cloneAuthChallenge = AuthChallenge(scheme: "https", host: info.host)
                cloneRetry = { [weak self] in await self?.cloneRepository(url: url, into: parentDir, name: name) }
            } else {
                openError = (error as? GitError)?.shortMessage ?? error.localizedDescription
            }
        }
    }

    func submitCloneCredentials(username: String, secret: String) async {
        guard let challenge = cloneAuthChallenge else { return }
        cloneAuthChallenge = nil
        try? await GitClient.ensureCredentialHelper()
        let input = "protocol=\(challenge.scheme)\nhost=\(challenge.host)\nusername=\(username)\npassword=\(secret)\n\n"
        try? await GitClient.credentialApprove(input)
        let retry = cloneRetry
        cloneRetry = nil
        await retry?()
    }

    func cancelCloneAuth() {
        cloneAuthChallenge = nil
        cloneRetry = nil
    }

    func closeRepository(_ repo: RepositoryModel) {
        repo.stopWatching()
        let wasSelected = selectedRepositoryID == repo.id
        repositories.removeAll { $0.id == repo.id }
        if wasSelected {
            selectedRepositoryID = repositories.first?.id
            if repositories.isEmpty { isHomeSelected = true }
        }
    }

    func refreshActive() async {
        await selectedRepository?.reloadEverything()
    }

    /// On launch: open a repo from `GRAFTBENCH_OPEN`, otherwise reopen the most
    /// recent repository so you land straight back in your work.
    func performStartupOpen() async {
        guard repositories.isEmpty else { return }
        if let path = repoPathFromArguments() ?? ProcessInfo.processInfo.environment["GRAFTBENCH_OPEN"] {
            await openRepository(at: URL(fileURLWithPath: path))
            return
        }
        if let recent = Preferences.shared.recentRepositories.first(where: { $0.exists }) {
            await openRepository(at: recent.url)
        }
    }

    private func repoPathFromArguments() -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--open"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

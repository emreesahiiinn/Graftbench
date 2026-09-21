import Foundation

/// Result of running a git subprocess.
struct GitOutput: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
    let outputData: Data

    var isSuccess: Bool { exitCode == 0 }

    /// stdout with a single trailing newline removed.
    var trimmedOutput: String {
        var s = standardOutput
        if s.hasSuffix("\n") { s.removeLast() }
        return s
    }
}

enum GitError: LocalizedError, Sendable {
    case executableNotFound
    case commandFailed(command: String, exitCode: Int32, message: String)
    case notARepository(URL)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "git executable could not be found. Install the Xcode command line tools or Homebrew git."
        case let .commandFailed(command, code, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(command) failed (\(code))\(detail.isEmpty ? "" : ":\n\(detail)")"
        case let .notARepository(url):
            return "\(url.path) is not a git repository."
        case let .parseFailure(what):
            return "Failed to parse git output: \(what)"
        }
    }

    /// A short single-line message for compact UI.
    var shortMessage: String {
        switch self {
        case .executableNotFound: return "git not found"
        case let .commandFailed(_, _, message):
            let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
            return firstLine.trimmingCharacters(in: .whitespaces)
        case .notARepository: return "Not a git repository"
        case let .parseFailure(what): return "Parse error: \(what)"
        }
    }

    /// True when the failure looks like an authentication problem.
    var isAuthenticationFailure: Bool {
        guard case let .commandFailed(_, _, message) = self else { return false }
        let text = message.lowercased()
        let markers = [
            "authentication failed", "could not read username", "could not read password",
            "terminal prompts disabled", "permission denied (publickey",
            "invalid username or password", "support for password authentication",
            "403 forbidden", "fatal: authentication", "authentication required"
        ]
        return markers.contains { text.contains($0) }
    }
}

/// Resolves and runs the `git` executable.
enum GitProcess {
    /// Candidate locations, most-preferred first. A user-configured path (if any)
    /// is injected ahead of these by `Preferences`.
    static let commonPaths: [String] = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/usr/bin/git"
    ]

    /// The resolved absolute path to git, cached after first lookup.
    nonisolated(unsafe) static var overridePath: String?

    static func resolvedExecutable() -> String? {
        if let override = overridePath, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// Run git with the given arguments in the given working directory.
    static func run(
        _ arguments: [String],
        in workingDirectory: URL? = nil,
        input: Data? = nil,
        extraEnvironment: [String: String] = [:]
    ) async throws -> GitOutput {
        guard let executable = resolvedExecutable() else {
            throw GitError.executableNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let workingDirectory {
                    process.currentDirectoryURL = workingDirectory
                }

                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"     // never hang on credential prompts
                env["GIT_OPTIONAL_LOCKS"] = "0"       // don't take locks for read-only status
                env["LC_ALL"] = "en_US.UTF-8"
                for (key, value) in extraEnvironment { env[key] = value }
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                let inputPipe: Pipe? = (input != nil) ? Pipe() : nil
                if let inputPipe { process.standardInput = inputPipe }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if let inputPipe, let input {
                    inputPipe.fileHandleForWriting.write(input)
                    inputPipe.fileHandleForWriting.closeFile()
                }

                // Drain stdout and stderr concurrently to avoid pipe-buffer deadlock.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                let readQueue = DispatchQueue(label: "com.graftbench.git.read", attributes: .concurrent)

                group.enter()
                readQueue.async {
                    outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                readQueue.async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()

                let output = GitOutput(
                    exitCode: process.terminationStatus,
                    standardOutput: String(decoding: outData, as: UTF8.self),
                    standardError: String(decoding: errData, as: UTF8.self),
                    outputData: outData
                )
                continuation.resume(returning: output)
            }
        }
    }
}

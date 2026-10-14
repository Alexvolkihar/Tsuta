import Foundation

public struct GitError: Error, LocalizedError, Sendable {
    public let arguments: [String]
    public let status: Int32
    public let stderr: String

    public var errorDescription: String? {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "git \(arguments.first ?? "") a échoué (code \(status))" : message
    }
}

/// Runs the system `git` binary. Every call is a short-lived child process, which keeps
/// us exactly as correct as git itself (hooks, config, worktrees, submodules...).
public final class GitClient: @unchecked Sendable {
    public let root: URL
    public static let executable = "/usr/bin/git"
    /// Called for every command (success or failure), from a background thread.
    private let observer: (@Sendable (GitCommandRecord) -> Void)?

    public init(root: URL, observer: (@Sendable (GitCommandRecord) -> Void)? = nil) {
        self.root = root
        self.observer = observer
    }

    /// Runs git and returns stdout. Throws `GitError` when the exit status is not allowed.
    @discardableResult
    public func run(_ arguments: [String], stdin: String? = nil, environment: [String: String] = [:],
                    allowedStatuses: Set<Int32> = [0]) async throws -> String {
        let root = self.root
        let observer = self.observer
        return try await Task.detached(priority: .userInitiated) {
            let started = Date()
            do {
                let output = try Self.runSync(root: root, arguments: arguments, stdin: stdin, environment: environment, allowed: allowedStatuses)
                observer?(GitCommandRecord(date: started, arguments: arguments, duration: Date().timeIntervalSince(started),
                                           status: 0, outputBytes: output.utf8.count, errorText: nil))
                return output
            } catch let error as GitError {
                observer?(GitCommandRecord(date: started, arguments: arguments, duration: Date().timeIntervalSince(started),
                                           status: error.status, outputBytes: 0, errorText: error.stderr))
                throw error
            }
        }.value
    }

    static func runSync(root: URL, arguments: [String], stdin: String?, environment: [String: String] = [:],
                        allowed: Set<Int32>) throws -> String {
        var env = ["GIT_EDITOR": "true", "GIT_PAGER": "cat"]
        for (key, value) in environment { env[key] = value }
        let output = try ProcessRunner.run(
            executable: executable,
            arguments: ["--no-optional-locks", "-c", "core.quotepath=false", "-C", root.path] + arguments,
            stdin: stdin, environment: env)
        guard allowed.contains(output.status) else {
            throw GitError(arguments: arguments, status: output.status, stderr: output.stderr)
        }
        return output.stdout
    }

    /// Resolves the top-level directory of the repository containing `url`, or nil.
    public static func topLevel(of url: URL) -> URL? {
        guard let out = try? runSync(root: url, arguments: ["rev-parse", "--show-toplevel"], stdin: nil, allowed: [0]) else { return nil }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
}

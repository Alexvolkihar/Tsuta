import AppKit
import Foundation
import HankoCore
import Observation

/// Everything AI-related for one repository: generation through a local CLI, and the list of
/// Claude Code / Codex conversations that worked in this repository or one of its worktrees.
@MainActor
@Observable
final class AssistantModel {
    private let git: GitClient
    private let settings: AppSettings

    private(set) var isBusy = false
    private(set) var title = ""
    private(set) var output: String?
    private(set) var sessions: [AgentSession] = []
    private(set) var isLoadingSessions = false

    var onError: (String) -> Void = { _ in }
    var directories: () -> [String] = { [] }

    init(git: GitClient, settings: AppSettings) {
        self.git = git
        self.settings = settings
    }

    var backend: AIBackend? { settings.agent }
    var isAvailable: Bool { backend != nil }

    func dismissOutput() { output = nil }

    // MARK: Generation

    private func run(title: String, _ prompt: () async throws -> String) async -> String? {
        guard let backend else {
            onError("Aucun outil IA trouvé. Installe « claude » (Claude Code) ou « codex ».")
            return nil
        }
        isBusy = true
        self.title = title
        defer { isBusy = false }
        do {
            return AIPrompts.stripFence(try await AIRunner.ask(try await prompt(), backend: backend))
        } catch {
            onError(error.localizedDescription)
            return nil
        }
    }

    func commitMessage() async -> String? {
        await run(title: "Message de commit") {
            let patch = try await git.run(["diff", "--cached", "--no-ext-diff", "--no-textconv", "--no-color"])
            guard !patch.isEmpty else { throw AIError(message: "Rien n’est indexé : indexe des fichiers d’abord.") }
            let subjects = try await git.run(["log", "-n", "8", "--format=%s"], allowedStatuses: [0, 128])
            return AIPrompts.commitMessage(stagedDiff: patch, recentSubjects: subjects.split(separator: "\n").map(String.init))
        }
    }

    func explain(_ commit: Commit) async {
        output = await run(title: "Explication de \(commit.shortID)") {
            let patch = try await git.run(["show", "--format=", "--patch", "--no-ext-diff", "--no-textconv",
                                           "--diff-merges=first-parent", "--no-color", commit.id])
            return AIPrompts.explain(commit: commit.subject, patch: patch)
        }
    }

    func resolution(for block: ConflictBlock, path: String) async -> [String]? {
        await run(title: "Suggestion de résolution") { AIPrompts.resolveConflict(path: path, block: block) }?
            .components(separatedBy: "\n")
    }

    func summarize(_ request: ReviewRequest, diff: [DiffFile], discussion: [ReviewComment]) async {
        let raw = diff.flatMap(\.lines).map { line -> String in
            switch line.kind {
            case .added: "+" + line.text
            case .removed: "-" + line.text
            default: line.text
            }
        }.joined(separator: "\n")
        output = await run(title: "Résumé de #\(request.number)") {
            AIPrompts.summarize(request: request.title, diff: raw, discussion: discussion.map { "\($0.author): \($0.body)" })
        }
    }

    // MARK: Agent sessions

    func loadSessions() async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }
        let dirs = directories()
        sessions = await Task.detached(priority: .utility) { AgentSessionScanner.sessions(directories: dirs) }.value
    }

    func sessions(in directory: String) -> [AgentSession] { sessions.filter { $0.directory == directory } }

    /// Opens Terminal in the session's directory and runs the agent. Ids come from file names on
    /// disk, so they are validated before being placed in a shell command.
    func resume(_ session: AgentSession) {
        guard session.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            onError("Identifiant de session invalide.")
            return
        }
        launchTerminal(directory: session.directory, command: session.resumeCommand)
    }

    func startNewSession(agent: AgentSession.Agent, in directory: String) {
        launchTerminal(directory: directory, command: agent == .claudeCode ? "claude" : "codex")
    }

    func copyCommand(_ session: AgentSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("cd '\(session.directory)' && \(session.resumeCommand)", forType: .string)
    }

    private func launchTerminal(directory: String, command: String) {
        let quoted = directory.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/zsh\ncd '\(quoted)' || exit 1\nexec \(command)\n"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hanko-\(UUID().uuidString).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

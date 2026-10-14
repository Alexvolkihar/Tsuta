import Foundation

// MARK: Repository operation in progress (merge / rebase / cherry-pick / revert)

public enum RepoOperation: String, Sendable {
    case none, merge, rebase, cherryPick, revert

    public static func detect(gitDirectory: URL) -> RepoOperation {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: gitDirectory.appendingPathComponent(name).path) }
        if exists("rebase-merge") || exists("rebase-apply") { return .rebase }
        if exists("MERGE_HEAD") { return .merge }
        if exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if exists("REVERT_HEAD") { return .revert }
        return .none
    }

    public var title: String {
        switch self {
        case .none: ""
        case .merge: "Merge en cours"
        case .rebase: "Rebase en cours"
        case .cherryPick: "Cherry-pick en cours"
        case .revert: "Revert en cours"
        }
    }

    public var continueArguments: [String]? {
        switch self {
        case .none: nil
        case .merge: ["commit", "--no-edit"]
        case .rebase: ["rebase", "--continue"]
        case .cherryPick: ["cherry-pick", "--continue"]
        case .revert: ["revert", "--continue"]
        }
    }

    public var abortArguments: [String]? {
        switch self {
        case .none: nil
        case .merge: ["merge", "--abort"]
        case .rebase: ["rebase", "--abort"]
        case .cherryPick: ["cherry-pick", "--abort"]
        case .revert: ["revert", "--abort"]
        }
    }
}

// MARK: Interactive rebase

public enum RebaseAction: String, CaseIterable, Identifiable, Sendable {
    case pick, reword, squash, fixup, drop
    public var id: String { rawValue }
}

public struct RebaseEntry: Identifiable, Equatable, Sendable {
    public let id: String          // full sha
    public let shortID: String
    public let subject: String
    public var action: RebaseAction
    public var newMessage: String

    public init(id: String, shortID: String, subject: String, action: RebaseAction = .pick, newMessage: String? = nil) {
        self.id = id; self.shortID = shortID; self.subject = subject
        self.action = action; self.newMessage = newMessage ?? subject
    }
}

public enum RebasePlanner {
    public static let logFormat = "--format=%H%x1f%h%x1f%s"

    public static func parseEntries(_ text: String) -> [RebaseEntry] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3 else { return nil }
            return RebaseEntry(id: f[0], shortID: f[1], subject: f[2])
        }
    }

    /// Returns a user-facing problem with the plan, or nil when it is valid.
    public static func validate(_ entries: [RebaseEntry]) -> String? {
        guard let first = entries.first(where: { $0.action != .drop }) else {
            return entries.isEmpty ? "Aucun commit à rebaser." : "Tous les commits sont supprimés."
        }
        if first.action == .squash || first.action == .fixup {
            return "Le premier commit conservé ne peut pas être squash/fixup : il n’a aucun commit précédent."
        }
        if let empty = entries.first(where: { $0.action == .reword && $0.newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Le message du commit \(empty.shortID) est vide."
        }
        return nil
    }

    /// The todo list git will execute. Rewording is done with an `exec git commit --amend`
    /// so that no editor ever opens; `messageFile` returns the path holding the new message.
    public static func todo(_ entries: [RebaseEntry], messageFile: (RebaseEntry) -> String) -> String {
        var lines: [String] = []
        for entry in entries {
            switch entry.action {
            case .reword:
                lines.append("pick \(entry.id) \(entry.subject)")
                lines.append("exec git commit --amend -q --no-verify -F '\(messageFile(entry))'")
            default:
                lines.append("\(entry.action.rawValue) \(entry.id) \(entry.subject)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: Stash & worktrees

public struct StashEntry: Identifiable, Hashable, Sendable {
    public var id: String { ref }
    public let ref: String
    public let message: String
    public let date: Date
}

public struct Worktree: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let head: String
    public let branch: String?
    public let isBare: Bool
    public let isDetached: Bool
    public let isMain: Bool
    public let isLocked: Bool

    public var displayName: String {
        branch ?? (isDetached ? "détaché @ \(head.prefix(7))" : (path as NSString).lastPathComponent)
    }
}

public enum GitLists {
    public static let stashFormat = "--format=%gd%x1f%ct%x1f%gs"

    public static func parseStashes(_ text: String) -> [StashEntry] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3 else { return nil }
            return StashEntry(ref: f[0], message: f[2], date: Date(timeIntervalSince1970: TimeInterval(f[1]) ?? 0))
        }
    }

    public static func parseWorktrees(_ text: String) -> [Worktree] {
        var result: [Worktree] = []
        for (index, block) in text.components(separatedBy: "\n\n").enumerated() {
            var path = "", head = "", branch: String? = nil
            var bare = false, detached = false, locked = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
                else if line.hasPrefix("HEAD ") { head = String(line.dropFirst(5)) }
                else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst(7))
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : ref
                }
                else if line == "bare" { bare = true }
                else if line == "detached" { detached = true }
                else if line.hasPrefix("locked") { locked = true }
            }
            if !path.isEmpty {
                result.append(Worktree(path: path, head: head, branch: branch, isBare: bare,
                                       isDetached: detached, isMain: index == 0, isLocked: locked))
            }
        }
        return result
    }
}

// MARK: GitClient helpers

extension GitClient {
    public func gitDirectory() async throws -> URL {
        let out = try await run(["rev-parse", "--absolute-git-dir"])
        return URL(fileURLWithPath: out.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
    }

    public func currentOperation() async -> RepoOperation {
        guard let dir = try? await gitDirectory() else { return .none }
        return RepoOperation.detect(gitDirectory: dir)
    }

    /// Runs `git rebase -i` non-interactively: the todo list is injected through
    /// GIT_SEQUENCE_EDITOR, rewording uses `exec git commit --amend -F`.
    /// `base == nil` rebases from the root commit.
    public func interactiveRebase(onto base: String?, entries: [RebaseEntry]) async throws {
        if let problem = RebasePlanner.validate(entries) { throw GitError(arguments: ["rebase"], status: 1, stderr: problem) }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tsuta-rebase-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var messageFiles: [String: String] = [:]
        for entry in entries where entry.action == .reword {
            let file = scratch.appendingPathComponent("msg-\(entry.shortID)")
            try (entry.newMessage + "\n").write(to: file, atomically: true, encoding: .utf8)
            messageFiles[entry.id] = file.path
        }
        let todo = scratch.appendingPathComponent("todo")
        try RebasePlanner.todo(entries) { messageFiles[$0.id] ?? "" }.write(to: todo, atomically: true, encoding: .utf8)

        var args = ["rebase", "-i", "--autostash"]
        args += base.map { [$0] } ?? ["--root"]
        try await run(args, environment: ["GIT_SEQUENCE_EDITOR": "cp '\(todo.path)'"])
    }
}

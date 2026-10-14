import AppKit
import Foundation
import TsutaCore

extension RepoSession {
    // MARK: Operation in progress

    func continueOperation() async {
        guard let args = operation.continueArguments else { return }
        await perform { try await $0.run(args) }
    }

    func abortOperation() async {
        guard let args = operation.abortArguments else { return }
        await perform { try await $0.run(args) }
    }

    // MARK: Conflicts

    func conflictFileURL(_ change: FileChange) -> URL { root.appendingPathComponent(change.path) }

    func resolveConflict(path: String, content: String) async {
        await perform { git in
            try content.write(to: git.root.appendingPathComponent(path), atomically: true, encoding: .utf8)
            try await git.run(["add", "--", path])
        }
    }

    func takeSide(_ change: FileChange, side: String) async {
        await perform { git in
            try await git.run(["checkout", "--\(side)", "--", change.path])
            try await git.run(["add", "--", change.path])
        }
    }

    // MARK: Remote

    func fetch() async { await perform { try await $0.run(["fetch", "--all", "--prune"]) } }

    func pull() async {
        let flag = settings.pullFlag
        await perform { try await $0.run(["pull", flag], allowedStatuses: [0, 1]) }
    }

    /// Publishes the branch with an upstream the first time, plain `push` afterwards.
    func push() async {
        let branch = status.branch
        let needsUpstream = status.upstream == nil && !branch.isEmpty && !branch.hasPrefix("(")
        let remote = knownRemoteName
        await perform { git in
            if needsUpstream, let remote {
                try await git.run(["push", "--set-upstream", remote, branch])
            } else {
                try await git.run(["push"])
            }
        }
    }

    private var knownRemoteName: String? {
        branches.first(where: \.isRemote).map { String($0.name.split(separator: "/").first ?? "origin") } ?? (remoteURL == nil ? nil : "origin")
    }

    // MARK: Worktrees & submodules

    func addWorktree(path: String, branch: String) async {
        await perform { try await $0.run(["worktree", "add", "-b", branch, path]) }
    }

    func removeWorktree(_ tree: Worktree) async {
        await perform { try await $0.run(["worktree", "remove", tree.path]) }
    }

    func updateSubmodule(_ module: SubmoduleInfo) async {
        await perform { try await $0.run(["submodule", "update", "--init", "--", module.path]) }
    }

    func submoduleURL(_ module: SubmoduleInfo) -> URL { root.appendingPathComponent(module.path, isDirectory: true) }

    // MARK: Console

    func clearConsole() { /* records are append-only by design; replaced wholesale here */
        consoleReset()
    }
}

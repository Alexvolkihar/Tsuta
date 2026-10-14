import Foundation

// MARK: Blame and file history

extension GitParsing {
    /// Parses `git blame --porcelain`.
    public static func parseBlame(_ text: String) -> [BlameLine] {
        struct Meta { var author = "", email = "", time: TimeInterval = 0, summary = "" }
        var metas: [String: Meta] = [:]
        var lines: [BlameLine] = []
        var currentCommit = "", currentLine = 0

        func isHeader(_ line: Substring) -> (String, Int)? {
            let parts = line.split(separator: " ")
            guard parts.count >= 3, parts[0].count == 40, parts[0].allSatisfy(\.isHexDigit),
                  let final = Int(parts[2]) else { return nil }
            return (String(parts[0]), final)
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("\t") {
                let meta = metas[currentCommit] ?? Meta()
                lines.append(BlameLine(number: currentLine, commit: currentCommit, author: meta.author, email: meta.email,
                                       date: Date(timeIntervalSince1970: meta.time), summary: meta.summary,
                                       text: String(raw.dropFirst())))
            } else if let (sha, final) = isHeader(raw) {
                currentCommit = sha
                currentLine = final
                if metas[sha] == nil { metas[sha] = Meta() }
            } else if raw.hasPrefix("author ") {
                metas[currentCommit]?.author = String(raw.dropFirst(7))
            } else if raw.hasPrefix("author-mail ") {
                metas[currentCommit]?.email = String(raw.dropFirst(12)).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            } else if raw.hasPrefix("author-time ") {
                metas[currentCommit]?.time = TimeInterval(raw.dropFirst(12)) ?? 0
            } else if raw.hasPrefix("summary ") {
                metas[currentCommit]?.summary = String(raw.dropFirst(8))
            }
        }
        return lines
    }

    /// Parses `git log --follow --name-only --format=%H`: the path a file had at each commit.
    public static func parseFollowedPaths(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var sha: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if raw.count == 40, raw.allSatisfy(\.isHexDigit) {
                sha = String(raw)
            } else if let current = sha, result[current] == nil {
                result[current] = String(raw)
            }
        }
        return result
    }
}

extension GitClient {
    public func blame(path: String, revision: String? = nil) async throws -> [BlameLine] {
        var args = ["blame", "--porcelain"]
        if let revision { args.append(revision) }
        args += ["--", path]
        return GitParsing.parseBlame(try await run(args))
    }

    /// Commits that touched `path`, newest first, following renames.
    public func fileHistory(path: String, limit: Int = 300) async throws -> [FileHistoryEntry] {
        async let log = run(["log", "--follow", "-n", String(limit), GitParsing.logFormat, "--", path])
        async let names = run(["log", "--follow", "-n", String(limit), "--name-only", "--format=%H", "--", path])
        let commits = GitParsing.parseLog(try await log)
        let paths = GitParsing.parseFollowedPaths(try await names)
        return commits.map { FileHistoryEntry(commit: $0, path: paths[$0.id] ?? path) }
    }

    /// Patch of one commit restricted to the path the file had at that commit.
    public func filePatch(commit: String, path: String) async throws -> [DiffFile] {
        let out = try await run(["show", "--format=", "--patch", "-M", "--no-ext-diff", "--no-textconv", "--no-color", commit, "--", path])
        return GitParsing.parseDiff(out)
    }

    // MARK: Partial staging of a new file

    /// Records an untracked file in the index as "intent to add", so it shows up as a regular
    /// diff whose lines can be staged one by one. Nothing is staged until a line is applied.
    public func markIntentToAdd(path: String) async throws {
        try await run(["add", "--intent-to-add", "--", path])
    }

    /// Drops an intent-to-add entry (or any index entry) without touching the working tree file.
    public func forgetIndexEntry(path: String) async throws {
        try await run(["rm", "--cached", "-q", "--", path])
    }
}

// MARK: Snapshots for undo

/// Where HEAD and the index were before an operation that rewrites history.
public struct HeadSnapshot: Sendable, Equatable {
    public let head: String?
    public let branch: String?
    public let indexTree: String?
}

extension GitClient {
    public enum RestoreMode: Sendable {
        /// `reset --keep`: HEAD, index and files return to the snapshot; uncommitted changes that
        /// do not conflict are kept, and git refuses when they do.
        case keep
        /// `reset --soft` then the saved index: for resets and amends, where files did not move.
        case soft
    }

    public func headSnapshot() async -> HeadSnapshot {
        async let head = try? run(["rev-parse", "--verify", "-q", "HEAD"], allowedStatuses: [0, 1])
        async let branch = try? run(["symbolic-ref", "--short", "-q", "HEAD"], allowedStatuses: [0, 1])
        async let tree = try? run(["write-tree"])
        func clean(_ value: String??) -> String? {
            guard let inner = value ?? nil else { return nil }
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return HeadSnapshot(head: clean(await head), branch: clean(await branch), indexTree: clean(await tree))
    }

    /// Restores a snapshot, but only if the repository is still where the operation left it.
    public func restore(_ snapshot: HeadSnapshot, expectedHead: String?, mode: RestoreMode) async throws {
        let now = await headSnapshot()
        if let expectedHead, now.head != expectedHead {
            throw GitError(arguments: ["undo"], status: 1,
                           stderr: "L’historique a changé depuis cette action : l’annuler ne serait plus sûr.")
        }
        if now.branch != snapshot.branch {
            throw GitError(arguments: ["undo"], status: 1,
                           stderr: "Tu n’es plus sur la branche d’origine (\(snapshot.branch ?? "HEAD détaché")).")
        }
        guard let previous = snapshot.head else {
            throw GitError(arguments: ["undo"], status: 1, stderr: "Il n’y avait pas encore de commit avant cette action.")
        }
        switch mode {
        case .keep:
            try await run(["reset", "--keep", previous])
        case .soft:
            try await run(["reset", "--soft", previous])
            if let tree = snapshot.indexTree { try await run(["read-tree", tree]) }
        }
    }
}

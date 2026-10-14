import Foundation

public struct RefLabel: Hashable, Sendable {
    public enum Kind: Sendable { case head, local, remote, tag }
    public let name: String
    public let kind: Kind
    public init(name: String, kind: Kind) { self.name = name; self.kind = kind }
}

public struct Commit: Identifiable, Hashable, Sendable {
    public let id: String
    public let shortID: String
    public let parents: [String]
    public let author: String
    public let email: String
    public let date: Date
    public let refs: [RefLabel]
    public let subject: String

    public init(id: String, shortID: String, parents: [String], author: String, email: String,
                date: Date, refs: [RefLabel], subject: String) {
        self.id = id; self.shortID = shortID; self.parents = parents; self.author = author
        self.email = email; self.date = date; self.refs = refs; self.subject = subject
    }
}

public struct FileChange: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let originalPath: String?
    /// Index (staged) status letter, "." when unchanged.
    public let index: Character
    /// Working tree status letter, "." when unchanged.
    public let worktree: Character
    public let isUntracked: Bool
    public let isConflicted: Bool

    public var isStaged: Bool { !isUntracked && !isConflicted && index != "." }
    public var isUnstaged: Bool { isUntracked || isConflicted || worktree != "." }
}

public struct RepoStatus: Sendable, Equatable {
    public var branch: String = ""
    public var upstream: String?
    public var ahead: Int = 0
    public var behind: Int = 0
    public var changes: [FileChange] = []
    public init() {}

    public var staged: [FileChange] { changes.filter(\.isStaged) }
    public var unstaged: [FileChange] { changes.filter(\.isUnstaged) }
}

public struct BranchInfo: Identifiable, Hashable, Sendable {
    public var id: String { fullName }
    public let name: String
    public let fullName: String
    public let isCurrent: Bool
    public let isRemote: Bool
    public let upstream: String?
}

public struct DiffLine: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case meta, hunk, context, added, removed }
    public let id: Int
    public let kind: Kind
    public let text: String
    public let oldNumber: Int?
    public let newNumber: Int?

    public var isChange: Bool { kind == .added || kind == .removed }
}

public struct DiffHunk: Identifiable, Hashable, Sendable {
    public var id: Int { header.id }
    public let header: DiffLine
    public let oldStart: Int
    public let newStart: Int
    public let lines: [DiffLine]

    public var changeIDs: Set<Int> { Set(lines.filter(\.isChange).map(\.id)) }
}

public struct DiffFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    /// `diff --git`, `index`, `---` and `+++` lines, verbatim: needed to rebuild a patch.
    public let headerLines: [String]
    public let hunks: [DiffHunk]
    /// Every line in display order (header meta lines, hunk headers and hunk bodies).
    public let lines: [DiffLine]

    public var additions: Int { lines.filter { $0.kind == .added }.count }
    public var deletions: Int { lines.filter { $0.kind == .removed }.count }
    public var isBinary: Bool { hunks.isEmpty && headerLines.contains { $0.hasPrefix("Binary files") || $0.hasPrefix("GIT binary patch") } }
}

public struct SubmoduleInfo: Identifiable, Hashable, Sendable {
    public enum State: Sendable { case upToDate, uninitialized, modified, conflicted }
    public var id: String { path }
    public let path: String
    public let commit: String
    public let state: State
    public let describe: String?
}

public struct GitCommandRecord: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let arguments: [String]
    public let duration: TimeInterval
    public let status: Int32
    public let outputBytes: Int
    public let errorText: String?

    public var commandLine: String { "git " + arguments.joined(separator: " ") }
}

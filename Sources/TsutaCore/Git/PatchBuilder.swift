import Foundation

/// Builds partial patches so single hunks or single lines can be staged / unstaged
/// with `git apply --cached --recount` (the same technique other Git GUIs use).
public enum PatchBuilder {
    public enum Direction: Sendable {
        /// Working tree -> index: the patch comes from `git diff`, applied forward.
        case stage
        /// Index -> HEAD: the patch comes from `git diff --cached`, applied with `-R`.
        case unstage

        /// Extra arguments for `git apply`.
        public var applyArguments: [String] {
            switch self {
            case .stage: ["apply", "--cached", "--recount", "--whitespace=nowarn", "-"]
            case .unstage: ["apply", "--cached", "-R", "--recount", "--whitespace=nowarn", "-"]
            }
        }
    }

    /// `selected` holds the ids of the added/removed lines to act on. Unselected changes are
    /// neutralised so the patch only carries the selection. Returns nil when nothing is selected.
    public static func patch(for file: DiffFile, selected: Set<Int>, direction: Direction) -> String? {
        var body: [String] = []
        for hunk in file.hunks {
            guard hunk.lines.contains(where: { selected.contains($0.id) }) else { continue }
            var old = 0, new = 0
            var out: [String] = []
            for line in hunk.lines {
                switch line.kind {
                case .context:
                    out.append(" " + line.text); old += 1; new += 1
                case .meta:
                    out.append(line.text)
                case .added:
                    if selected.contains(line.id) {
                        out.append("+" + line.text); new += 1
                    } else if direction == .unstage {
                        out.append(" " + line.text); old += 1; new += 1   // stays in the index
                    }                                                    // stage: not part of this patch
                case .removed:
                    if selected.contains(line.id) {
                        out.append("-" + line.text); old += 1
                    } else if direction == .stage {
                        out.append(" " + line.text); old += 1; new += 1   // stays in the index
                    }                                                    // unstage: already absent
                case .hunk:
                    break
                }
            }
            body.append("@@ -\(hunk.oldStart),\(old) +\(hunk.newStart),\(new) @@")
            body += out
        }
        guard !body.isEmpty else { return nil }
        return (file.headerLines + body).joined(separator: "\n") + "\n"
    }

    public static func patch(for hunk: DiffHunk, in file: DiffFile, direction: Direction) -> String? {
        patch(for: file, selected: hunk.changeIDs, direction: direction)
    }
}

/// Client-side filter over the loaded history.
public struct HistoryFilter: Equatable, Sendable {
    public var text = ""
    public var author = ""

    public init(text: String = "", author: String = "") { self.text = text; self.author = author }

    public var isActive: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty || !author.trimmingCharacters(in: .whitespaces).isEmpty }

    public func matches(_ commit: Commit) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if !t.isEmpty {
            let haystack = ([commit.subject, commit.id, commit.shortID, commit.author] + commit.refs.map(\.name)).joined(separator: "\n").lowercased()
            if !haystack.contains(t) { return false }
        }
        let a = author.trimmingCharacters(in: .whitespaces).lowercased()
        if !a.isEmpty, !commit.author.lowercased().contains(a), !commit.email.lowercased().contains(a) { return false }
        return true
    }

    public func apply(to commits: [Commit]) -> [Commit] { isActive ? commits.filter(matches) : commits }
}

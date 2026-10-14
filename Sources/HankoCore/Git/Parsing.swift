import Foundation

public enum GitParsing {
    private static let recordSeparator: Character = "\u{1e}"
    private static let unitSeparator: Character = "\u{1f}"

    /// Pass as arguments to `git log` — keep in sync with `parseLog`.
    public static let logFormat = "--format=%x1e%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%D%x1f%s"

    public static func parseLog(_ text: String, remotes: Set<String> = []) -> [Commit] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return text.split(separator: recordSeparator, omittingEmptySubsequences: true).compactMap { record in
            let f = record.split(separator: unitSeparator, maxSplits: 7, omittingEmptySubsequences: false)
            guard f.count == 8 else { return nil }
            return Commit(
                id: String(f[0]),
                shortID: String(f[1]),
                parents: f[2].split(separator: " ").map(String.init),
                author: String(f[3]),
                email: String(f[4]),
                date: iso.date(from: String(f[5])) ?? .distantPast,
                refs: parseDecoration(String(f[6]), remotes: remotes),
                subject: f[7].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public static func parseDecoration(_ text: String, remotes: Set<String>) -> [RefLabel] {
        text.split(separator: ",").compactMap { raw in
            let part = raw.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { return nil }
            if part.hasPrefix("HEAD -> ") { return RefLabel(name: String(part.dropFirst(8)), kind: .head) }
            if part == "HEAD" { return RefLabel(name: "HEAD", kind: .head) }
            if part.hasPrefix("tag: ") { return RefLabel(name: String(part.dropFirst(5)), kind: .tag) }
            if part.hasSuffix("/HEAD") { return nil }
            if let slash = part.firstIndex(of: "/"), remotes.contains(String(part[..<slash])) {
                return RefLabel(name: part, kind: .remote)
            }
            return RefLabel(name: part, kind: .local)
        }
    }

    /// Parses `git status --porcelain=v2 -z --branch --untracked-files=all`.
    public static func parseStatus(_ text: String) -> RepoStatus {
        var status = RepoStatus()
        let tokens = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            i += 1
            if token.hasPrefix("# ") {
                let parts = token.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                if parts[0] == "branch.head" { status.branch = parts[1] }
                if parts[0] == "branch.upstream" { status.upstream = parts[1] }
                if parts[0] == "branch.ab" {
                    let ab = parts[1].split(separator: " ")
                    if ab.count == 2 {
                        status.ahead = Int(ab[0].dropFirst()) ?? 0
                        status.behind = Int(ab[1].dropFirst()) ?? 0
                    }
                }
                continue
            }
            guard let kind = token.first else { continue }
            switch kind {
            case "1":
                let f = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard f.count == 9, f[1].count == 2 else { continue }
                let xy = Array(f[1])
                status.changes.append(FileChange(path: String(f[8]), originalPath: nil, index: xy[0], worktree: xy[1], isUntracked: false, isConflicted: false))
            case "2":
                let f = token.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard f.count == 10, f[1].count == 2 else { continue }
                let xy = Array(f[1])
                let original = i < tokens.count ? tokens[i] : nil
                i += 1
                status.changes.append(FileChange(path: String(f[9]), originalPath: original, index: xy[0], worktree: xy[1], isUntracked: false, isConflicted: false))
            case "u":
                let f = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard f.count == 11 else { continue }
                status.changes.append(FileChange(path: String(f[10]), originalPath: nil, index: "U", worktree: "U", isUntracked: false, isConflicted: true))
            case "?":
                status.changes.append(FileChange(path: String(token.dropFirst(2)), originalPath: nil, index: ".", worktree: "?", isUntracked: true, isConflicted: false))
            default:
                continue
            }
        }
        status.changes.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return status
    }

    /// `git for-each-ref --format=%(refname:short)%09%(refname)%09%(HEAD)%09%(upstream:short)`
    public static let branchFormat = "--format=%(refname:short)%09%(refname)%09%(HEAD)%09%(upstream:short)"

    public static func parseBranches(_ text: String) -> [BranchInfo] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3 else { return nil }
            let full = f[1]
            if full.hasSuffix("/HEAD") { return nil }
            return BranchInfo(
                name: f[0], fullName: full,
                isCurrent: f[2] == "*",
                isRemote: full.hasPrefix("refs/remotes/"),
                upstream: f.count > 3 && !f[3].isEmpty ? f[3] : nil
            )
        }
    }

    /// `git submodule status` (non recursive).
    public static func parseSubmodules(_ text: String) -> [SubmoduleInfo] {
        text.split(separator: "\n").compactMap { raw in
            guard let marker = raw.first else { return nil }
            let rest = raw.dropFirst().split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard rest.count >= 2 else { return nil }
            let state: SubmoduleInfo.State
            switch marker {
            case "-": state = .uninitialized
            case "+": state = .modified
            case "U": state = .conflicted
            default: state = .upToDate
            }
            let describe = rest.count == 3 ? rest[2].trimmingCharacters(in: CharacterSet(charactersIn: "()")) : nil
            return SubmoduleInfo(path: rest[1], commit: rest[0], state: state, describe: describe)
        }
    }

    /// Parses a unified diff (possibly several files) into files, hunks and displayable lines.
    public static func parseDiff(_ text: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var counter = 0

        var path = ""
        var header: [String] = []
        var hunks: [DiffHunk] = []
        var lines: [DiffLine] = []
        var hunkHeader: DiffLine?
        var hunkOld = 0, hunkNew = 0
        var hunkLines: [DiffLine] = []
        var oldNo = 0, newNo = 0

        func makeLine(_ kind: DiffLine.Kind, _ text: String, old: Int? = nil, new: Int? = nil) -> DiffLine {
            defer { counter += 1 }
            return DiffLine(id: counter, kind: kind, text: text, oldNumber: old, newNumber: new)
        }
        func closeHunk() {
            if let h = hunkHeader { hunks.append(DiffHunk(header: h, oldStart: hunkOld, newStart: hunkNew, lines: hunkLines)) }
            hunkHeader = nil; hunkLines = []
        }
        func closeFile() {
            closeHunk()
            if !path.isEmpty || !lines.isEmpty {
                files.append(DiffFile(path: path, headerLines: header, hunks: hunks, lines: lines))
            }
            path = ""; header = []; hunks = []; lines = []
        }
        func append(_ line: DiffLine, toHunk: Bool) {
            lines.append(line)
            if toHunk { hunkLines.append(line) }
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git ") {
                closeFile()
                if let range = line.range(of: " b/", options: .backwards) { path = String(line[range.upperBound...]) }
                header.append(line)
                append(makeLine(.meta, line), toHunk: false)
                continue
            }
            if line.hasPrefix("@@") {
                closeHunk()
                let numbers = line.split(whereSeparator: { !"0123456789-+,".contains($0) }).prefix(2)
                if numbers.count == 2 {
                    oldNo = Int(numbers[0].dropFirst().split(separator: ",").first ?? "0") ?? 0
                    newNo = Int(numbers[1].dropFirst().split(separator: ",").first ?? "0") ?? 0
                }
                hunkOld = oldNo; hunkNew = newNo
                let h = makeLine(.hunk, line)
                hunkHeader = h
                lines.append(h)
                continue
            }
            if hunkHeader == nil {
                if line.hasPrefix("+++ b/") && path.isEmpty { path = String(line.dropFirst(6)) }
                if !line.isEmpty {
                    header.append(line)
                    append(makeLine(.meta, line), toHunk: false)
                }
                continue
            }
            switch line.first {
            case "+": append(makeLine(.added, String(line.dropFirst()), new: newNo), toHunk: true); newNo += 1
            case "-": append(makeLine(.removed, String(line.dropFirst()), old: oldNo), toHunk: true); oldNo += 1
            case "\\": append(makeLine(.meta, line), toHunk: true)
            case " ": append(makeLine(.context, String(line.dropFirst()), old: oldNo, new: newNo), toHunk: true); oldNo += 1; newNo += 1
            default: if !line.isEmpty { append(makeLine(.meta, line), toHunk: true) }
            }
        }
        closeFile()
        return files
    }
}

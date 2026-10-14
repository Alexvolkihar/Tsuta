import Foundation

public enum ForgeKind: String, Sendable {
    case github, gitlab

    public var cli: String { self == .github ? "gh" : "glab" }
    public var requestName: String { self == .github ? "Pull request" : "Merge request" }

    public static func detect(remoteURL: String) -> ForgeKind? {
        let url = remoteURL.lowercased()
        if url.contains("github.com") { return .github }
        if url.contains("gitlab") { return .gitlab }
        return nil
    }
}

public enum ChecksState: String, Codable, Sendable { case passing, failing, pending, none }

public struct ReviewRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let title: String
    public let author: String
    public let sourceBranch: String
    public let targetBranch: String
    public let url: String
    public let isDraft: Bool
    public let updatedAt: Date
    public let checks: ChecksState
    /// APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED (GitHub) or nil.
    public let decision: String?
}

public struct ReviewComment: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case comment, review, inline }
    public let id: String
    public let kind: Kind
    public let author: String
    public let body: String
    public let path: String?
    public let line: Int?
    public let state: String?
    public let date: Date
}

public enum ForgeParsing {
    private static func date(_ value: Any?) -> Date {
        guard let s = value as? String else { return .distantPast }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? .distantPast
    }

    private static func objects(_ text: String) -> [[String: Any]] {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return json
    }

    private static func login(_ value: Any?) -> String {
        let dict = value as? [String: Any]
        return (dict?["login"] as? String) ?? (dict?["username"] as? String) ?? (dict?["name"] as? String) ?? "?"
    }

    public static let githubListFields = "number,title,author,headRefName,baseRefName,url,isDraft,updatedAt,reviewDecision,statusCheckRollup"

    public static func parseGitHubList(_ text: String) -> [ReviewRequest] {
        objects(text).compactMap { o in
            guard let number = o["number"] as? Int, let title = o["title"] as? String else { return nil }
            return ReviewRequest(
                number: number, title: title, author: login(o["author"]),
                sourceBranch: o["headRefName"] as? String ?? "", targetBranch: o["baseRefName"] as? String ?? "",
                url: o["url"] as? String ?? "", isDraft: o["isDraft"] as? Bool ?? false,
                updatedAt: date(o["updatedAt"]), checks: githubChecks(o["statusCheckRollup"]),
                decision: (o["reviewDecision"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    static func githubChecks(_ value: Any?) -> ChecksState {
        guard let items = value as? [[String: Any]], !items.isEmpty else { return .none }
        var pending = false
        for item in items {
            let conclusion = (item["conclusion"] as? String ?? "").uppercased()
            let status = (item["status"] as? String ?? "").uppercased()
            let state = (item["state"] as? String ?? "").uppercased()
            if ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"].contains(conclusion)
                || ["FAILURE", "ERROR"].contains(state) { return .failing }
            if (!status.isEmpty && status != "COMPLETED") || state == "PENDING" || state == "EXPECTED" { pending = true }
        }
        return pending ? .pending : .passing
    }

    public static func parseGitLabList(_ text: String) -> [ReviewRequest] {
        objects(text).compactMap { o in
            guard let number = o["iid"] as? Int, let title = o["title"] as? String else { return nil }
            return ReviewRequest(
                number: number, title: title, author: login(o["author"]),
                sourceBranch: o["source_branch"] as? String ?? "", targetBranch: o["target_branch"] as? String ?? "",
                url: o["web_url"] as? String ?? "", isDraft: (o["draft"] as? Bool) ?? (o["work_in_progress"] as? Bool) ?? false,
                updatedAt: date(o["updated_at"]), checks: .none, decision: nil)
        }
    }

    /// `gh pr view N --json comments,reviews`
    public static func parseGitHubDiscussion(_ text: String) -> [ReviewComment] {
        guard let data = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var result: [ReviewComment] = []
        for (i, c) in (o["comments"] as? [[String: Any]] ?? []).enumerated() {
            result.append(ReviewComment(id: "c\(i)", kind: .comment, author: login(c["author"]),
                                        body: c["body"] as? String ?? "", path: nil, line: nil, state: nil, date: date(c["createdAt"])))
        }
        for (i, r) in (o["reviews"] as? [[String: Any]] ?? []).enumerated() {
            let body = r["body"] as? String ?? ""
            let state = r["state"] as? String
            if body.isEmpty && state == "COMMENTED" { continue }
            result.append(ReviewComment(id: "r\(i)", kind: .review, author: login(r["author"]),
                                        body: body, path: nil, line: nil, state: state, date: date(r["submittedAt"])))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// `gh api repos/{owner}/{repo}/pulls/N/comments`
    public static func parseGitHubInline(_ text: String) -> [ReviewComment] {
        objects(text).enumerated().map { i, c in
            ReviewComment(id: "i\(c["id"] as? Int ?? i)", kind: .inline, author: login(c["user"]),
                          body: c["body"] as? String ?? "", path: c["path"] as? String,
                          line: (c["line"] as? Int) ?? (c["original_line"] as? Int), state: nil, date: date(c["created_at"]))
        }
    }

    /// GitLab `.../merge_requests/N/notes`
    public static func parseGitLabNotes(_ text: String) -> [ReviewComment] {
        objects(text).filter { ($0["system"] as? Bool) != true }.enumerated().map { i, n in
            let position = n["position"] as? [String: Any]
            return ReviewComment(id: "n\(n["id"] as? Int ?? i)", kind: position == nil ? .comment : .inline,
                                 author: login(n["author"]), body: n["body"] as? String ?? "",
                                 path: position?["new_path"] as? String, line: position?["new_line"] as? Int,
                                 state: nil, date: date(n["created_at"]))
        }.sorted { $0.date < $1.date }
    }
}

public enum MergeMethod: String, CaseIterable, Identifiable, Sendable {
    case squash, merge, rebase
    public var id: String { rawValue }
}

public enum ReviewVerdict: String, Sendable { case approve, requestChanges, comment }

public struct ForgeError: Error, LocalizedError, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Talks to a forge through its official CLI, which already owns authentication.
public final class ForgeClient: @unchecked Sendable {
    public let kind: ForgeKind
    public let root: URL
    public init(kind: ForgeKind, root: URL) { self.kind = kind; self.root = root }

    @discardableResult
    func cli(_ arguments: [String]) async throws -> String {
        let kind = self.kind, root = self.root
        return try await Task.detached(priority: .userInitiated) {
            guard let exe = ProcessRunner.resolve(kind.cli) else {
                throw ForgeError(message: "La commande « \(kind.cli) » est introuvable. Installe-la (brew install \(kind == .github ? "gh" : "glab")) puis connecte-toi.")
            }
            let out = try ProcessRunner.run(executable: exe, arguments: arguments, directory: root, timeout: 60)
            guard out.status == 0 else {
                let msg = out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ForgeError(message: msg.isEmpty ? "\(kind.cli) a échoué (code \(out.status))" : msg)
            }
            return out.stdout
        }.value
    }

    public func list() async throws -> [ReviewRequest] {
        switch kind {
        case .github:
            return ForgeParsing.parseGitHubList(try await cli(["pr", "list", "--state", "open", "--limit", "50", "--json", ForgeParsing.githubListFields]))
        case .gitlab:
            return ForgeParsing.parseGitLabList(try await cli(["mr", "list", "-F", "json", "--per-page", "50"]))
        }
    }

    public func diff(_ number: Int) async throws -> String {
        switch kind {
        case .github: try await cli(["pr", "diff", String(number), "--color=never"])
        case .gitlab: try await cli(["mr", "diff", String(number), "--color=never"])
        }
    }

    public func discussion(_ number: Int) async throws -> [ReviewComment] {
        switch kind {
        case .github:
            let main = ForgeParsing.parseGitHubDiscussion(try await cli(["pr", "view", String(number), "--json", "comments,reviews"]))
            let inline = ForgeParsing.parseGitHubInline(try await cli(["api", "repos/{owner}/{repo}/pulls/\(number)/comments", "--paginate"]))
            return (main + inline).sorted { $0.date < $1.date }
        case .gitlab:
            return ForgeParsing.parseGitLabNotes(try await cli(["api", "projects/:id/merge_requests/\(number)/notes"]))
        }
    }

    public func comment(_ number: Int, body: String) async throws {
        switch kind {
        case .github: try await cli(["pr", "comment", String(number), "--body", body])
        case .gitlab: try await cli(["mr", "note", String(number), "--message", body])
        }
    }

    public func review(_ number: Int, verdict: ReviewVerdict, body: String) async throws {
        switch kind {
        case .github:
            let flag = ["approve": "--approve", "requestChanges": "--request-changes", "comment": "--comment"][verdict.rawValue]!
            var args = ["pr", "review", String(number), flag]
            if !body.isEmpty { args += ["--body", body] }
            try await cli(args)
        case .gitlab:
            if verdict == .approve { try await cli(["mr", "approve", String(number)]) }
            if !body.isEmpty || verdict != .approve { try await cli(["mr", "note", String(number), "--message", body]) }
        }
    }

    public func merge(_ number: Int, method: MergeMethod, deleteBranch: Bool) async throws {
        switch kind {
        case .github:
            var args = ["pr", "merge", String(number), "--\(method.rawValue)"]
            if deleteBranch { args.append("--delete-branch") }
            try await cli(args)
        case .gitlab:
            var args = ["mr", "merge", String(number), "--yes"]
            if method == .squash { args.append("--squash") }
            if method == .rebase { args.append("--rebase") }
            if deleteBranch { args.append("--remove-source-branch") }
            try await cli(args)
        }
    }

    public func checkout(_ number: Int) async throws {
        switch kind {
        case .github: try await cli(["pr", "checkout", String(number)])
        case .gitlab: try await cli(["mr", "checkout", String(number)])
        }
    }
}

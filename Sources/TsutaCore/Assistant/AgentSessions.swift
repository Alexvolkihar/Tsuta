import Foundation

/// A coding-agent conversation (Claude Code or Codex) that worked inside a repository.
public struct AgentSession: Identifiable, Hashable, Sendable {
    public enum Agent: String, Sendable { case claudeCode, codex }

    public let id: String
    public let agent: Agent
    public let title: String
    public let directory: String
    public let branch: String?
    public let lastActivity: Date
    public let messageCount: Int

    public var agentName: String { agent == .claudeCode ? "Claude Code" : "Codex" }

    /// Shell command that resumes the conversation from its own directory.
    public var resumeCommand: String {
        switch agent {
        case .claudeCode: "claude --resume \(id)"
        case .codex: "codex resume \(id)"
        }
    }
}

/// Reads the sessions the agents keep on disk; nothing is sent anywhere.
public enum AgentSessionScanner {
    public static var defaultClaudeProjects: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects") }
    public static var defaultCodexSessions: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions") }

    /// Claude Code names a project folder after its path, with `/` and `.` turned into `-`.
    public static func claudeFolderName(for path: String) -> String {
        path.map { $0 == "/" || $0 == "." ? "-" : String($0) }.joined()
    }

    public static func sessions(directories: [String], limit: Int = 40,
                                claudeProjects: URL = defaultClaudeProjects,
                                codexSessions: URL = defaultCodexSessions) -> [AgentSession] {
        var result = directories.flatMap { claudeSessions(in: $0, projects: claudeProjects, limit: limit) }
        result += codexSessionsMatching(directories: Set(directories), root: codexSessions, limit: limit)
        return result.sorted { $0.lastActivity > $1.lastActivity }.prefix(limit).map { $0 }
    }

    // MARK: Claude Code

    static func claudeSessions(in directory: String, projects: URL, limit: Int) -> [AgentSession] {
        let folder = projects.appendingPathComponent(claudeFolderName(for: directory))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        let files = names.filter { $0.hasSuffix(".jsonl") }.compactMap { name -> (URL, Date)? in
            let url = folder.appendingPathComponent(name)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url, date)
        }
        return files.sorted { $0.1 > $1.1 }.prefix(limit).compactMap { parseClaude(file: $0.0, modified: $0.1, directory: directory) }
    }

    static func parseClaude(file: URL, modified: Date, directory: String) -> AgentSession? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        var title: String?
        var firstPrompt: String?
        var branch: String?
        var messages = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if raw.contains("\"type\":\"ai-title\"") {
                if let o = object(raw), let t = o["aiTitle"] as? String, !t.isEmpty { title = t }
            } else if raw.contains("\"type\":\"user\"") {
                guard let o = object(raw), (o["isSidechain"] as? Bool) != true else { continue }
                messages += 1
                if branch == nil, let b = o["gitBranch"] as? String, b != "HEAD" { branch = b }
                if firstPrompt == nil, let t = userText(o), !t.hasPrefix("<") { firstPrompt = t }
            }
        }
        guard messages > 0 else { return nil }
        let name = (title ?? firstPrompt ?? "Session sans titre").replacingOccurrences(of: "\n", with: " ")
        return AgentSession(id: file.deletingPathExtension().lastPathComponent, agent: .claudeCode,
                            title: String(name.prefix(120)), directory: directory, branch: branch,
                            lastActivity: modified, messageCount: messages)
    }

    private static func object(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func userText(_ o: [String: Any]) -> String? {
        guard let message = o["message"] as? [String: Any] else { return nil }
        if let s = message["content"] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let blocks = message["content"] as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: Codex  (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, first line = session_meta)

    static func codexSessionsMatching(directories: Set<String>, root: URL, limit: Int) -> [AgentSession] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var candidates: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            candidates.append((url, date))
        }
        var result: [AgentSession] = []
        for (url, date) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(400) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = handle.readData(ofLength: 16_384)
            try? handle.close()
            let firstLine = String(decoding: head, as: UTF8.self).split(separator: "\n", maxSplits: 1).first
            guard let line = firstLine, let o = object(line),
                  let payload = (o["payload"] as? [String: Any]) ?? o as [String: Any]?,
                  let cwd = payload["cwd"] as? String, directories.contains(cwd),
                  let id = payload["id"] as? String else { continue }
            let preview = (payload["instructions"] as? String).map { String($0.prefix(80)) } ?? "Session Codex"
            result.append(AgentSession(id: id, agent: .codex, title: preview, directory: cwd, branch: nil,
                                       lastActivity: date, messageCount: 0))
            if result.count >= limit { break }
        }
        return result
    }
}

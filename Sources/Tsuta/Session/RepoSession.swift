import AppKit
import TsutaCore
import Observation

/// Everything about one open repository. Feature code lives in `RepoSession+*.swift`;
/// reviews and the assistant are separate models so this type stays about repository state.
@MainActor
@Observable
final class RepoSession: Identifiable {
    enum Mode: String, CaseIterable, Identifiable {
        case history, changes, reviews, agents
        var id: String { rawValue }
        var title: String {
            switch self {
            case .history: "Historique"
            case .changes: "Changements"
            case .reviews: "Reviews"
            case .agents: "Agents"
            }
        }
        var symbol: String {
            switch self {
            case .history: "point.3.connected.trianglepath.dotted"
            case .changes: "square.and.pencil"
            case .reviews: "text.bubble"
            case .agents: "sparkles"
            }
        }
    }

    struct BranchDrop: Identifiable {
        let id = UUID()
        let source: String
        let target: BranchInfo
    }

    nonisolated let id = UUID()
    let root: URL
    let name: String
    let git: GitClient
    let settings: AppSettings
    let reviews: ReviewsModel
    let assistant: AssistantModel

    // Repository state
    private(set) var commits: [Commit] = []
    private(set) var rows: [GraphRow] = []
    private(set) var laneCount = 1
    private(set) var branches: [BranchInfo] = []
    private(set) var status = RepoStatus()
    private(set) var operation: RepoOperation = .none
    private(set) var stashes: [StashEntry] = []
    private(set) var worktrees: [Worktree] = []
    private(set) var submodules: [SubmoduleInfo] = []
    private(set) var remoteURL: String?
    private(set) var forge: ForgeKind?
    private(set) var isLoading = false
    var isBusy = false

    // Navigation and selection
    var mode: Mode = .history
    var filter = HistoryFilter()
    var selectedCommitID: String?
    private(set) var commitBody = ""
    var selectedChangeID: String?
    var selectedChangeStaged = false
    private(set) var diff: [DiffFile] = []
    var commitMessage = ""

    // Presentation
    var errorMessage: String?
    var showConsole = false
    private(set) var console: [GitCommandRecord] = []
    func consoleReset() { console.removeAll() }
    var rebasePlan: RebasePlan?
    var editingConflict: FileChange?
    var showNewWorktree = false
    var pendingDrop: BranchDrop?
    var undoStack: [UndoEntry] = []
    var operationOrigin: (title: String, snapshot: HeadSnapshot, mode: GitClient.RestoreMode)?
    var inspectedFile: InspectedFile?

    struct InspectedFile: Identifiable {
        let id = UUID()
        let path: String
        /// Blame as of this commit; nil blames the working tree.
        var revision: String?
    }

    struct RebasePlan: Identifiable {
        let id = UUID()
        let base: String?
        var entries: [RebaseEntry]
    }

    private var watcher: RepositoryWatcher?
    private var refreshTask: Task<Void, Never>?
    private var autoFetchTask: Task<Void, Never>?
    private var knownRemotes: Set<String> = []

    var selectedCommit: Commit? { commits.first { $0.id == selectedCommitID } }
    var visibleCommits: [Commit] { filter.apply(to: commits) }
    var currentBranch: BranchInfo? { branches.first { $0.isCurrent } }
    var hasConflicts: Bool { status.changes.contains(where: \.isConflicted) }

    private final class Relay: @unchecked Sendable { var handler: (@Sendable (GitCommandRecord) -> Void)? }

    init(root: URL, settings: AppSettings) {
        self.root = root
        self.name = root.lastPathComponent
        self.settings = settings
        let relay = Relay()
        let client = GitClient(root: root) { relay.handler?($0) }
        git = client
        reviews = ReviewsModel(root: root)
        assistant = AssistantModel(git: client, settings: settings)
        relay.handler = { [weak self] record in
            Task { @MainActor in self?.record(record) }
        }
        reviews.onError = { [weak self] in self?.errorMessage = $0 }
        reviews.onRepositoryChanged = { [weak self] in await self?.refresh() }
        assistant.onError = { [weak self] in self?.errorMessage = $0 }
        assistant.directories = { [weak self] in
            guard let self else { return [] }
            return Array(Set([self.root.path] + self.worktrees.map(\.path)))
        }
    }

    private func record(_ record: GitCommandRecord) {
        console.append(record)
        if console.count > 300 { console.removeFirst(console.count - 300) }
    }

    // MARK: Lifecycle

    func load() async {
        isLoading = true
        await refresh()
        isLoading = false
        if selectedCommitID == nil, let first = commits.first { await select(commit: first.id) }
        startWatching()
    }

    private func startWatching() {
        watcher = RepositoryWatcher(root: root) { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        autoFetchTask?.cancel()
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.settings.autoFetchMinutes > 0 else { continue }
                try? await Task.sleep(for: .seconds(Double(self.settings.autoFetchMinutes) * 60 - 60))
                if !self.isBusy { _ = try? await self.git.run(["fetch", "--all", "--prune", "--quiet"]); await self.refresh() }
            }
        }
    }

    /// Coalesces bursts of file events into a single refresh.
    func scheduleRefresh() {
        guard !isBusy else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        do {
            async let remoteOut = git.run(["remote"])
            async let statusOut = git.run(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"])
            async let branchOut = git.run(["for-each-ref", GitParsing.branchFormat, "refs/heads", "refs/remotes"])
            async let stashOut = git.run(["stash", "list", GitLists.stashFormat])
            async let worktreeOut = git.run(["worktree", "list", "--porcelain"])
            async let submoduleOut = git.run(["submodule", "status"], allowedStatuses: [0, 128])
            async let urlOut = git.run(["remote", "get-url", "origin"], allowedStatuses: [0, 2, 128])
            async let logOut = git.run(["log", "--all", "--date-order", "-n", String(settings.commitLimit), GitParsing.logFormat],
                                       allowedStatuses: [0, 128])

            knownRemotes = Set(try await remoteOut.split(separator: "\n").map(String.init))
            status = GitParsing.parseStatus(try await statusOut)
            branches = GitParsing.parseBranches(try await branchOut)
            stashes = GitLists.parseStashes(try await stashOut)
            worktrees = GitLists.parseWorktrees(try await worktreeOut)
            submodules = GitParsing.parseSubmodules(try await submoduleOut)
            let url = try await urlOut.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteURL = url.isEmpty ? nil : url
            forge = remoteURL.flatMap { ForgeKind.detect(remoteURL: $0) }
            reviews.configure(forge: forge, remoteURL: remoteURL)
            operation = await git.currentOperation()
            if operation == .none { await finishPausedOperation() }

            commits = GitParsing.parseLog(try await logOut, remotes: knownRemotes)
            rows = GraphLayout.build(commits)
            laneCount = max(1, rows.map(\.laneCount).max() ?? 1)
            await reloadDiff()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Navigation

    func select(commit id: String) async {
        selectedCommitID = id
        await reloadDiff()
    }

    func select(change: FileChange, staged: Bool) async {
        selectedChangeID = change.id
        selectedChangeStaged = staged
        await reloadDiff()
    }

    func setMode(_ mode: Mode) async {
        self.mode = mode
        switch mode {
        case .history, .changes: await reloadDiff()
        case .reviews: await reviews.load()
        case .agents: await assistant.loadSessions()
        }
    }

    var diffArguments: [String] {
        ["--no-ext-diff", "--no-textconv", "--no-color"] + (settings.hideWhitespaceChanges ? ["--ignore-all-space"] : [])
    }

    /// Hunk/line staging relies on patches git can re-apply, which excludes whitespace-insensitive diffs.
    var canStagePartially: Bool { !settings.hideWhitespaceChanges }

    func reloadDiff() async {
        do {
            switch mode {
            case .history:
                guard let id = selectedCommitID else { diff = []; commitBody = ""; return }
                async let patch = git.run(["show", "--format=", "--patch", "--diff-merges=first-parent"] + diffArguments + [id])
                async let body = git.run(["show", "-s", "--format=%b", id])
                diff = GitParsing.parseDiff(try await patch)
                commitBody = try await body.trimmingCharacters(in: .whitespacesAndNewlines)
            case .changes:
                guard let id = selectedChangeID, let change = status.changes.first(where: { $0.id == id }) else { diff = []; return }
                if change.isUntracked {
                    let out = try await git.run(["diff", "--no-index"] + diffArguments + ["--", "/dev/null", change.path], allowedStatuses: [0, 1])
                    diff = GitParsing.parseDiff(out)
                } else {
                    let cached = selectedChangeStaged ? ["--cached"] : []
                    diff = GitParsing.parseDiff(try await git.run(["diff"] + cached + diffArguments + ["--", change.path]))
                }
            case .reviews, .agents:
                break
            }
        } catch {
            diff = []
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Mutations

    /// Runs a git mutation with a busy flag, surfaces errors, then refreshes.
    func perform(_ work: (GitClient) async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do { try await work(git) } catch { errorMessage = error.localizedDescription }
        await refresh()
    }
}

import AppKit
import HankoCore
import Observation

/// Root model: the open repositories (tabs), recents and preferences.
@MainActor
@Observable
final class AppModel {
    private(set) var sessions: [RepoSession] = []
    var activeID: RepoSession.ID?
    private(set) var recent: [URL] = []
    let settings = AppSettings()
    var showPalette = false
    var notice: String?

    private static let recentKey = "recentRepositories"
    private static let openKey = "openRepositories"

    var active: RepoSession? { sessions.first { $0.id == activeID } }

    private let options = LaunchOptions.current

    init() {
        if let zoom = options.zoom { settings.zoom = zoom }
        if let repository = options.repository {
            // Scripted launch (screenshots): open exactly this repository and leave saved state alone.
            Task {
                await open(repository)
                await applyLaunchOptions()
            }
            return
        }
        recent = (UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let previous = (UserDefaults.standard.stringArray(forKey: Self.openKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        Task { for url in previous { await open(url) } }
    }

    private func applyLaunchOptions() async {
        guard let session = active else { return }
        if let mode = options.mode { await session.setMode(mode) }
        if options.selectFirstChange, let change = session.status.changes.first(where: { !$0.isConflicted }) {
            await session.select(change: change, staged: change.isStaged)
        }
        if let path = options.selectChange, let change = session.status.changes.first(where: { $0.path == path }) {
            await session.select(change: change, staged: change.isStaged && !change.isUnstaged)
        }
        if let number = options.selectReview { await session.reviews.select(number) }
        session.showConsole = options.showConsole
        showPalette = options.openPalette
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ouvrir"
        panel.message = "Choisis un dossier contenant un dépôt Git"
        if panel.runModal() == .OK, let url = panel.url { Task { await open(url) } }
    }

    func open(_ url: URL) async {
        guard let root = await Task.detached(operation: { GitClient.topLevel(of: url) }).value else {
            notice = "« \(url.lastPathComponent) » n’est pas un dépôt Git."
            return
        }
        if let existing = sessions.first(where: { $0.root == root }) {
            activeID = existing.id
            return
        }
        let session = RepoSession(root: root, settings: settings)
        sessions.append(session)
        activeID = session.id
        if !options.isSnapshot {
            remember(root)
            persistOpen()
        }
        await session.load()
    }

    func close(_ session: RepoSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        if activeID == session.id { activeID = sessions[safe: min(index, sessions.count - 1)]?.id }
        persistOpen()
    }

    func select(offset: Int) {
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.id == activeID }) else { return }
        activeID = sessions[(index + offset + sessions.count) % sessions.count].id
    }

    private func remember(_ url: URL) {
        recent.removeAll { $0 == url }
        recent.insert(url, at: 0)
        recent = Array(recent.prefix(10))
        UserDefaults.standard.set(recent.map(\.path), forKey: Self.recentKey)
    }

    private func persistOpen() {
        UserDefaults.standard.set(sessions.map(\.root.path), forKey: Self.openKey)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

import TsutaCore
import SwiftUI

struct SidebarView: View {
    let session: RepoSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                branches
                remotes
                stashes
                worktrees
                if !session.submodules.isEmpty { submodules }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: Sections

    private var branches: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title: "Branches", count: session.branches.filter { !$0.isRemote }.count).padding(.bottom, 4)
            ForEach(session.branches.filter { !$0.isRemote }) { branch in
                BranchRow(session: session, branch: branch)
            }
        }
    }

    @ViewBuilder
    private var remotes: some View {
        let remote = session.branches.filter(\.isRemote)
        if !remote.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(title: "Distantes", count: remote.count).padding(.bottom, 4)
                ForEach(remote) { branch in BranchRow(session: session, branch: branch) }
            }
        }
    }

    private var stashes: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title: "Stashes", count: session.stashes.count).padding(.bottom, 4)
            if session.stashes.isEmpty { Text("Aucun").ui(12).foregroundStyle(.tertiary).padding(.leading, 4) }
            ForEach(session.stashes) { stash in
                SidebarRow(symbol: "tray.full", title: stash.message, subtitle: stash.date.formatted(.relative(presentation: .named)))
                    .contextMenu {
                        Button("Appliquer") { Task { await session.stashApply(stash) } }
                        Button("Appliquer et supprimer (pop)") { Task { await session.stashPop(stash) } }
                        Divider()
                        Button("Supprimer", role: .destructive) { Task { await session.stashDrop(stash) } }
                    }
            }
        }
    }

    private var worktrees: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel(title: "Worktrees", count: session.worktrees.count)
                IconButton(symbol: "plus", help: "Nouveau worktree") { session.showNewWorktree = true }
            }
            .padding(.bottom, 4)
            ForEach(session.worktrees) { tree in
                let agents = session.assistant.sessions(in: tree.path).count
                SidebarRow(symbol: tree.isMain ? "folder.fill" : "folder", title: tree.displayName,
                           subtitle: (tree.path as NSString).abbreviatingWithTildeInPath, trailing: agents)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { Task { await NSApp.openRepository(URL(fileURLWithPath: tree.path)) } }
                    .contextMenu {
                        Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tree.path)]) }
                        Button("Lancer Claude Code ici") { session.assistant.startNewSession(agent: .claudeCode, in: tree.path) }
                            .disabled(!AIBackend.claude.isAvailable)
                        Button("Lancer Codex ici") { session.assistant.startNewSession(agent: .codex, in: tree.path) }
                            .disabled(!AIBackend.codex.isAvailable)
                        if !tree.isMain {
                            Divider()
                            Button("Supprimer", role: .destructive) { Task { await session.removeWorktree(tree) } }
                        }
                    }
            }
        }
    }

    private var submodules: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title: "Sous-modules", count: session.submodules.count).padding(.bottom, 4)
            ForEach(session.submodules) { module in
                SidebarRow(symbol: symbol(module.state), title: module.path, subtitle: module.describe ?? String(module.commit.prefix(8)))
                    .contextMenu {
                        Button(module.state == .uninitialized ? "Initialiser" : "Mettre à jour") { Task { await session.updateSubmodule(module) } }
                        Button("Afficher dans le Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([session.submoduleURL(module)])
                        }
                    }
            }
        }
    }

    private func symbol(_ state: SubmoduleInfo.State) -> String {
        switch state {
        case .upToDate: "shippingbox"
        case .uninitialized: "shippingbox.circle"
        case .modified: "shippingbox.fill"
        case .conflicted: "exclamationmark.triangle"
        }
    }
}

private struct SidebarRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var trailing = 0
    var isCurrent = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).ui(11.5).foregroundStyle(isCurrent ? Theme.accent : .secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).ui(12.5, isCurrent ? .semibold : .regular).lineLimit(1).truncationMode(.middle)
                if let subtitle { Text(subtitle).ui(10.5).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head) }
            }
            Spacer(minLength: 0)
            if trailing > 0 {
                HStack(spacing: 2) { Image(systemName: "sparkles"); Text("\(trailing)") }
                    .ui(10, .semibold).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(isCurrent ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct BranchRow: View {
    let session: RepoSession
    let branch: BranchInfo

    var body: some View {
        SidebarRow(symbol: branch.isRemote ? "cloud" : (branch.isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch"),
                   title: branch.name, subtitle: branch.upstream, isCurrent: branch.isCurrent)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if !branch.isCurrent { Task { await session.checkout(branch) } } }
            .draggable(branch.name)
            .dropDestination(for: String.self) { items, _ in
                guard let source = items.first, source != branch.name, !branch.isRemote else { return false }
                session.pendingDrop = .init(source: source, target: branch)
                return true
            }
            .contextMenu {
                Button("Basculer sur cette branche") { Task { await session.checkout(branch) } }.disabled(branch.isCurrent)
                if !branch.isRemote && !branch.isCurrent {
                    Button("Fusionner dans la branche courante") { Task { await session.merge(branch.name) } }
                    Divider()
                    Button("Supprimer", role: .destructive) { Task { await session.deleteBranch(branch, force: false) } }
                }
            }
    }
}

extension NSApplication {
    /// Opens a repository from anywhere in the view tree without threading AppModel through it.
    @MainActor
    func openRepository(_ url: URL) async {
        NotificationCenter.default.post(name: .tsutaOpenRepository, object: url)
    }
}

extension Notification.Name {
    static let tsutaOpenRepository = Notification.Name("tsuta.openRepository")
}

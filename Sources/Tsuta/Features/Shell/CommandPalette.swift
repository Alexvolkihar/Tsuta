import TsutaCore
import SwiftUI

@MainActor
final class PaletteModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
}

struct PaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let run: () async -> Void
}

/// ⌘K: one search box for actions, branches, commits and recent repositories.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = PaletteModel()
    @FocusState private var focused: Bool

    var body: some View {
        let results = items()
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher une action, une branche, un commit…", text: $state.query)
                    .textFieldStyle(.plain)
                    .ui(15)
                    .focused($focused)
                    .onSubmit { run(results) }
            }
            .padding(14)
            Divider()
            if results.isEmpty {
                Text("Aucun résultat").ui(12.5).foregroundStyle(.secondary).padding(30)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                HStack(spacing: 10) {
                                    Image(systemName: item.symbol).frame(width: 20).foregroundStyle(Theme.accent)
                                    Text(item.title).ui(13).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(item.subtitle).ui(11.5).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(index == state.selection ? Theme.accent.opacity(0.18) : .clear)
                                .contentShape(Rectangle())
                                .id(index)
                                .onTapGesture { state.selection = index; run(results) }
                            }
                        }
                    }
                    .onChange(of: state.selection) { proxy.scrollTo(state.selection) }
                }
            }
        }
        .frame(width: 600, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { focused = true }
        .onChange(of: state.query) { state.selection = 0 }
        .onKeyPress(.downArrow) { state.selection = min(state.selection + 1, max(0, items().count - 1)); return .handled }
        .onKeyPress(.upArrow) { state.selection = max(state.selection - 1, 0); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(state.selection) else { return }
        let item = results[state.selection]
        dismiss()
        Task { await item.run() }
    }

    // MARK: Content

    private func items() -> [PaletteItem] {
        let query = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        var all = actions()
        if let session = model.active {
            all += session.branches.map { branch in
                PaletteItem(title: branch.name, subtitle: branch.isCurrent ? "branche courante" : (branch.isRemote ? "branche distante" : "basculer"),
                            symbol: branch.isRemote ? "cloud" : "arrow.triangle.branch") { await session.checkout(branch) }
            }
            if query.count >= 2 {
                all += session.commits.lazy.filter { $0.subject.lowercased().contains(query) || $0.shortID.hasPrefix(query) || $0.author.lowercased().contains(query) }
                    .prefix(30).map { commit in
                        PaletteItem(title: commit.subject, subtitle: "\(commit.shortID) · \(commit.author)", symbol: "circle.dotted") {
                            await session.setMode(.history)
                            await session.select(commit: commit.id)
                        }
                    }
            }
        }
        all += model.recent.map { url in
            PaletteItem(title: url.lastPathComponent, subtitle: "ouvrir le dépôt", symbol: "folder") { await model.open(url) }
        }
        guard !query.isEmpty else { return Array(all.prefix(40)) }
        return all.filter { ($0.title + " " + $0.subtitle).lowercased().contains(query) }
    }

    private func actions() -> [PaletteItem] {
        var list = [PaletteItem(title: "Ouvrir un dépôt…", subtitle: "⌘O", symbol: "folder.badge.plus") { model.chooseRepository() }]
        list.append(PaletteItem(title: "Agrandir l’interface", subtitle: "⌘+", symbol: "plus.magnifyingglass") { model.settings.zoomIn() })
        list.append(PaletteItem(title: "Réduire l’interface", subtitle: "⌘-", symbol: "minus.magnifyingglass") { model.settings.zoomOut() })
        guard let s = model.active else { return list }
        list += [
            PaletteItem(title: "Fetch", subtitle: "récupérer les remotes", symbol: "arrow.triangle.2.circlepath") { await s.fetch() },
            PaletteItem(title: "Pull", subtitle: "tirer la branche courante", symbol: "arrow.down.to.line") { await s.pull() },
            PaletteItem(title: "Push", subtitle: "pousser la branche courante", symbol: "arrow.up.to.line") { await s.push() },
            PaletteItem(title: "Actualiser", subtitle: "⌘R", symbol: "arrow.clockwise") { await s.refresh() },
            PaletteItem(title: "Indexer tous les fichiers", subtitle: "git add -A", symbol: "plus.circle") { await s.stageAll() },
            PaletteItem(title: "Nouveau worktree…", subtitle: "", symbol: "folder.badge.plus") { s.showNewWorktree = true },
            PaletteItem(title: "Afficher la console Git", subtitle: "⌘J", symbol: "terminal") { s.showConsole.toggle() },
        ]
        for mode in RepoSession.Mode.allCases {
            list.append(PaletteItem(title: "Aller à : \(mode.title)", subtitle: "", symbol: mode.symbol) { await s.setMode(mode) })
        }
        if let undo = s.undoTitle {
            list.append(PaletteItem(title: undo, subtitle: "⌥⌘Z", symbol: "arrow.uturn.backward") { await s.undo() })
        }
        return list
    }
}

import SwiftUI
import TsutaCore

@MainActor
final class FileInspectorModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case blame = "Blame", history = "Historique"
        var id: String { rawValue }
    }

    @Published var tab: Tab = .blame
    @Published var blame: [BlameLine] = []
    @Published var history: [FileHistoryEntry] = []
    @Published var selected: FileHistoryEntry?
    @Published var patch: [DiffFile] = []
    @Published var isLoading = true
    @Published var error: String?

    /// Consecutive lines from the same commit are shown as one block with a single label.
    var blockStarts: Set<Int> {
        var starts: Set<Int> = []
        var previous: String?
        for line in blame {
            if line.commit != previous { starts.insert(line.number) }
            previous = line.commit
        }
        return starts
    }

    func load(git: GitClient, path: String, revision: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let lines = git.blame(path: path, revision: revision)
            async let entries = git.fileHistory(path: path)
            blame = try await lines
            history = try await entries
        } catch {
            self.error = error.localizedDescription
        }
        if let first = history.first { await select(first, git: git) }
    }

    func select(_ entry: FileHistoryEntry, git: GitClient) async {
        selected = entry
        patch = (try? await git.filePatch(commit: entry.commit.id, path: entry.path)) ?? []
    }
}

/// Blame and history of one file, following renames.
struct FileInspectorSheet: View {
    let session: RepoSession
    let file: RepoSession.InspectedFile
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = FileInspectorModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.accent)
                Text(file.path).ui(14, .semibold).lineLimit(1).truncationMode(.middle)
                if let revision = file.revision {
                    Text("@ \(String(revision.prefix(7)))").ui(11.5, mono: true).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $model.tab) {
                    ForEach(FileInspectorModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error {
                EmptyState(symbol: "exclamationmark.triangle", title: "Impossible de lire ce fichier", message: error)
            } else {
                switch model.tab {
                case .blame: BlameView(model: model, open: openCommit)
                case .history: HistoryTab(model: model, session: session)
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            if LaunchOptions.current.inspectTab == "history" { model.tab = .history }
            await model.load(git: session.git, path: file.path, revision: file.revision)
        }
    }

    private func openCommit(_ sha: String) {
        dismiss()
        Task {
            await session.setMode(.history)
            if session.commits.contains(where: { $0.id == sha }) {
                await session.select(commit: sha)
            } else {
                session.errorMessage = "Ce commit est plus ancien que les \(session.settings.commitLimit) derniers chargés (Réglages)."
            }
        }
    }
}

private struct BlameView: View {
    @ObservedObject var model: FileInspectorModel
    let open: (String) -> Void

    var body: some View {
        if model.blame.isEmpty {
            EmptyState(symbol: "doc", title: "Fichier vide", message: "Il n’y a aucune ligne à afficher.")
        } else {
            let starts = model.blockStarts
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.blame) { line in
                        BlameRow(line: line, showsMeta: starts.contains(line.number), open: open)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct BlameRow: View {
    let line: BlameLine
    let showsMeta: Bool
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(line.isUncommitted ? Color.orange : Theme.avatarColor(for: line.commit))
                .frame(width: 3)
            Group {
                if showsMeta {
                    HStack(spacing: 6) {
                        if line.isUncommitted {
                            Text("Non commité").ui(11.5).foregroundStyle(.orange)
                        } else {
                            Text(line.shortCommit).ui(11, mono: true).foregroundStyle(.secondary)
                            Text(line.author).ui(11.5, .medium).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(line.date.formatted(.relative(presentation: .named)))
                                .ui(10.5).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    .help(line.summary)
                    .contentShape(Rectangle())
                    .onTapGesture { if !line.isUncommitted { open(line.commit) } }
                } else {
                    Color.clear
                }
            }
            .frame(width: 290, alignment: .leading)
            .padding(.horizontal, 8)
            Text("\(line.number)").ui(11, mono: true).foregroundStyle(.tertiary).frame(width: 44, alignment: .trailing)
            Text(line.text.isEmpty ? " " : line.text).ui(12, mono: true).textSelection(.enabled).padding(.leading, 10)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(showsMeta ? Color.primary.opacity(0.035) : .clear)
    }
}

private struct HistoryTab: View {
    @ObservedObject var model: FileInspectorModel
    let session: RepoSession

    var body: some View {
        if model.history.isEmpty {
            EmptyState(symbol: "clock", title: "Aucun commit", message: "Ce fichier n’a pas d’historique.")
        } else {
            HSplitView {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.history) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                AvatarView(name: entry.commit.author, email: entry.commit.email, size: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.commit.subject).ui(12.5, .medium).lineLimit(2)
                                    Text("\(entry.commit.author) · \(entry.commit.date.formatted(.relative(presentation: .named)))")
                                        .ui(11).foregroundStyle(.secondary).lineLimit(1)
                                    if entry.path != model.history.first?.path {
                                        Text(entry.path).ui(10.5, mono: true).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                Text(entry.commit.shortID).ui(10.5, mono: true).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(model.selected?.id == entry.id ? Theme.accent.opacity(0.2) : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture { Task { await model.select(entry, git: session.git) } }
                        }
                    }
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
                DiffView(files: model.patch).frame(minWidth: 460)
            }
        }
    }
}

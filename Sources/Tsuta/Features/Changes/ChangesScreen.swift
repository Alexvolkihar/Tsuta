import TsutaCore
import SwiftUI

struct ChangesScreen: View {
    let session: RepoSession

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ChangeList(session: session)
                Divider()
                CommitComposer(session: session)
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)

            DiffView(files: session.diff, staging: staging)
                .frame(minWidth: 380)
                .overlay(alignment: .top) {
                    if !session.canStagePartially {
                        Text("Indexation partielle désactivée : les changements d’espaces sont masqués (Réglages).")
                            .ui(11.5).padding(6).background(.thinMaterial, in: Capsule()).padding(8)
                    }
                }
        }
    }

    private var staging: StagingContext? {
        guard session.canStagePartially, let id = session.selectedChangeID,
              let change = session.status.changes.first(where: { $0.id == id }), !change.isUntracked, !change.isConflicted else { return nil }
        let staged = session.selectedChangeStaged
        return StagingContext(
            staged: staged,
            onHunk: { hunk, file in Task { await session.applyPartial(hunk: hunk, in: file, staged: staged) } },
            onLines: { file, ids in Task { await session.applyPartial(file: file, selected: ids, staged: staged) } })
    }
}

private struct ChangeList: View {
    let session: RepoSession

    var body: some View {
        let conflicts = session.status.changes.filter(\.isConflicted)
        let unstaged = session.status.unstaged.filter { !$0.isConflicted }
        if session.status.changes.isEmpty {
            EmptyState(symbol: "checkmark.circle", title: "Rien à valider", message: "L’arbre de travail est propre.")
        } else {
            List {
                if !conflicts.isEmpty {
                    Section {
                        ForEach(conflicts) { ConflictRow(session: session, change: $0) }
                    } header: { SectionLabel(title: "Conflits", count: conflicts.count) }
                }
                Section {
                    ForEach(session.status.staged) { ChangeRow(session: session, change: $0, staged: true) }
                } header: { SectionLabel(title: "Indexés", count: session.status.staged.count) }
                Section {
                    ForEach(unstaged) { ChangeRow(session: session, change: $0, staged: false) }
                } header: {
                    HStack {
                        SectionLabel(title: "Modifiés", count: unstaged.count)
                        if !unstaged.isEmpty {
                            Button("Tout indexer") { Task { await session.stageAll() } }.buttonStyle(.plain).foregroundStyle(Theme.accent).ui(11, .medium)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ConflictRow: View {
    let session: RepoSession
    let change: FileChange

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).ui(11)
            Text(change.path).ui(12.5).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button("Résoudre…") { session.editingConflict = change }.buttonStyle(.borderless).ui(12)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { session.editingConflict = change }
        .contextMenu {
            Button("Garder la nôtre (ours)") { Task { await session.takeSide(change, side: "ours") } }
            Button("Prendre la leur (theirs)") { Task { await session.takeSide(change, side: "theirs") } }
        }
    }
}

private struct ChangeRow: View {
    let session: RepoSession
    let change: FileChange
    let staged: Bool

    var body: some View {
        let selected = session.selectedChangeID == change.id && session.selectedChangeStaged == staged
        HStack(spacing: 8) {
            Text(letter).ui(11, .bold, mono: true).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text((change.path as NSString).lastPathComponent).ui(12.5).lineLimit(1)
                let dir = (change.path as NSString).deletingLastPathComponent
                if !dir.isEmpty { Text(dir).ui(10.5).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
            }
            Spacer(minLength: 0)
            IconButton(symbol: staged ? "minus.circle" : "plus.circle", help: staged ? "Retirer de l’index" : "Indexer") {
                Task { staged ? await session.unstage(change) : await session.stage(change) }
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .listRowBackground(selected ? Theme.accent.opacity(0.2) : Color.clear)
        .onTapGesture { Task { await session.select(change: change, staged: staged) } }
        .contextMenu {
            if !staged {
                Button("Abandonner les modifications (annulable)", role: .destructive) { Task { await session.discard(change) } }
            }
        }
    }

    private var letter: String {
        if change.isUntracked { return "?" }
        return String(staged ? change.index : change.worktree)
    }

    private var color: Color {
        switch letter {
        case "A", "?": .green
        case "D": .red
        case "R", "C": .blue
        default: .yellow
        }
    }
}

@MainActor
final class ComposerState: ObservableObject {
    @Published var stashMessage = ""
}

private struct CommitComposer: View {
    @Bindable var session: RepoSession
    @StateObject private var local = ComposerState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $session.commitMessage)
                    .ui(13)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if session.commitMessage.isEmpty {
                    Text("Message du commit").ui(13).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 84)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Color.primary.opacity(0.1)))

            HStack {
                Button {
                    Task { if let message = await session.assistant.commitMessage() { session.commitMessage = message } }
                } label: {
                    Label("Générer", systemImage: "sparkles")
                }
                .disabled(!session.assistant.isAvailable || session.assistant.isBusy || session.status.staged.isEmpty)
                .help("Rédige un message à partir du diff indexé (\(session.assistant.backend?.title ?? "aucun outil IA"))")
                Button("Amend") { Task { await session.commit(amend: true) } }
                    .disabled(session.status.staged.isEmpty && session.commitMessage.isEmpty)
                Spacer()
                Button("Commit") { Task { await session.commit() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.status.staged.isEmpty || session.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack(spacing: 6) {
                TextField("Message du stash (optionnel)", text: $local.stashMessage).textFieldStyle(.roundedBorder).ui(12)
                Button("Mettre de côté") {
                    let message = local.stashMessage
                    local.stashMessage = ""
                    Task { await session.stashPush(message: message) }
                }
                .disabled(session.status.changes.isEmpty)
            }
        }
        .padding(12)
    }
}

import TsutaCore
import SwiftUI

@MainActor
final class RebaseModel: ObservableObject {
    @Published var entries: [RebaseEntry]
    init(entries: [RebaseEntry]) { self.entries = entries }
    var problem: String? { RebasePlanner.validate(entries) }
}

struct RebaseSheet: View {
    let session: RepoSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: RebaseModel
    private let base: String?

    init(session: RepoSession, plan: RepoSession.RebasePlan) {
        self.session = session
        _model = StateObject(wrappedValue: RebaseModel(entries: plan.entries))
        base = plan.base
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rebase interactif").ui(15, .semibold)
                Text("Glisse pour réordonner (le plus ancien en haut). Les merges sont ignorés.")
                    .ui(12).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            Divider()
            List {
                ForEach($model.entries) { $entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Picker("", selection: $entry.action) {
                                ForEach(RebaseAction.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().frame(width: 100)
                            Text(entry.shortID).ui(11.5, mono: true).foregroundStyle(.secondary)
                            Text(entry.subject).ui(13).lineLimit(1)
                                .strikethrough(entry.action == .drop)
                                .foregroundStyle(entry.action == .drop ? .secondary : .primary)
                            Spacer(minLength: 0)
                        }
                        if entry.action == .reword {
                            TextField("Nouveau message", text: $entry.newMessage)
                                .textFieldStyle(.roundedBorder).padding(.leading, 110)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { model.entries.move(fromOffsets: $0, toOffset: $1) }
            }
            Divider()
            HStack {
                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).ui(12)
                }
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lancer le rebase") {
                    let entries = model.entries, base = base
                    dismiss()
                    Task { await session.runRebase(base: base, entries: entries) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.problem != nil)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
final class WorktreeDraft: ObservableObject {
    @Published var branch = ""
}

struct NewWorktreeSheet: View {
    let session: RepoSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = WorktreeDraft()

    private var path: String {
        let safe = draft.branch.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        return session.root.deletingLastPathComponent()
            .appendingPathComponent("\(session.root.lastPathComponent)-\(safe.isEmpty ? "branche" : safe)").path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nouveau worktree").ui(15, .semibold)
            TextField("Nom de la nouvelle branche", text: $draft.branch).textFieldStyle(.roundedBorder)
            Text("Créé à côté du dépôt : \((path as NSString).abbreviatingWithTildeInPath)")
                .ui(11.5).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Créer") {
                    let branch = draft.branch.trimmingCharacters(in: .whitespaces), path = path
                    dismiss()
                    Task { await session.addWorktree(path: path, branch: branch) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.branch.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

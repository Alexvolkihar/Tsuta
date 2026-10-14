import HankoCore
import SwiftUI

/// One repository: sidebar, toolbar, the active mode and the optional Git console.
struct SessionView: View {
    let session: RepoSession

    var body: some View {
        HSplitView {
            SidebarView(session: session)
                .frame(minWidth: 210, idealWidth: 250, maxWidth: 340)
            VStack(spacing: 0) {
                SessionToolbar(session: session)
                Divider()
                if session.operation != .none { OperationBanner(session: session) }
                ModeContent(session: session)
                if session.showConsole {
                    Divider()
                    ConsoleView(session: session).frame(height: 190)
                }
            }
            .frame(minWidth: 620)
        }
        .sheet(item: Binding(get: { session.rebasePlan }, set: { session.rebasePlan = $0 })) { plan in
            RebaseSheet(session: session, plan: plan)
        }
        .sheet(isPresented: Binding(get: { session.showNewWorktree }, set: { session.showNewWorktree = $0 })) {
            NewWorktreeSheet(session: session)
        }
        .sheet(item: Binding(get: { session.editingConflict }, set: { session.editingConflict = $0 })) { change in
            ConflictEditorView(session: session, change: change)
        }
        .confirmationDialog("Que faire ?", isPresented: Binding(get: { session.pendingDrop != nil },
                                                                   set: { if !$0 { session.pendingDrop = nil } }),
                            presenting: session.pendingDrop) { drop in
            ForEach(Array(session.dropOptions(for: drop).enumerated()), id: \.offset) { _, option in
                Button(option.title) { Task { await option.run() } }
            }
        }
        .alert("Erreur Git", isPresented: Binding(get: { session.errorMessage != nil },
                                                  set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}

struct ModeContent: View {
    let session: RepoSession

    var body: some View {
        VStack(spacing: 0) {
            switch session.mode {
            case .history: HistoryScreen(session: session)
            case .changes: ChangesScreen(session: session)
            case .reviews: ReviewsScreen(session: session)
            case .agents: AgentsScreen(session: session)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session.assistant.isBusy || session.assistant.output != nil { AIPanel(assistant: session.assistant) }
        }
    }
}

struct SessionToolbar: View {
    @Environment(AppModel.self) private var model
    let session: RepoSession

    var body: some View {
        HStack(spacing: 10) {
            BranchPill(session: session)

            Picker("", selection: Binding(get: { session.mode }, set: { mode in Task { await session.setMode(mode) } })) {
                ForEach(RepoSession.Mode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)

            Spacer(minLength: 0)

            if session.isBusy { ProgressView().controlSize(.small) }
            IconButton(symbol: "arrow.triangle.2.circlepath", help: "Fetch (⇧⌘F)") { Task { await session.fetch() } }
            IconButton(symbol: "arrow.down.to.line", help: "Pull") { Task { await session.pull() } }
            IconButton(symbol: "arrow.up.to.line", help: "Push") { Task { await session.push() } }
            Divider().frame(height: 16)
            AgentMenu()
            IconButton(symbol: "terminal", help: "Console Git (⌘J)") { session.showConsole.toggle() }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}

struct BranchPill: View {
    let session: RepoSession

    var body: some View {
        Menu {
            ForEach(session.branches.filter { !$0.isRemote }) { branch in
                Button {
                    Task { await session.checkout(branch) }
                } label: {
                    Label(branch.name, systemImage: branch.isCurrent ? "checkmark" : "arrow.triangle.branch")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").ui(11, .semibold)
                Text(session.status.branch.isEmpty ? "…" : session.status.branch).ui(12.5, .semibold).lineLimit(1)
                if session.status.ahead > 0 { Text("↑\(session.status.ahead)").ui(11, .medium).foregroundStyle(Theme.accent) }
                if session.status.behind > 0 { Text("↓\(session.status.behind)").ui(11, .medium).foregroundStyle(.orange) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct AgentMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let available = AIBackend.allCases.filter(\.isAvailable)
        Menu {
            if available.isEmpty {
                Text("Aucun outil IA détecté (claude, codex)")
            }
            ForEach(available) { backend in
                Button {
                    model.settings.agent = backend
                } label: {
                    Label(backend.title, systemImage: model.settings.agent == backend ? "checkmark" : "sparkles")
                }
            }
        } label: {
            Image(systemName: "sparkles").ui(12, .medium)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Outil IA : \(model.settings.agent?.title ?? "aucun")")
    }
}

struct OperationBanner: View {
    let session: RepoSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(session.operation.title).ui(12.5, .semibold)
            if session.hasConflicts { Text("Résous les conflits pour continuer").ui(12).foregroundStyle(.secondary) }
            Spacer()
            Button("Abandonner") { Task { await session.abortOperation() } }
            Button("Continuer") { Task { await session.continueOperation() } }
                .buttonStyle(.borderedProminent)
                .disabled(session.hasConflicts)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.13))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct AIPanel: View {
    let assistant: AssistantModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(assistant.title, systemImage: "sparkles").ui(12.5, .semibold)
                Spacer()
                if let output = assistant.output {
                    Button("Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                    }
                    IconButton(symbol: "xmark", help: "Fermer") { assistant.dismissOutput() }
                }
            }
            if assistant.isBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(assistant.backend?.title ?? "IA") réfléchit…").ui(12).foregroundStyle(.secondary)
                }
            } else if let output = assistant.output {
                ScrollView { Text(output).ui(12.5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 180)
            }
        }
        .padding(12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

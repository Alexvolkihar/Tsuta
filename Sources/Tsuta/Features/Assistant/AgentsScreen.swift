import TsutaCore
import SwiftUI

/// Claude Code and Codex conversations that touched this repository or one of its worktrees.
struct AgentsScreen: View {
    let session: RepoSession

    var body: some View {
        let assistant = session.assistant
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SectionLabel(title: "Sessions d’agents", count: assistant.sessions.count)
                if assistant.isLoadingSessions { ProgressView().controlSize(.small) }
                Spacer()
                Menu {
                    ForEach(session.worktrees) { tree in
                        Section(tree.displayName) {
                            Button("Claude Code") { assistant.startNewSession(agent: .claudeCode, in: tree.path) }
                                .disabled(!AIBackend.claude.isAvailable)
                            Button("Codex") { assistant.startNewSession(agent: .codex, in: tree.path) }
                                .disabled(!AIBackend.codex.isAvailable)
                        }
                    }
                } label: {
                    Label("Nouvelle session", systemImage: "plus")
                }
                .menuStyle(.borderlessButton).fixedSize()
                IconButton(symbol: "arrow.clockwise", help: "Actualiser") { Task { await assistant.loadSessions() } }
            }
            .padding(.horizontal, 12).frame(height: 38)
            Divider()
            if assistant.sessions.isEmpty {
                EmptyState(symbol: "sparkles", title: "Aucune session",
                           message: "Les conversations Claude Code (~/.claude) et Codex (~/.codex) menées dans ce dépôt ou ses worktrees apparaîtront ici.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(assistant.sessions) { item in
                            SessionCard(session: session, item: item)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task { await assistant.loadSessions() }
    }
}

private struct SessionCard: View {
    let session: RepoSession
    let item: AgentSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.agent == .claudeCode ? "sparkle" : "chevron.left.forwardslash.chevron.right")
                .ui(14, .semibold).foregroundStyle(Theme.accent).frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).ui(13.5, .semibold).lineLimit(2)
                HStack(spacing: 8) {
                    Text(item.agentName).ui(11.5, .medium)
                    if let branch = item.branch { RefChip(label: RefLabel(name: branch, kind: .local)) }
                    Text((item.directory as NSString).lastPathComponent).ui(11.5).foregroundStyle(.secondary)
                    Text(item.lastActivity.formatted(.relative(presentation: .named))).ui(11.5).foregroundStyle(.tertiary)
                    if item.messageCount > 0 { Text("\(item.messageCount) messages").ui(11.5).foregroundStyle(.tertiary) }
                }
            }
            Spacer(minLength: 0)
            Button("Reprendre") { session.assistant.resume(item) }.buttonStyle(.borderedProminent).controlSize(.small)
            IconButton(symbol: "doc.on.doc", help: "Copier la commande") { session.assistant.copyCommand(item) }
        }
        .card()
    }
}

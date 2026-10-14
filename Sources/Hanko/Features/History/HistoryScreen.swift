import HankoCore
import SwiftUI

struct HistoryScreen: View {
    let session: RepoSession

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HistorySearchBar(session: session)
                Divider()
                HistoryList(session: session)
            }
            .frame(minHeight: 220)
            VStack(spacing: 0) {
                if let commit = session.selectedCommit { CommitHeader(session: session, commit: commit) }
                DiffView(files: session.diff)
            }
            .frame(minHeight: 180)
        }
    }
}

private struct HistorySearchBar: View {
    @Bindable var session: RepoSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filtrer par message, SHA, branche ou tag", text: $session.filter.text)
                .textFieldStyle(.plain)
                .ui(12.5)
            Divider().frame(height: 14)
            Image(systemName: "person").foregroundStyle(.secondary)
            TextField("Auteur", text: $session.filter.author)
                .textFieldStyle(.plain)
                .ui(12.5)
                .frame(width: 130)
            if session.filter.isActive {
                Text("\(session.visibleCommits.count) / \(session.commits.count)").ui(11).foregroundStyle(.secondary)
                IconButton(symbol: "xmark.circle.fill", help: "Effacer le filtre") { session.filter = HistoryFilter() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct HistoryList: View {
    let session: RepoSession

    var body: some View {
        if session.commits.isEmpty {
            EmptyState(symbol: "clock", title: "Aucun commit", message: "Ce dépôt n’a pas encore d’historique.")
        } else if session.filter.isActive {
            let results = session.visibleCommits
            if results.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Aucun résultat", message: "Aucun commit ne correspond au filtre.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { commit in
                            CommitRow(commit: commit, row: nil, laneCount: 0, isSelected: commit.id == session.selectedCommitID)
                                .onTapGesture { Task { await session.select(commit: commit.id) } }
                                .contextMenu { CommitMenu(session: session, commit: commit) }
                        }
                    }
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(zip(session.commits, session.rows)), id: \.0.id) { commit, row in
                        CommitRow(commit: commit, row: row, laneCount: session.laneCount, isSelected: commit.id == session.selectedCommitID)
                            .onTapGesture { Task { await session.select(commit: commit.id) } }
                            .contextMenu { CommitMenu(session: session, commit: commit) }
                    }
                }
            }
        }
    }
}

struct CommitHeader: View {
    let session: RepoSession
    let commit: Commit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: commit.author, email: commit.email, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject).ui(14, .semibold).textSelection(.enabled)
                if !session.commitBody.isEmpty {
                    Text(session.commitBody).ui(12.5).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6)
                }
                HStack(spacing: 8) {
                    Text(commit.author).ui(12, .medium)
                    Text(commit.date.formatted(date: .abbreviated, time: .shortened)).ui(12).foregroundStyle(.secondary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commit.id, forType: .string)
                    } label: {
                        Text(commit.shortID).ui(11.5, mono: true)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Copier le SHA complet")
                    ForEach(commit.refs, id: \.self) { RefChip(label: $0) }
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await session.assistant.explain(commit) }
            } label: {
                Label("Expliquer", systemImage: "sparkles")
            }
            .disabled(!session.assistant.isAvailable || session.assistant.isBusy)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct CommitMenu: View {
    let session: RepoSession
    let commit: Commit

    var body: some View {
        Button("Expliquer avec l’IA") {
            Task { await session.select(commit: commit.id); await session.assistant.explain(commit) }
        }
        .disabled(!session.assistant.isAvailable)
        Divider()
        Button("Basculer sur ce commit (détaché)") { Task { await session.checkout(commit: commit) } }
        Button("Cherry-pick") { Task { await session.cherryPick(commit) } }
        Button("Revert") { Task { await session.revert(commit) } }
        Button("Rebase interactif depuis ce commit…") { Task { await session.beginRebase(from: commit) } }
        Divider()
        Menu("Reset la branche ici") {
            Button("Soft (garde l’index)") { Task { await session.reset(to: commit, mode: "soft") } }
            Button("Mixed (garde les fichiers)") { Task { await session.reset(to: commit, mode: "mixed") } }
        }
        Divider()
        Button("Copier le SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
    }
}

struct CommitRow: View {
    let commit: Commit
    let row: GraphRow?
    let laneCount: Int
    let isSelected: Bool
    private static let height: CGFloat = 30
    private static let laneWidth: CGFloat = 16

    var body: some View {
        HStack(spacing: 8) {
            if let row {
                GraphLanes(row: row, isMerge: commit.parents.count > 1, laneWidth: Self.laneWidth)
                    .frame(width: CGFloat(laneCount) * Self.laneWidth + 8, height: Self.height)
            }
            ForEach(commit.refs, id: \.self) { RefChip(label: $0) }
            Text(commit.subject).ui(13).lineLimit(1)
            Spacer(minLength: 12)
            AvatarView(name: commit.author, email: commit.email, size: 18)
            Text(commit.author).ui(12).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 120, alignment: .leading)
            Text(commit.shortID).ui(11, mono: true).foregroundStyle(.tertiary)
            Text(commit.date.formatted(.relative(presentation: .named)))
                .ui(11.5).foregroundStyle(.secondary).frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, row == nil ? 12 : 4)
        .padding(.trailing, 8)
        .frame(height: Self.height)
        .background(isSelected ? Theme.accent.opacity(0.2) : .clear)
        .contentShape(Rectangle())
    }
}

private struct GraphLanes: View {
    let row: GraphRow
    let isMerge: Bool
    let laneWidth: CGFloat

    private func x(_ lane: Int) -> CGFloat { CGFloat(lane) * laneWidth + laneWidth / 2 + 4 }

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            func line(_ from: CGPoint, _ to: CGPoint, _ lane: Int) {
                var path = Path()
                path.move(to: from)
                if from.x == to.x {
                    path.addLine(to: to)
                } else {
                    let c = (to.y - from.y) * 0.6
                    path.addCurve(to: to, control1: CGPoint(x: from.x, y: from.y + c), control2: CGPoint(x: to.x, y: to.y - c))
                }
                context.stroke(path, with: .color(Theme.lane(lane)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
            let node = CGPoint(x: x(row.column), y: mid)
            for lane in row.through { line(CGPoint(x: x(lane), y: 0), CGPoint(x: x(lane), y: size.height), lane) }
            for lane in row.incoming { line(CGPoint(x: x(lane), y: 0), node, lane) }
            for lane in row.outgoing { line(node, CGPoint(x: x(lane), y: size.height), lane) }

            let r: CGFloat = 5
            let rect = CGRect(x: node.x - r, y: node.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(Color(nsColor: .textBackgroundColor)))
            context.fill(Path(ellipseIn: rect), with: .color(Theme.lane(row.column)))
            if isMerge {
                context.fill(Path(ellipseIn: rect.insetBy(dx: 2, dy: 2)), with: .color(Color(nsColor: .textBackgroundColor)))
            }
        }
    }
}

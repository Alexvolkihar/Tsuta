import TsutaCore
import SwiftUI

/// What a diff can do with its lines: stage/unstage a hunk or a selection of lines.
struct StagingContext {
    let staged: Bool
    let onHunk: (DiffHunk, DiffFile) -> Void
    let onLines: (DiffFile, Set<Int>) -> Void
}

@MainActor
final class LineSelection: ObservableObject {
    @Published var ids: Set<Int> = []

    func toggle(_ id: Int) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }
}

struct DiffView: View {
    let files: [DiffFile]
    var staging: StagingContext?
    /// Inline review comments for (path, new line number).
    var comments: ((String, Int?) -> [ReviewComment])?
    @StateObject private var selection = LineSelection()
    private static let lineLimit = 4000

    var body: some View {
        if files.isEmpty {
            EmptyState(symbol: "doc.plaintext", title: "Aucune différence",
                       message: "Sélectionne un commit ou un fichier pour voir son diff.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(files) { file in
                        Section {
                            if file.hunks.isEmpty {
                                ForEach(file.lines.filter { $0.kind == .meta && !$0.text.hasPrefix("diff --git") }) { line in
                                    Text(line.text).ui(12, mono: true).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 2)
                                }
                            } else {
                                ForEach(file.hunks) { hunk in HunkView(file: file, hunk: hunk, staging: staging, comments: comments, selection: selection) }
                            }
                        } header: {
                            FileHeader(file: file, staging: staging, selection: selection)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: files) { selection.ids = [] }
        }
    }
}

private struct FileHeader: View {
    let file: DiffFile
    let staging: StagingContext?
    @ObservedObject var selection: LineSelection

    var body: some View {
        let own = selection.ids.intersection(file.lines.filter(\.isChange).map(\.id))
        HStack(spacing: 8) {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            Text(file.path).ui(12.5, .semibold).lineLimit(1).truncationMode(.middle)
            Text("+\(file.additions)").ui(11.5, .medium).foregroundStyle(.green)
            Text("−\(file.deletions)").ui(11.5, .medium).foregroundStyle(.red)
            Spacer()
            if let staging, !own.isEmpty {
                Button(staging.staged ? "Désindexer \(own.count) ligne(s)" : "Indexer \(own.count) ligne(s)") {
                    staging.onLines(file, own)
                    selection.ids.subtract(own)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct HunkView: View {
    let file: DiffFile
    let hunk: DiffHunk
    let staging: StagingContext?
    let comments: ((String, Int?) -> [ReviewComment])?
    @ObservedObject var selection: LineSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(hunk.header.text).ui(11.5, mono: true).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let staging {
                    Button(staging.staged ? "Désindexer le hunk" : "Indexer le hunk") { staging.onHunk(hunk, file) }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color.blue.opacity(0.09))

            ForEach(hunk.lines.prefix(2000)) { line in
                DiffLineRow(line: line, selectable: staging != nil && line.isChange, selection: selection)
                if let comments, let thread = Optional(comments(file.path, line.newNumber)), line.kind != .removed, !thread.isEmpty {
                    ForEach(thread) { InlineComment(comment: $0) }
                }
            }
        }
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let selectable: Bool
    @ObservedObject var selection: LineSelection

    var body: some View {
        let picked = selection.ids.contains(line.id)
        HStack(spacing: 0) {
            Group {
                if selectable {
                    Image(systemName: picked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(picked ? Theme.accent : Color.secondary.opacity(0.4))
                        .ui(11)
                } else {
                    Color.clear
                }
            }
            .frame(width: 24)
            Text(line.oldNumber.map(String.init) ?? "").frame(width: 40, alignment: .trailing)
            Text(line.newNumber.map(String.init) ?? "").frame(width: 40, alignment: .trailing)
            Text(marker).frame(width: 18)
            Text(line.text.isEmpty ? " " : line.text).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .ui(12, mono: true)
        .foregroundStyle(line.kind == .meta ? .secondary : .primary)
        .padding(.vertical, 1)
        .background(picked ? Theme.accent.opacity(0.22) : background)
        .contentShape(Rectangle())
        .onTapGesture { if selectable { selection.toggle(line.id) } }
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        default: ""
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: .green.opacity(0.15)
        case .removed: .red.opacity(0.15)
        default: .clear
        }
    }
}

struct InlineComment: View {
    let comment: ReviewComment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(name: comment.author, email: comment.author, size: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.author).ui(12, .semibold)
                    Text(comment.date.formatted(.relative(presentation: .named))).ui(11).foregroundStyle(.tertiary)
                }
                Text(comment.body).ui(12.5).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .card()
        .padding(.leading, 60).padding(.trailing, 12).padding(.vertical, 4)
    }
}

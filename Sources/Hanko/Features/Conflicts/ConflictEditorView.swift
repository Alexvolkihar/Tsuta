import HankoCore
import SwiftUI

@MainActor
final class ConflictModel: ObservableObject {
    @Published var segments: [ConflictSegment] = []
    @Published var choices: [ConflictChoice?] = []
    @Published var loadError: String?
    @Published var suggesting: Int?

    var total: Int { ConflictParser.conflictCount(segments) }
    var unresolved: Int { choices.filter { $0 == nil }.count }
    var rendered: String { ConflictParser.render(segments, choices: choices) }

    func load(_ url: URL) {
        do {
            segments = ConflictParser.parse(try String(contentsOf: url, encoding: .utf8))
            choices = Array(repeating: nil, count: ConflictParser.conflictCount(segments))
        } catch {
            loadError = "Lecture impossible (fichier binaire ?) : \(error.localizedDescription)"
        }
    }

    /// Replaces the n-th conflict by plain, already resolved lines (an AI suggestion).
    func replace(conflict n: Int, with lines: [String]) {
        var seen = 0
        for index in segments.indices {
            guard case .conflict = segments[index] else { continue }
            if seen == n {
                segments[index] = .text(lines)
                choices.remove(at: n)
                return
            }
            seen += 1
        }
    }

    /// Maps a segment index to its conflict ordinal.
    var ordinals: [Int: Int] {
        var map: [Int: Int] = [:]
        var n = 0
        for (index, segment) in segments.enumerated() {
            if case .conflict = segment { map[index] = n; n += 1 }
        }
        return map
    }
}

struct ConflictEditorView: View {
    let session: RepoSession
    let change: FileChange
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ConflictModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(Theme.accent)
                Text(change.path).ui(14, .semibold)
                Spacer()
                Text(model.total == 0 ? "Aucun marqueur" : "\(model.unresolved) / \(model.total) à résoudre")
                    .ui(12.5, .medium).foregroundStyle(model.unresolved == 0 ? .green : .orange)
            }
            .padding(14)
            Divider()
            if let error = model.loadError {
                EmptyState(symbol: "exclamationmark.triangle", title: "Fichier illisible", message: error)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        let ordinals = model.ordinals
                        ForEach(Array(model.segments.enumerated()), id: \.offset) { offset, segment in
                            switch segment {
                            case .text(let lines):
                                ContextLines(lines: lines)
                            case .conflict(let block):
                                let n = ordinals[offset] ?? 0
                                ConflictBlockView(block: block, choice: model.choices[n],
                                                  isSuggesting: model.suggesting == n,
                                                  canSuggest: session.assistant.isAvailable,
                                                  onChoose: { model.choices[n] = $0 },
                                                  onSuggest: { suggest(block, n) })
                            }
                        }
                    }
                    .padding(14)
                }
            }
            Divider()
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enregistrer et marquer résolu") {
                    let content = model.rendered, path = change.path
                    dismiss()
                    Task { await session.resolveConflict(path: path, content: content) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.unresolved > 0 || model.loadError != nil)
            }
            .padding(12)
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear { model.load(session.conflictFileURL(change)) }
    }

    private func suggest(_ block: ConflictBlock, _ n: Int) {
        model.suggesting = n
        Task {
            let lines = await session.assistant.resolution(for: block, path: change.path)
            model.suggesting = nil
            if let lines { model.replace(conflict: n, with: lines) }
        }
    }
}

private struct ContextLines: View {
    let lines: [String]

    var body: some View {
        let shown = lines.count > 6 ? Array(lines.prefix(2)) + ["⋯ \(lines.count - 4) lignes ⋯"] + Array(lines.suffix(2)) : lines
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line).ui(12, mono: true).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ConflictBlockView: View {
    let block: ConflictBlock
    let choice: ConflictChoice?
    let isSuggesting: Bool
    let canSuggest: Bool
    let onChoose: (ConflictChoice?) -> Void
    let onSuggest: () -> Void

    private let options: [(ConflictChoice, String)] = [
        (.ours, "Garder la nôtre"), (.theirs, "Garder la leur"), (.both, "Les deux"), (.bothReversed, "Les deux (inversé)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                pane("Nôtre · \(block.oursLabel)", block.ours, .blue, choice == .ours || choice == .both || choice == .bothReversed)
                pane("Leur · \(block.theirsLabel)", block.theirs, .green, choice == .theirs || choice == .both || choice == .bothReversed)
            }
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { option in
                    Button(option.1) { onChoose(choice == option.0 ? nil : option.0) }
                        .buttonStyle(.bordered)
                        .tint(choice == option.0 ? Theme.accent : nil)
                }
                Spacer()
                if isSuggesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button { onSuggest() } label: { Label("Suggérer", systemImage: "sparkles") }.disabled(!canSuggest)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(choice == nil ? Color.orange.opacity(0.55) : Color.green.opacity(0.55)))
    }

    private func pane(_ title: String, _ lines: [String], _ tint: Color, _ active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).ui(11.5, .semibold).foregroundStyle(tint).padding(.bottom, 3)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line).ui(12, mono: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(active ? 0.24 : 0.08))
            }
            if lines.isEmpty { Text("(vide)").ui(11.5).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

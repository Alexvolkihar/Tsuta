import TsutaCore
import SwiftUI

@MainActor
final class ReviewDraft: ObservableObject {
    @Published var body = ""
    @Published var mergeMethod: MergeMethod = .squash
    @Published var deleteBranch = true
}

struct ReviewsScreen: View {
    let session: RepoSession

    var body: some View {
        HSplitView {
            RequestList(reviews: session.reviews).frame(minWidth: 270, idealWidth: 330, maxWidth: 460)
            Group {
                if let request = session.reviews.selected {
                    RequestDetail(session: session, request: request).id(request.number)
                } else {
                    EmptyState(symbol: "text.bubble", title: "Aucune sélection", message: "Choisis une demande pour la relire.")
                }
            }
            .frame(minWidth: 460)
        }
        .task { if session.reviews.requests.isEmpty { await session.reviews.load() } }
    }
}

private struct RequestList: View {
    let reviews: ReviewsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(title: reviews.forge.map { "\($0.requestName)s" } ?? "Reviews", count: reviews.requests.count)
                if reviews.isLoading { ProgressView().controlSize(.small) }
                IconButton(symbol: "arrow.clockwise", help: "Actualiser") { Task { await reviews.load() } }
            }
            .padding(.horizontal, 12).frame(height: 38)
            Divider()
            if let cachedAt = reviews.cachedAt {
                Label("Copie locale du \(cachedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "icloud.slash")
                    .ui(11.5).foregroundStyle(.orange).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
            }
            if reviews.requests.isEmpty {
                EmptyState(symbol: reviews.statusMessage == nil ? "checkmark.seal" : "exclamationmark.bubble",
                           title: reviews.statusMessage == nil ? "Rien à relire" : "Reviews indisponibles",
                           message: reviews.statusMessage ?? "Aucune demande ouverte.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(reviews.requests) { request in
                            RequestRow(request: request, selected: request.number == reviews.selectedNumber)
                                .onTapGesture { Task { await reviews.select(request.number) } }
                        }
                    }
                }
            }
        }
    }
}

private struct RequestRow: View {
    let request: ReviewRequest
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: request.author, email: request.author, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("#\(request.number)").ui(11.5, .medium).foregroundStyle(.secondary)
                    if request.isDraft { Text("brouillon").ui(10).padding(.horizontal, 5).background(.quaternary, in: Capsule()) }
                    Spacer()
                    Image(systemName: checkIcon).foregroundStyle(checkColor).ui(11)
                }
                Text(request.title).ui(13, .medium).lineLimit(2)
                Text("\(request.author) · \(request.sourceBranch) → \(request.targetBranch)")
                    .ui(11).foregroundStyle(.secondary).lineLimit(1)
                if let decision = request.decision, let label = decisionLabel(decision) {
                    Text(label).ui(10.5, .semibold).foregroundStyle(decision == "APPROVED" ? .green : .orange)
                }
            }
        }
        .padding(10)
        .background(selected ? Theme.accent.opacity(0.18) : .clear)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        .contentShape(Rectangle())
    }

    private var checkIcon: String {
        switch request.checks {
        case .passing: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .none: "circle.dashed"
        }
    }

    private var checkColor: Color {
        switch request.checks {
        case .passing: .green
        case .failing: .red
        case .pending: .orange
        case .none: .secondary
        }
    }

    private func decisionLabel(_ decision: String) -> String? {
        switch decision {
        case "APPROVED": "Approuvée"
        case "CHANGES_REQUESTED": "Changements demandés"
        case "REVIEW_REQUIRED": "Revue requise"
        default: nil
        }
    }
}

private struct RequestDetail: View {
    let session: RepoSession
    let request: ReviewRequest
    @StateObject private var draft = ReviewDraft()

    var body: some View {
        @Bindable var reviews = session.reviews
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(request.title).ui(16, .semibold).lineLimit(2)
                    Spacer()
                    if let url = URL(string: request.url) { Link(destination: url) { Image(systemName: "arrow.up.right.square") } }
                }
                Text("#\(request.number) · \(request.author) · \(request.sourceBranch) → \(request.targetBranch)")
                    .ui(12).foregroundStyle(.secondary)
                HStack {
                    Picker("", selection: $reviews.tab) {
                        ForEach(ReviewsModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                    Spacer()
                    Button {
                        Task { await session.assistant.summarize(request, diff: reviews.diff, discussion: reviews.discussion) }
                    } label: { Label("Résumer", systemImage: "sparkles") }
                        .disabled(!session.assistant.isAvailable || session.assistant.isBusy)
                    Button("Récupérer la branche") {
                        Task { await reviews.checkoutSelected(); await session.setMode(.history) }
                    }
                }
            }
            .padding(12)
            Divider()
            switch reviews.tab {
            case .diff:
                DiffView(files: reviews.diff, comments: { path, line in reviews.comments(path: path, line: line) })
            case .discussion:
                DiscussionView(comments: reviews.discussion)
            }
            Divider()
            composer(reviews)
        }
    }

    private func composer(_ reviews: ReviewsModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Commentaire ou motif de la revue…", text: $draft.body, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...4)
            HStack {
                Button("Commenter") { send { await reviews.comment($0) } }.disabled(draft.body.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Demander des changements") { send { await reviews.review(.requestChanges, body: $0) } }
                    .disabled(draft.body.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Approuver") { send { await reviews.review(.approve, body: $0) } }
                Spacer()
                Picker("", selection: $draft.mergeMethod) {
                    ForEach(MergeMethod.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden().frame(width: 110)
                Toggle("Supprimer la branche", isOn: $draft.deleteBranch).toggleStyle(.checkbox)
                Button("Fusionner") { Task { await reviews.merge(method: draft.mergeMethod, deleteBranch: draft.deleteBranch) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(request.isDraft || request.checks == .failing || reviews.isBusy)
                    .help(request.isDraft ? "Cette demande est un brouillon" : (request.checks == .failing ? "Des checks sont en échec" : "Fusionner"))
            }
        }
        .padding(12)
    }

    private func send(_ action: @escaping (String) async -> Void) {
        let text = draft.body
        draft.body = ""
        Task { await action(text) }
    }
}

private struct DiscussionView: View {
    let comments: [ReviewComment]

    var body: some View {
        if comments.isEmpty {
            EmptyState(symbol: "bubble.left", title: "Pas de discussion", message: "Personne n’a encore commenté.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                AvatarView(name: comment.author, email: comment.author, size: 20)
                                Text(comment.author).ui(12.5, .semibold)
                                if let state = comment.state { Text(state.lowercased()).ui(11).foregroundStyle(.secondary) }
                                if let path = comment.path {
                                    Text("\(path)\(comment.line.map { ":\($0)" } ?? "")").ui(11, mono: true).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(comment.date.formatted(.relative(presentation: .named))).ui(11).foregroundStyle(.tertiary)
                            }
                            Text(comment.body).ui(12.5).textSelection(.enabled)
                        }
                        .card()
                    }
                }
                .padding(12)
            }
        }
    }
}

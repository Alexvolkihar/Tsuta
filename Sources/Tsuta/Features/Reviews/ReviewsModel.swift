import Foundation
import TsutaCore
import Observation

/// Pull / merge requests of the repository, read through `gh` / `glab`, with an offline cache.
@MainActor
@Observable
final class ReviewsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case diff = "Diff", discussion = "Discussion"
        var id: String { rawValue }
    }

    private let root: URL
    private(set) var forge: ForgeKind?
    private(set) var remoteURL: String?

    private(set) var requests: [ReviewRequest] = []
    private(set) var diff: [DiffFile] = []
    private(set) var discussion: [ReviewComment] = []
    var selectedNumber: Int?
    var tab: Tab = .diff
    private(set) var isLoading = false
    private(set) var statusMessage: String?
    /// Date of the cached copy being displayed when the network is unavailable.
    private(set) var cachedAt: Date?
    private(set) var isBusy = false

    var onError: (String) -> Void = { _ in }
    var onRepositoryChanged: () async -> Void = {}

    init(root: URL) { self.root = root }

    var selected: ReviewRequest? { requests.first { $0.number == selectedNumber } }

    private var client: ForgeClient? { forge.map { ForgeClient(kind: $0, root: root) } }

    func configure(forge: ForgeKind?, remoteURL: String?) {
        self.forge = forge
        self.remoteURL = remoteURL
    }

    // MARK: Loading

    func load() async {
        guard let client else {
            requests = []
            statusMessage = remoteURL == nil ? "Ce dépôt n’a pas de remote « origin »."
                                             : "La forge de « \(remoteURL ?? "") » n’est pas reconnue (GitHub ou GitLab)."
            return
        }
        if requests.isEmpty, let cached = ReviewCache.load(key: cacheKey) {
            requests = cached.requests
            cachedAt = cached.date
        }
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await client.list()
            cachedAt = nil
            statusMessage = nil
            ReviewCache.save(.init(date: .now, requests: requests, details: [:]), key: cacheKey)
            if let n = selectedNumber, !requests.contains(where: { $0.number == n }) { selectedNumber = nil }
        } catch {
            statusMessage = requests.isEmpty ? error.localizedDescription : "Hors ligne : \(error.localizedDescription)"
        }
    }

    func select(_ number: Int) async {
        selectedNumber = number
        diff = []
        discussion = []
        guard let client else { return }
        if let cached = ReviewCache.load(key: cacheKey)?.details[String(number)] {
            diff = GitParsing.parseDiff(cached.diff)
            discussion = cached.discussion
        }
        do {
            async let rawDiff = client.diff(number)
            async let comments = client.discussion(number)
            let text = try await rawDiff
            diff = GitParsing.parseDiff(text)
            discussion = try await comments
            var cache = ReviewCache.load(key: cacheKey) ?? .init(date: .now, requests: requests, details: [:])
            cache.details[String(number)] = .init(diff: text, discussion: discussion)
            ReviewCache.save(cache, key: cacheKey)
        } catch {
            if diff.isEmpty { onError(error.localizedDescription) }
        }
    }

    /// Comments attached to a file line, shown inline under the diff.
    func comments(path: String, line: Int?) -> [ReviewComment] {
        guard let line else { return [] }
        return discussion.filter { $0.kind == .inline && $0.path == path && $0.line == line }
    }

    // MARK: Actions

    private func act(_ work: (ForgeClient, Int) async throws -> Void) async {
        guard let client, let number = selectedNumber else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await work(client, number) } catch { onError(error.localizedDescription) }
        await load()
        await select(number)
    }

    func review(_ verdict: ReviewVerdict, body: String) async { await act { try await $0.review($1, verdict: verdict, body: body) } }
    func comment(_ body: String) async { await act { try await $0.comment($1, body: body) } }

    func merge(method: MergeMethod, deleteBranch: Bool) async {
        await act { try await $0.merge($1, method: method, deleteBranch: deleteBranch) }
        await onRepositoryChanged()
    }

    func checkoutSelected() async {
        guard let client, let number = selectedNumber else { return }
        do { try await client.checkout(number) } catch { onError(error.localizedDescription) }
        await onRepositoryChanged()
    }

    // MARK: Cache

    private var cacheKey: String { remoteURL ?? root.path }
}

/// JSON files under Caches, one per repository, so reviews stay readable offline.
enum ReviewCache {
    struct Detail: Codable { var diff: String; var discussion: [ReviewComment] }
    struct Snapshot: Codable {
        var date: Date
        var requests: [ReviewRequest]
        var details: [String: Detail]
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Tsuta/reviews")
    }

    private static func file(_ key: String) -> URL {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    static func load(key: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot, key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) { try? data.write(to: file(key), options: .atomic) }
    }
}

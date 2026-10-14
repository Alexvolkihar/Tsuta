import Foundation
import HankoCore
import Observation

/// User preferences, persisted in UserDefaults. Plain stored properties so SwiftUI observes them.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var zoom: Double { didSet { defaults.set(zoom, forKey: "zoom") } }
    var hideWhitespaceChanges: Bool { didSet { defaults.set(hideWhitespaceChanges, forKey: "hideWhitespaceChanges") } }
    var commitLimit: Int { didSet { defaults.set(commitLimit, forKey: "commitLimit") } }
    var preferredAgent: String { didSet { defaults.set(preferredAgent, forKey: "preferredAgent") } }
    var autoFetchMinutes: Int { didSet { defaults.set(autoFetchMinutes, forKey: "autoFetchMinutes") } }
    var pullStrategy: String { didSet { defaults.set(pullStrategy, forKey: "pullStrategy") } }

    /// `git pull` flag for each strategy.
    static let pullStrategies: [(id: String, title: String, flag: String)] = [
        ("ff-only", "Avance rapide uniquement", "--ff-only"),
        ("rebase", "Rebase", "--rebase"),
        ("merge", "Merge", "--no-rebase"),
    ]
    var pullFlag: String { Self.pullStrategies.first { $0.id == pullStrategy }?.flag ?? "--ff-only" }

    static let zoomRange: ClosedRange<Double> = 0.8...1.6
    static let commitLimits = [500, 1500, 3000, 6000]

    init() {
        let d = UserDefaults.standard
        let z = d.double(forKey: "zoom")
        zoom = z == 0 ? 1 : min(max(z, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        hideWhitespaceChanges = d.bool(forKey: "hideWhitespaceChanges")
        let limit = d.integer(forKey: "commitLimit")
        commitLimit = Self.commitLimits.contains(limit) ? limit : 1500
        preferredAgent = d.string(forKey: "preferredAgent") ?? ""
        autoFetchMinutes = d.integer(forKey: "autoFetchMinutes")
        pullStrategy = d.string(forKey: "pullStrategy") ?? "ff-only"
    }

    func zoomIn() { zoom = min(Self.zoomRange.upperBound, (zoom + 0.1).rounded(toPlaces: 1)) }
    func zoomOut() { zoom = max(Self.zoomRange.lowerBound, (zoom - 0.1).rounded(toPlaces: 1)) }
    func resetZoom() { zoom = 1 }

    var agent: AIBackend? {
        get { AIBackend(rawValue: preferredAgent).flatMap { $0.isAvailable ? $0 : nil } ?? AIBackend.firstAvailable }
        set { preferredAgent = newValue?.rawValue ?? "" }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

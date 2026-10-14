import Foundation

/// Command-line switches, used to take reproducible screenshots (`Tsuta --open <repo> --mode history --snapshot out.png`).
struct LaunchOptions {
    var repository: URL?
    var mode: RepoSession.Mode?
    var snapshot: URL?
    var size = CGSize(width: 1280, height: 800)
    var selectFirstChange = false
    var selectChange: String?
    var zoom: Double?
    var openPalette = false
    var showConsole = false
    var selectReview: Int?
    var dark = false
    var inspect: String?
    var inspectRevision: String?
    var inspectTab: String?
    var light = false

    static let current = LaunchOptions(arguments: CommandLine.arguments)

    var isSnapshot: Bool { snapshot != nil }

    init(arguments: [String]) {
        var index = 1
        func value() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            switch arguments[index] {
            case "--open": repository = value().map { URL(fileURLWithPath: $0, isDirectory: true) }
            case "--mode": mode = value().flatMap { RepoSession.Mode(rawValue: $0) }
            case "--snapshot": snapshot = value().map { URL(fileURLWithPath: $0) }
            case "--size":
                if let parts = value()?.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
                    size = CGSize(width: parts[0], height: parts[1])
                }
            case "--select-first-change": selectFirstChange = true
            case "--select-change": selectChange = value()
            case "--zoom": zoom = value().flatMap(Double.init)
            case "--palette": openPalette = true
            case "--console": showConsole = true
            case "--review": selectReview = value().flatMap(Int.init)
            case "--dark": dark = true
            case "--inspect": inspect = value()
            case "--inspect-revision": inspectRevision = value()
            case "--inspect-tab": inspectTab = value()
            case "--light": light = true
            default: break
            }
            index += 1
        }
    }
}

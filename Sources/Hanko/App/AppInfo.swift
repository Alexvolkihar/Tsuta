import Foundation

enum AppInfo {
    static let name = "Hanko"
    static let tagline = "Un client Git natif pour macOS"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static let repositoryURL = URL(string: "https://github.com/Alexvolkihar/Hanko")!
}

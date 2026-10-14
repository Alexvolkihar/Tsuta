import AppKit

/// Renders the main window into a PNG and quits. Needs no screen-recording permission because it
/// only draws the app's own view hierarchy.
@MainActor
enum SnapshotRunner {
    static func schedule(_ options: LaunchOptions) {
        guard let target = options.snapshot else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
                window.setContentSize(options.size)
                window.center()
                if options.dark { window.appearance = NSAppearance(named: .darkAqua) }
                if options.light { window.appearance = NSAppearance(named: .aqua) }
            }
            try? await Task.sleep(for: .seconds(5.0))
            // A sheet (palette, blame, conflict editor…) is its own window: capture it when one is open.
            let main = NSApp.windows.first(where: { $0.contentView != nil })
            guard let view = main?.attachedSheet?.contentView ?? main?.contentView else { exit(2) }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(3) }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { exit(4) }
            try? data.write(to: target)
            exit(0)
        }
    }
}

import CoreServices
import Foundation

/// Calls `onChange` (debounced) when files in the working tree or the interesting parts
/// of `.git` change, so the UI follows what happens in a terminal or an editor.
final class RepositoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable () -> Void
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "hanko.watcher")

    init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handle(Array(list.prefix(count)))
        }
        stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [root.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func handle(_ paths: [String]) {
        guard paths.contains(where: Self.isRelevant) else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [onChange] in onChange() }
        pending = item
        queue.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    /// Ignores git's own bookkeeping (objects, logs, lock files) that would cause refresh loops.
    static func isRelevant(_ path: String) -> Bool {
        guard let range = path.range(of: "/.git/") else { return !path.hasSuffix("/.git") }
        let inside = path[range.upperBound...]
        if inside.hasSuffix(".lock") { return false }
        for noisy in ["objects/", "logs/", "lfs/", "hooks/", "info/", "fsmonitor"] where inside.hasPrefix(noisy) { return false }
        return true
    }
}

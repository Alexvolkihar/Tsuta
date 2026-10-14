import Foundation
import TsutaCore

extension RepoSession {
    struct UndoEntry {
        enum Kind {
            case commit(previousHead: String?)
            case discard(path: String, backup: URL)
            /// Any operation that moved HEAD (rebase, merge, reset, amend…): restored from a snapshot.
            case history(before: HeadSnapshot, after: String?, mode: GitClient.RestoreMode)
        }
        let title: String
        let kind: Kind
    }

    static var backupDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Tsuta/undo")
    }

    var undoTitle: String? { undoStack.last?.title }

    func pushUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > 20 { undoStack.removeFirst() }
    }

    /// Runs a git operation that can move HEAD and records how to take it back.
    /// An operation that stops on conflicts keeps its starting point until it is continued.
    func performUndoable(_ title: String, mode: GitClient.RestoreMode = .keep,
                         _ work: (GitClient) async throws -> Void) async {
        let before = await git.headSnapshot()
        await perform(work)
        if operation != .none {
            operationOrigin = (title, before, mode)
            return
        }
        let after = await git.headSnapshot()
        if before.head != nil, before.head != after.head {
            pushUndo(UndoEntry(title: title, kind: .history(before: before, after: after.head, mode: mode)))
        }
    }

    /// Called once a paused operation (merge, rebase…) has finished.
    func finishPausedOperation() async {
        guard let origin = operationOrigin, operation == .none else { return }
        operationOrigin = nil
        let after = await git.headSnapshot()
        if origin.snapshot.head != after.head {
            pushUndo(UndoEntry(title: origin.title, kind: .history(before: origin.snapshot, after: after.head, mode: origin.mode)))
        }
    }

    func undo() async {
        guard let entry = undoStack.popLast() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            switch entry.kind {
            case .commit(let previous):
                if let previous {
                    try await git.run(["reset", "--soft", previous])
                } else {
                    try await git.run(["update-ref", "-d", "HEAD"])
                }
            case .history(let before, let after, let mode):
                try await git.restore(before, expectedHead: after, mode: mode)
            case .discard(let path, let backup):
                let target = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.copyItem(at: backup, to: target)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}

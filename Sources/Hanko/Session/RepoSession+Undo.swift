import Foundation

extension RepoSession {
    struct UndoEntry {
        enum Kind {
            case commit(previousHead: String?)
            case discard(path: String, backup: URL)
        }
        let title: String
        let kind: Kind
    }

    static var backupDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Hanko/undo")
    }

    var undoTitle: String? { undoStack.last?.title }

    func pushUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > 20 { undoStack.removeFirst() }
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

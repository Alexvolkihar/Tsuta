import Foundation
import TsutaCore

extension RepoSession {
    // MARK: Index

    func stage(_ change: FileChange) async {
        await perform { try await $0.run(["add", "--", change.path]) }
    }

    func unstage(_ change: FileChange) async {
        await perform { git in
            let hasHead = (try? await git.run(["rev-parse", "--verify", "-q", "HEAD"])) != nil
            if hasHead {
                try await git.run(["restore", "--staged", "--", change.path])
            } else {
                try await git.run(["rm", "--cached", "-q", "--", change.path])
            }
        }
    }

    func stageAll() async { await perform { try await $0.run(["add", "-A"]) } }

    /// Makes an untracked file stageable line by line: it is recorded as "intent to add", which
    /// turns it into a regular diff. Nothing is staged until a line or a hunk is applied.
    func prepareLineStaging(_ change: FileChange) async {
        await perform { try await $0.markIntentToAdd(path: change.path) }
    }

    /// Stages (or unstages) only the selected lines of one file, via `git apply --cached`.
    func applyPartial(file: DiffFile, selected: Set<Int>, staged: Bool) async {
        let direction: PatchBuilder.Direction = staged ? .unstage : .stage
        guard let patch = PatchBuilder.patch(for: file, selected: selected, direction: direction) else { return }
        await perform { try await $0.run(direction.applyArguments, stdin: patch) }
    }

    func applyPartial(hunk: DiffHunk, in file: DiffFile, staged: Bool) async {
        await applyPartial(file: file, selected: hunk.changeIDs, staged: staged)
    }

    // MARK: Discard (undoable)

    func discard(_ change: FileChange) async {
        let source = root.appendingPathComponent(change.path)
        let backup = Self.backupDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: Self.backupDirectory, withIntermediateDirectories: true)
        if (try? FileManager.default.copyItem(at: source, to: backup)) != nil {
            pushUndo(UndoEntry(title: "Annuler l’abandon de « \(change.path) »",
                               kind: .discard(path: change.path, backup: backup)))
        }
        // An intent-to-add entry must never be restored from the index (that would empty the file):
        // it is forgotten first and the file is then removed like any untracked file.
        let isIntentToAdd = !change.isUntracked && change.index == "." && change.worktree == "A"
        await perform { git in
            if isIntentToAdd {
                try await git.forgetIndexEntry(path: change.path)
                try await git.run(["clean", "-f", "--", change.path])
            } else if change.isUntracked {
                try await git.run(["clean", "-f", "--", change.path])
            } else {
                try await git.run(["restore", "--worktree", "--", change.path])
            }
        }
    }

    // MARK: Commit

    func commit(amend: Bool = false) async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amend || !message.isEmpty else { return }
        let previousHead = try? await git.run(["rev-parse", "--verify", "-q", "HEAD"], allowedStatuses: [0, 1])
        errorMessage = nil
        let before = await git.headSnapshot()
        await perform { git in
            var args = ["commit", "-q"]
            if amend { args.append("--amend") }
            if message.isEmpty {
                try await git.run(args + ["--no-edit"])
            } else {
                try await git.run(args + ["-F", "-"], stdin: message + "\n")
            }
        }
        guard errorMessage == nil else { return }
        commitMessage = ""
        if amend {
            let after = await git.headSnapshot()
            if before.head != nil { pushUndo(UndoEntry(title: "Annuler l’amend", kind: .history(before: before, after: after.head, mode: .soft))) }
        } else {
            let head = previousHead?.trimmingCharacters(in: .whitespacesAndNewlines)
            pushUndo(UndoEntry(title: "Annuler le commit", kind: .commit(previousHead: head?.isEmpty == true ? nil : head)))
        }
    }

    // MARK: Stash

    func stashPush(message: String) async {
        await perform { try await $0.run(["stash", "push", "-u", "-m", message.isEmpty ? "WIP" : message]) }
    }
    func stashApply(_ stash: StashEntry) async { await perform { try await $0.run(["stash", "apply", stash.ref]) } }
    func stashPop(_ stash: StashEntry) async { await perform { try await $0.run(["stash", "pop", stash.ref]) } }
    func stashDrop(_ stash: StashEntry) async { await perform { try await $0.run(["stash", "drop", stash.ref]) } }
}

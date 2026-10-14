import Foundation
import HankoCore

extension RepoSession {
    // MARK: Commit actions

    func cherryPick(_ commit: Commit) async {
        await perform { try await $0.run(["cherry-pick", commit.id], allowedStatuses: [0, 1]) }
    }

    func revert(_ commit: Commit) async {
        await perform { try await $0.run(["revert", "--no-edit", commit.id], allowedStatuses: [0, 1]) }
    }

    func checkout(commit: Commit) async {
        await perform { try await $0.run(["switch", "--detach", commit.id]) }
    }

    func createBranch(named name: String, at commit: Commit? = nil) async {
        await perform { try await $0.run(["switch", "-c", name] + (commit.map { [$0.id] } ?? [])) }
    }

    func reset(to commit: Commit, mode: String) async {
        await perform { try await $0.run(["reset", "--\(mode)", commit.id]) }
    }

    // MARK: Branches

    func checkout(_ branch: BranchInfo) async {
        await perform { git in
            if branch.isRemote {
                let local = branch.name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? branch.name
                try await git.run(["switch", "--track", "-c", local, branch.name])
            } else {
                try await git.run(["switch", branch.name])
            }
        }
    }

    func deleteBranch(_ branch: BranchInfo, force: Bool) async {
        await perform { try await $0.run(["branch", force ? "-D" : "-d", branch.name]) }
    }

    func merge(_ source: String) async {
        await perform { try await $0.run(["merge", "--no-edit", source], allowedStatuses: [0, 1]) }
    }

    func rebaseCurrentBranch(onto target: String) async {
        await perform { try await $0.run(["rebase", "--autostash", target], allowedStatuses: [0, 1]) }
    }

    /// Resolves a drag & drop of one branch onto another into concrete operations.
    func dropOptions(for drop: BranchDrop) -> [(title: String, run: () async -> Void)] {
        let source = drop.source, target = drop.target
        guard source != target.name else { return [] }
        if target.isCurrent {
            return [
                ("Fusionner « \(source) » dans « \(target.name) »", { await self.merge(source) }),
                ("Rebaser « \(target.name) » sur « \(source) »", { await self.rebaseCurrentBranch(onto: source) }),
            ]
        }
        guard !target.isRemote else { return [] }
        return [("Basculer sur « \(target.name) » puis fusionner « \(source) »", {
            await self.checkout(target)
            if self.errorMessage == nil { await self.merge(source) }
        })]
    }

    // MARK: Interactive rebase

    func beginRebase(from commit: Commit) async {
        do {
            let base = commit.parents.first
            let range = base.map { "\($0)..HEAD" } ?? "HEAD"
            let out = try await git.run(["log", "--reverse", "--no-merges", RebasePlanner.logFormat, range])
            let entries = RebasePlanner.parseEntries(out)
            guard !entries.isEmpty else {
                errorMessage = "Aucun commit à rebaser à partir de celui-ci (les merges sont ignorés)."
                return
            }
            rebasePlan = RebasePlan(base: base, entries: entries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runRebase(base: String?, entries: [RebaseEntry]) async {
        await perform { try await $0.interactiveRebase(onto: base, entries: entries) }
    }
}

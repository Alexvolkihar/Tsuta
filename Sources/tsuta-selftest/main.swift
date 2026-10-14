import Foundation
import TsutaCore

var failures = 0
var checks = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: Int = #line) {
    checks += 1
    if actual != expected {
        failures += 1
        print("  ✗ \(label) (ligne \(line)) — attendu \(expected), obtenu \(actual)")
    }
}

func group(_ name: String, _ body: () async throws -> Void) async {
    let before = failures
    do { try await body() } catch { failures += 1; print("  ✗ exception: \(error)") }
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

func commit(_ id: String, _ parents: [String]) -> Commit {
    Commit(id: id, shortID: id, parents: parents, author: "", email: "", date: .now, refs: [], subject: id)
}

await group("log parsing") {
    let text = "\u{1e}aaa\u{1f}aa\u{1f}bbb ccc\u{1f}Ann\u{1f}a@x.io\u{1f}2026-10-14T19:04:59+02:00\u{1f}HEAD -> main, origin/main, tag: v1, feature/x\u{1f}Fix thing\n"
    let commits = GitParsing.parseLog(text, remotes: ["origin"])
    expect(commits.count, 1, "un commit")
    expect(commits[0].parents, ["bbb", "ccc"], "deux parents")
    expect(commits[0].subject, "Fix thing", "sujet")
    expect(commits[0].refs.map(\.kind), [.head, .remote, .tag, .local], "types de refs")
}

await group("status parsing") {
    let text = "# branch.head main\0# branch.ab +2 -1\0"
        + "1 .M N... 100644 100644 100644 h1 h2 src/a b.swift\0"
        + "1 A. N... 000000 100644 100644 h1 h2 new.txt\0"
        + "2 R. N... 100644 100644 100644 h1 h2 R100 renamed.txt\0old.txt\0"
        + "? untracked.txt\0"
    let s = GitParsing.parseStatus(text)
    expect(s.branch, "main", "branche")
    expect(s.ahead, 2, "ahead")
    expect(s.behind, 1, "behind")
    expect(s.changes.count, 4, "4 changements")
    expect(s.staged.map(\.path).sorted(), ["new.txt", "renamed.txt"], "indexés")
    expect(s.unstaged.contains { $0.path == "src/a b.swift" }, true, "chemin avec espace")
    expect(s.changes.first { $0.path == "renamed.txt" }?.originalPath, "old.txt", "ancien nom")
}

await group("diff parsing") {
    let diff = "diff --git a/f.txt b/f.txt\nindex 1..2 100644\n--- a/f.txt\n+++ b/f.txt\n@@ -1,2 +1,3 @@\n keep\n-old\n+new\n+more\n"
    let files = GitParsing.parseDiff(diff)
    expect(files.count, 1, "un fichier")
    expect(files[0].path, "f.txt", "chemin")
    expect(files[0].additions, 2, "ajouts")
    expect(files[0].deletions, 1, "suppressions")
    expect(files[0].lines.last?.newNumber, 3, "numéro de ligne")
}

await group("graph: historique linéaire") {
    let rows = GraphLayout.build([commit("c", ["b"]), commit("b", ["a"]), commit("a", [])])
    expect(rows.map(\.column), [0, 0, 0], "une seule colonne")
    expect(rows.allSatisfy { $0.laneCount == 1 }, true, "une seule lane")
}

await group("graph: merge") {
    let rows = GraphLayout.build([commit("m", ["b", "x"]), commit("x", ["a"]), commit("b", ["a"]), commit("a", [])])
    expect(rows[0].outgoing, [0, 1], "le merge ouvre une 2e lane")
    expect(rows[1].column, 1, "x sur la 2e lane")
    expect(rows[2].column, 0, "b sur la 1re")
    expect(rows[2].outgoing, [1], "b rejoint la lane de a par une courbe")
    expect(rows[3].incoming, [1], "a reçoit la lane 1")
    expect(rows[3].column, 1, "a reste sur la lane 1")
    expect(rows[3].outgoing, [], "a est la racine")
}

await group("dépôt git réel") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tsuta-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let git = GitClient(root: dir)
    let statusArgs = ["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all"]

    try await git.run(["init", "-q", "-b", "main"])
    try await git.run(["config", "user.name", "Test"])
    try await git.run(["config", "user.email", "t@example.com"])
    try await git.run(["config", "commit.gpgsign", "false"])
    expect(GitClient.topLevel(of: dir)?.lastPathComponent, dir.lastPathComponent, "topLevel")

    let file = dir.appendingPathComponent("a.txt")
    try "hello\n".write(to: file, atomically: true, encoding: .utf8)
    var status = GitParsing.parseStatus(try await git.run(statusArgs))
    expect(status.unstaged.map(\.path), ["a.txt"], "fichier non suivi")

    try await git.run(["add", "--", "a.txt"])
    try await git.run(["commit", "-q", "-F", "-"], stdin: "first commit\n")
    try "hello\nworld\n".write(to: file, atomically: true, encoding: .utf8)

    status = GitParsing.parseStatus(try await git.run(statusArgs))
    expect(status.branch, "main", "branche courante")
    expect(status.changes.first?.worktree, "M", "modifié")

    let diff = GitParsing.parseDiff(try await git.run(["diff", "--no-ext-diff", "--", "a.txt"]))
    expect(diff.first?.additions, 1, "diff: 1 ajout")

    let log = GitParsing.parseLog(try await git.run(["log", "--all", GitParsing.logFormat]))
    expect(log.map(\.subject), ["first commit"], "log")
    expect(log.first?.refs.first?.name, "main", "ref HEAD")

    var failed = false
    do { try await git.run(["checkout", "no-such-branch"]) } catch { failed = true }
    expect(failed, true, "une commande en échec lève GitError")
}

// MARK: - conflits, rebase, stash, worktrees, forges, IA

func makeRepo() async throws -> (GitClient, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tsuta-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let git = GitClient(root: dir)
    try await git.run(["init", "-q", "-b", "main"])
    try await git.run(["config", "user.name", "Test"])
    try await git.run(["config", "user.email", "t@example.com"])
    try await git.run(["config", "commit.gpgsign", "false"])
    return (git, dir)
}

func write(_ text: String, _ name: String, in dir: URL) throws {
    try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
}

func commitAll(_ git: GitClient, _ message: String) async throws {
    try await git.run(["add", "-A"])
    try await git.run(["commit", "-q", "-F", "-"], stdin: message + "\n")
}

await group("conflits: parsing et résolution") {
    let text = "avant\n<<<<<<< HEAD\nnotre ligne\n||||||| base\nancienne\n=======\nleur ligne\n>>>>>>> feature\napres\n"
    let segments = ConflictParser.parse(text)
    expect(ConflictParser.conflictCount(segments), 1, "un conflit")
    guard case .conflict(let block) = segments[1] else { expect(false, true, "bloc"); return }
    expect(block.ours, ["notre ligne"], "ours")
    expect(block.theirs, ["leur ligne"], "theirs")
    expect(block.base ?? [], ["ancienne"], "base diff3")
    expect(block.oursLabel, "HEAD", "label ours")
    expect(block.theirsLabel, "feature", "label theirs")
    expect(ConflictParser.render(segments, choices: [.ours]), "avant\nnotre ligne\napres\n", "choix ours")
    expect(ConflictParser.render(segments, choices: [.theirs]), "avant\nleur ligne\napres\n", "choix theirs")
    expect(ConflictParser.render(segments, choices: [.both]), "avant\nnotre ligne\nleur ligne\napres\n", "choix both")
    expect(ConflictParser.render(segments, choices: [.bothReversed]), "avant\nleur ligne\nnotre ligne\napres\n", "both inversé")
    // un conflit non résolu doit se re-sérialiser tel quel (hors section base renommée)
    let simple = "a\n<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> topic\nb\n"
    expect(ConflictParser.render(ConflictParser.parse(simple), choices: [nil]), simple, "aller-retour sans modification")
    // marqueur isolé, sans fin : traité comme du texte
    expect(ConflictParser.conflictCount(ConflictParser.parse("<<<<<<< orphelin\nrien\n")), 0, "marqueur orphelin")
}

await group("merge réel avec conflit, résolution et continuation") {
    let (git, dir) = try await makeRepo()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write("un\ndeux\ntrois\n", "f.txt", in: dir)
    try await commitAll(git, "base")
    try await git.run(["switch", "-q", "-c", "topic"])
    try write("un\nDEUX topic\ntrois\n", "f.txt", in: dir)
    try await commitAll(git, "topic")
    try await git.run(["switch", "-q", "main"])
    try write("un\nDEUX main\ntrois\n", "f.txt", in: dir)
    try await commitAll(git, "main")

    var failed = false
    do { try await git.run(["merge", "topic"]) } catch { failed = true }
    expect(failed, true, "le merge s’arrête sur un conflit")
    expect(await git.currentOperation(), .merge, "opération détectée: merge")

    let status = GitParsing.parseStatus(try await git.run(["status", "--porcelain=v2", "-z", "--branch"]))
    expect(status.changes.filter(\.isConflicted).map(\.path), ["f.txt"], "fichier en conflit détecté")

    let content = try String(contentsOf: dir.appendingPathComponent("f.txt"), encoding: .utf8)
    let segments = ConflictParser.parse(content)
    expect(ConflictParser.conflictCount(segments), 1, "un bloc dans le fichier réel")
    try write(ConflictParser.render(segments, choices: [.both]), "f.txt", in: dir)
    try await git.run(["add", "--", "f.txt"])
    try await git.run(RepoOperation.merge.continueArguments!)
    expect(await git.currentOperation(), .none, "merge terminé")
    let final = try String(contentsOf: dir.appendingPathComponent("f.txt"), encoding: .utf8)
    expect(final, "un\nDEUX main\nDEUX topic\ntrois\n", "contenu résolu")
}

await group("rebase interactif: reword + squash + drop") {
    let (git, dir) = try await makeRepo()
    defer { try? FileManager.default.removeItem(at: dir) }
    for (name, msg) in [("a", "A"), ("b", "B"), ("c", "C"), ("d", "D")] {
        try write(name, "\(name).txt", in: dir)
        try await commitAll(git, msg)
    }
    let list = try await git.run(["log", "--reverse", "--no-merges", RebasePlanner.logFormat, "HEAD~3..HEAD"])
    var entries = RebasePlanner.parseEntries(list)
    expect(entries.map(\.subject), ["B", "C", "D"], "entrées lues")
    entries[0].action = .reword; entries[0].newMessage = "B renommé"
    entries[1].action = .squash
    entries[2].action = .drop
    try await git.interactiveRebase(onto: "HEAD~3", entries: entries)

    let subjects = try await git.run(["log", "--format=%s"]).split(separator: "\n").map(String.init)
    expect(subjects.first, "B renommé", "reword appliqué")
    expect(subjects.count, 2, "B+C squashés, D supprimé")
    expect(try await git.run(["status", "--porcelain"]), "", "arbre propre")
    expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("c.txt").path), true, "c.txt conservé (squash)")
    expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("d.txt").path), false, "d.txt supprimé (drop)")

    expect(RebasePlanner.validate([RebaseEntry(id: "1", shortID: "1", subject: "x", action: .squash)]) != nil, true, "premier commit squash refusé")
}

await group("stash et worktrees") {
    let (git, dir) = try await makeRepo()
    defer { try? FileManager.default.removeItem(at: dir) }
    try write("1\n", "f.txt", in: dir)
    try await commitAll(git, "init")
    try write("2\n", "f.txt", in: dir)
    try write("neuf\n", "new.txt", in: dir)
    try await git.run(["stash", "push", "-u", "-m", "wip test"])
    let stashes = GitLists.parseStashes(try await git.run(["stash", "list", GitLists.stashFormat]))
    expect(stashes.count, 1, "un stash")
    expect(stashes.first?.ref, "stash@{0}", "ref du stash")
    expect(stashes.first?.message.contains("wip test"), true, "message du stash")
    try await git.run(["stash", "pop", "stash@{0}"])
    expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.txt").path), true, "stash -u restaure les fichiers non suivis")

    let wt = dir.deletingLastPathComponent().appendingPathComponent("tsuta-wt-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: wt) }
    try await git.run(["worktree", "add", "-q", "-b", "wt-branch", wt.path])
    let trees = GitLists.parseWorktrees(try await git.run(["worktree", "list", "--porcelain"]))
    expect(trees.count, 2, "deux worktrees")
    expect(trees.first?.isMain, true, "le premier est le principal")
    expect(trees.last?.branch, "wt-branch", "branche du worktree")
}

await group("forges: parsing GitHub / GitLab") {
    let gh = """
    [{"number":12,"title":"Ajoute X","author":{"login":"alex"},"headRefName":"feat/x","baseRefName":"main",
      "url":"https://github.com/o/r/pull/12","isDraft":true,"updatedAt":"2026-10-14T10:00:00Z",
      "reviewDecision":"APPROVED","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"},{"state":"PENDING"}]},
     {"number":13,"title":"Casse Y","author":{"login":"bob"},"headRefName":"fix/y","baseRefName":"main",
      "url":"u","isDraft":false,"updatedAt":"2026-10-14T11:00:00Z","reviewDecision":"",
      "statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}]
    """
    let list = ForgeParsing.parseGitHubList(gh)
    expect(list.count, 2, "deux PR")
    expect(list[0].author, "alex", "auteur")
    expect(list[0].isDraft, true, "brouillon")
    expect(list[0].checks, .pending, "checks en attente")
    expect(list[0].decision, "APPROVED", "décision")
    expect(list[1].checks, .failing, "checks en échec")
    expect(list[1].decision, nil, "pas de décision")

    let discussion = ForgeParsing.parseGitHubDiscussion("""
    {"comments":[{"author":{"login":"a"},"body":"salut","createdAt":"2026-10-14T10:00:00Z"}],
     "reviews":[{"author":{"login":"b"},"body":"ok","state":"APPROVED","submittedAt":"2026-10-14T12:00:00Z"},
                {"author":{"login":"c"},"body":"","state":"COMMENTED","submittedAt":"2026-10-14T13:00:00Z"}]}
    """)
    expect(discussion.map(\.author), ["a", "b"], "discussion triée, review vide ignorée")
    let inline = ForgeParsing.parseGitHubInline("""
    [{"id":7,"user":{"login":"d"},"body":"ici","path":"a.swift","line":42,"created_at":"2026-10-14T10:00:00Z"}]
    """)
    expect(inline.first?.path, "a.swift", "commentaire inline: chemin")
    expect(inline.first?.line, 42, "commentaire inline: ligne")

    let gl = ForgeParsing.parseGitLabList("""
    [{"iid":3,"title":"MR","author":{"username":"carl"},"source_branch":"s","target_branch":"t","web_url":"w","draft":false,"updated_at":"2026-10-14T10:00:00.000Z"}]
    """)
    expect(gl.first?.number, 3, "MR GitLab")
    expect(gl.first?.author, "carl", "auteur GitLab")
    expect(ForgeKind.detect(remoteURL: "git@github.com:o/r.git"), .github, "détection GitHub")
    expect(ForgeKind.detect(remoteURL: "https://gitlab.example.com/g/p.git"), .gitlab, "détection GitLab")
    expect(ForgeKind.detect(remoteURL: "https://example.com/x.git"), nil, "forge inconnue")
}

await group("IA: prompts et réponse réelle") {
    expect(AIPrompts.stripFence("```\nfeat: x\n```"), "feat: x", "retire la clôture Markdown")
    expect(AIPrompts.stripFence("feat: x"), "feat: x", "texte brut inchangé")
    let prompt = AIPrompts.commitMessage(stagedDiff: "diff --git a/x b/x", recentSubjects: ["Fix a", "Add b"])
    expect(prompt.contains("<diff>") && prompt.contains("- Fix a"), true, "prompt de commit")
    expect(AIPrompts.clip(String(repeating: "x", count: 30_000)).hasSuffix("(tronqué)"), true, "troncature")

    if AIBackend.claude.isAvailable {
        let answer = try await AIRunner.ask("Réponds uniquement par le mot : pong", backend: .claude, timeout: 90)
        expect(answer.lowercased().contains("pong"), true, "Claude répond via le CLI")
    } else {
        print("  (claude absent : test réel ignoré)")
    }
}

await group("forge réelle: gh") {
    let (_, dir) = try await makeRepo()
    defer { try? FileManager.default.removeItem(at: dir) }
    expect(ProcessRunner.resolve("gh") != nil, true, "gh introuvable")
    let client = ForgeClient(kind: .github, root: dir)
    var failedCleanly = false
    do { _ = try await client.list() } catch { failedCleanly = !(error.localizedDescription.isEmpty) }
    expect(failedCleanly, true, "dépôt sans remote GitHub : erreur lisible, pas de crash")
}

// MARK: - staging partiel, sous-modules, filtre, console, sessions d'agents

await group("staging par ligne et par hunk (git apply --cached)") {
    let (git, dir) = try await makeRepo()
    defer { try? FileManager.default.removeItem(at: dir) }
    let original = (1...12).map { "ligne \($0)" }.joined(separator: "\n") + "\n"
    try write(original, "f.txt", in: dir)
    try await commitAll(git, "base")

    // deux hunks éloignés : on change les lignes 2 et 3 en haut, la ligne 11 en bas
    var changed = (1...12).map { "ligne \($0)" }
    changed[1] = "ligne 2 MODIFIÉE"
    changed.insert("ligne ajoutée", at: 3)
    changed[11] = "ligne 11 MODIFIÉE"
    try write(changed.joined(separator: "\n") + "\n", "f.txt", in: dir)

    func workingDiff() async throws -> DiffFile {
        GitParsing.parseDiff(try await git.run(["diff", "--no-ext-diff", "--", "f.txt"]))[0]
    }
    func cachedDiff() async throws -> [DiffFile] {
        GitParsing.parseDiff(try await git.run(["diff", "--cached", "--no-ext-diff", "--", "f.txt"]))
    }

    let file = try await workingDiff()
    expect(file.hunks.count, 2, "deux hunks détectés")

    // 1. un seul hunk (le premier)
    let patchHunk = PatchBuilder.patch(for: file.hunks[0], in: file, direction: .stage)!
    try await git.run(PatchBuilder.Direction.stage.applyArguments, stdin: patchHunk)
    var staged = try await cachedDiff()
    expect(staged.first?.hunks.count, 1, "un seul hunk indexé")
    expect(staged.first?.additions, 2, "le hunk contient 2 ajouts (modif + insertion)")
    var rest = try await workingDiff()
    expect(rest.hunks.count, 1, "il reste le hunk du bas dans le working tree")

    // 2. désindexer une seule ligne du hunk indexé : l'ajout « ligne ajoutée »
    let addedID = staged[0].lines.first { $0.kind == .added && $0.text == "ligne ajoutée" }!.id
    let unstagePatch = PatchBuilder.patch(for: staged[0], selected: [addedID], direction: .unstage)!
    try await git.run(PatchBuilder.Direction.unstage.applyArguments, stdin: unstagePatch)
    staged = try await cachedDiff()
    expect(staged.first?.lines.contains { $0.kind == .added && $0.text == "ligne ajoutée" }, false, "la ligne n’est plus indexée")
    expect(staged.first?.lines.contains { $0.kind == .added && $0.text == "ligne 2 MODIFIÉE" }, true, "le reste du hunk reste indexé")

    // 3. indexer une seule ligne depuis le working tree
    rest = try await workingDiff()
    let target = rest.lines.first { $0.kind == .added && $0.text == "ligne ajoutée" }!.id
    let linePatch = PatchBuilder.patch(for: rest, selected: [target], direction: .stage)!
    try await git.run(PatchBuilder.Direction.stage.applyArguments, stdin: linePatch)
    staged = try await cachedDiff()
    expect(staged.first?.lines.contains { $0.kind == .added && $0.text == "ligne ajoutée" }, true, "ligne unique indexée")
    expect(staged.first?.lines.contains { $0.kind == .added && $0.text == "ligne 11 MODIFIÉE" }, false, "le hunk du bas n’est pas indexé")

    // rien de sélectionné -> pas de patch
    expect(PatchBuilder.patch(for: rest, selected: [], direction: .stage) == nil, true, "sélection vide")

    // l'index final doit rester un fichier valide : on commit et on vérifie le contenu du commit
    try await git.run(["commit", "-q", "-m", "partiel"])
    let committed = try await git.run(["show", "HEAD:f.txt"])
    expect(committed.contains("ligne ajoutée") && committed.contains("ligne 2 MODIFIÉE"), true, "contenu du commit partiel")
    expect(committed.contains("ligne 11 MODIFIÉE"), false, "le reste n’est pas dans le commit")
}

await group("sous-modules, filtre d'historique, console") {
    let subs = GitParsing.parseSubmodules("""
     1111111111111111111111111111111111111111 libs/ok (v1.0)
    -2222222222222222222222222222222222222222 libs/vide
    +3333333333333333333333333333333333333333 libs/modifie (heads/main)
    U4444444444444444444444444444444444444444 libs/conflit
    """)
    expect(subs.map(\.state), [.upToDate, .uninitialized, .modified, .conflicted], "états des sous-modules")
    expect(subs[0].describe, "v1.0", "describe")
    expect(subs[1].path, "libs/vide", "chemin")

    let commits = [commit("a", []), commit("b", ["a"])]
    var filter = HistoryFilter(text: "b")
    expect(filter.apply(to: commits).map(\.id), ["b"], "filtre texte")
    filter = HistoryFilter(text: "", author: "nobody")
    expect(filter.apply(to: commits).count, 0, "filtre auteur")
    expect(HistoryFilter().apply(to: commits).count, 2, "filtre inactif")

    final class Sink: @unchecked Sendable { var records: [GitCommandRecord] = [] }
    let sink = Sink()
    let (_, dir) = try await makeRepo()
    defer { try? FileManager.default.removeItem(at: dir) }
    let observed = GitClient(root: dir, observer: { sink.records.append($0) })
    try await observed.run(["rev-parse", "--is-inside-work-tree"])
    _ = try? await observed.run(["checkout", "n-existe-pas"])
    expect(sink.records.count, 2, "deux commandes enregistrées")
    expect(sink.records.first?.commandLine, "git rev-parse --is-inside-work-tree", "ligne de commande")
    expect(sink.records.last?.status != 0, true, "échec enregistré")
}

await group("sessions Claude Code / Codex sur disque") {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agents-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = "/Users/test/mon.projet"
    let folder = root.appendingPathComponent("claude").appendingPathComponent(AgentSessionScanner.claudeFolderName(for: repo))
    expect(AgentSessionScanner.claudeFolderName(for: repo), "-Users-test-mon-projet", "encodage du chemin")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let lines = [
        #"{"type":"user","cwd":"/Users/test/mon.projet","gitBranch":"feature/x","isSidechain":false,"message":{"content":"Ajoute un bouton"}}"#,
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}"#,
        #"{"type":"ai-title","aiTitle":"Bouton d’export","sessionId":"abc"}"#,
        #"{"type":"user","isSidechain":false,"message":{"content":[{"type":"text","text":"merci"}]}}"#,
        #"{"type":"user","isSidechain":true,"message":{"content":"sous-agent"}}"#,
    ]
    try lines.joined(separator: "\n").write(to: folder.appendingPathComponent("abc.jsonl"), atomically: true, encoding: .utf8)

    let codexDay = root.appendingPathComponent("codex/2026/10/14")
    try FileManager.default.createDirectory(at: codexDay, withIntermediateDirectories: true)
    try #"{"type":"session_meta","payload":{"id":"cdx-1","cwd":"/Users/test/mon.projet","instructions":"Corrige le bug"}}"#
        .write(to: codexDay.appendingPathComponent("rollout-1.jsonl"), atomically: true, encoding: .utf8)

    let found = AgentSessionScanner.sessions(directories: [repo],
                                             claudeProjects: root.appendingPathComponent("claude"),
                                             codexSessions: root.appendingPathComponent("codex"))
    expect(found.count, 2, "une session Claude + une session Codex")
    let claude = found.first { $0.agent == .claudeCode }
    expect(claude?.title, "Bouton d’export", "titre IA de la session")
    expect(claude?.branch, "feature/x", "branche")
    expect(claude?.messageCount, 2, "sous-agents exclus du décompte")
    expect(claude?.resumeCommand, "claude --resume abc", "commande de reprise")
    expect(found.first { $0.agent == .codex }?.resumeCommand, "codex resume cdx-1", "reprise Codex")
}

print(failures == 0 ? "\nTout est OK (\(checks) vérifications)" : "\n\(failures) échec(s) sur \(checks) vérifications")
exit(failures == 0 ? 0 : 1)

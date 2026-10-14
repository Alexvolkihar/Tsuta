# Architecture

[English](ARCHITECTURE.md) · [Français](ARCHITECTURE.fr.md)

Tsuta is a Swift package with three targets. The rule: **the core knows nothing about the interface**, and
the interface only talks to Git through the core.

```
Sources/
├── TsutaCore/            library, no UI dependency
│   ├── Git/              GitClient, ProcessRunner, models, parsing, PatchBuilder
│   ├── Graph/            GraphLayout (lane assignment)
│   ├── Operations/       conflicts, interactive rebase, stash, worktrees, operation state
│   ├── Forge/            ForgeClient (gh / glab) and JSON parsing
│   └── Assistant/        AIBackend / AIRunner / AIPrompts, AgentSessionScanner
├── Tsuta/                the SwiftUI application
│   ├── App/              TsutaApp, AppModel (tabs), AppSettings, LaunchOptions
│   ├── Session/          RepoSession (+ one extension per domain), RepositoryWatcher
│   ├── DesignSystem/     Theme, zoom, components (avatars, chips, cards)
│   └── Features/         Shell, History, Changes, Diff, Conflicts, Rebase, Reviews, Assistant, Sidebar
└── tsuta-selftest/       executable checks on real repositories
```

## Data flow

```
SwiftUI view ──action──▶ RepoSession (+Changes, +History, +Operations, +Undo)
                              │  perform { git in … }
                              ▼
                         GitClient ──▶ /usr/bin/git        (the console is fed by an observer)
                              │
                              ▼
                      GitParsing / GraphLayout ──▶ immutable models ──▶ @Observable ──▶ view
```

- **One entry point to Git**: `GitClient.run`. Everything goes through `ProcessRunner`, which never blocks
  the main thread (calls are detached) and records every command.
- **Immutable models** (`Commit`, `FileChange`, `DiffFile`…): views mutate nothing. They call methods on
  `RepoSession`, which refreshes its state after each mutation.
- **One `RepoSession` per repository, one `AppModel` for the window.** Tabs are independent sessions.
  Reviews (`ReviewsModel`) and AI (`AssistantModel`) are separate models so the session does not grow
  into a god object.
- **Refresh**: `RepositoryWatcher` (FSEvents) listens to the folder, ignores git's own noise (objects, logs,
  lock files) and merges bursts of events.

## Notable choices

- **Partial staging.** `PatchBuilder` rebuilds a patch from the checked lines (unselected lines are turned
  into context or dropped depending on the direction), then `git apply --cached --recount`, or `-R` to
  unstage.
- **Interactive rebase without an editor.** The todo list is injected through `GIT_SEQUENCE_EDITOR`; a
  `reword` becomes `pick` + `exec git commit --amend -F <file>`.
- **Forges and AI through CLIs.** No token, no OAuth: the authentication of `gh`, `glab`, `claude` and
  `codex` is reused.
- **Agent sessions.** Read-only, from `~/.claude/projects` and `~/.codex/sessions`; identifiers are
  validated before they go into a shell command.
- **No `@State`.** The Command Line Tools do not ship the `@State` macro plugin. Local state goes through
  `@StateObject` and `ObservableObject`, shared state through `@Observable`.

## Adding a feature

1. Put the parsing or pure logic in `TsutaCore`, with its check in `tsuta-selftest` (on a real temporary
   repository when Git is involved).
2. Expose a method in the matching `RepoSession` extension.
3. Build the view in `Features/<Domain>`, using `.ui(...)` for fonts (zoom) and `Theme` for colors.

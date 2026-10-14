<div align="center">

<img src="Resources/AppIcon-source.png" width="128" alt="Tsuta icon" />

# Tsuta

**English** · [Français](README.fr.md)

**A native Git client for macOS. Fast, and no account.**<br/>
Commit graph, line-by-line staging, conflict resolution, interactive rebase,<br/>
GitHub / GitLab reviews and coding agents (Claude Code, Codex) in one window.

[![CI](https://github.com/Alexvolkihar/Tsuta/actions/workflows/ci.yml/badge.svg)](https://github.com/Alexvolkihar/Tsuta/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
[![MIT license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<img src="docs/screenshots/history.png" width="900" alt="History: commit graph, diff and commit details" />

</div>

## Why Tsuta

- **Native.** SwiftUI and AppKit, a 4 MB binary, no Electron.
- **Faithful to Git.** Tsuta does not reimplement Git. It drives the `git` binary on your Mac, so hooks,
  config, worktrees and submodules behave exactly as they do in your terminal.
- **Transparent.** Every command it runs shows up in the Git console (`⌘J`).
- **No server, no account.** No telemetry and no API key. Forges go through `gh` / `glab`, AI goes through
  the `claude` / `codex` CLIs that are already installed and signed in on your machine.
- **French interface, for now.** The UI strings are not translated yet.

## Features

| | |
|---|---|
| **History** | Colored commit lanes, HEAD / branch / tag chips, avatars, filter by message, SHA, branch, tag or author, commit details. Context menu: cherry-pick, revert, detached checkout, reset, interactive rebase. |
| **Changes** | Index and working tree, **staging by hunk or by line** (new files too), undoable discard, commit and amend, stash. The view updates by itself when files change elsewhere. |
| **Blame and file history** | Per-line blame with uncommitted lines marked, file history that follows renames, jump from a blame line to its commit. |
| **Conflicts** | Per-block editor (ours / theirs / both / both reversed), diff3 support, AI suggestion for a block, Continue / Abort banner for merge, rebase, cherry-pick and revert. |
| **Interactive rebase** | pick, reword, squash, fixup, drop, reorder by drag and drop. No editor is ever opened. |
| **Reviews** | GitHub pull requests and GitLab merge requests: checks, decision, diff with **inline comments**, discussion, comment, approve, request changes, merge. Local copy for offline reading. |
| **Agents** | The **Claude Code** and **Codex** sessions that worked in the repository and its worktrees, with one-click resume in Terminal. |
| **AI** | Commit message from the staged diff, commit explanation, review summary, conflict block suggestion. |
| **Branches** | Switch, merge and rebase by **dragging** one branch onto another. Worktrees, submodules and stashes in the sidebar. |
| **Comfort** | Tabs for several repositories, command palette (`⌘K`), zoom (`⌘+` / `⌘-`), light and dark, settings. |
| **Undo** (`⌥⌘Z`) | Commits, amends, rebases, merges, pulls, resets, cherry-picks, reverts and discarded files. It refuses when history moved since. |

<div align="center">
<img src="docs/screenshots/changes.png" width="900" alt="Changes: staging by hunk and by line" />
</div>

## Install

### From a release

1. Download `Tsuta-<version>-macos.zip` from the [Releases](https://github.com/Alexvolkihar/Tsuta/releases) page.
2. Unzip it and drag `Tsuta.app` to `/Applications`.
3. The app is not notarized. On first launch, right click and choose **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Tsuta.app
   ```

### From source

Swift 6 and macOS 14 are enough. The Command Line Tools work without Xcode.

```sh
git clone https://github.com/Alexvolkihar/Tsuta.git
cd Tsuta
./scripts/build-app.sh      # → build/Tsuta.app
open build/Tsuta.app
```

`./scripts/package.sh --universal` also produces an Apple Silicon + Intel zip.

## Optional tools

| Feature | Tool |
|---|---|
| GitHub reviews | [`gh`](https://cli.github.com), signed in (`gh auth login`) |
| GitLab reviews | [`glab`](https://gitlab.com/gitlab-org/cli), signed in |
| AI and sessions | [Claude Code](https://claude.ai/code) (`claude`) and / or Codex (`codex`) |

Everything else works without them.

## Privacy and security

- Tsuta opens **no network connection** itself. Only `git`, `gh`, `glab` and the AI CLIs do.
- When you ask for a generation, the relevant diff is sent to **the AI tool you picked**, started on your
  Mac with your own account.
- Claude is started **without tools** (`--tools ""`) and outside the repository, so an instruction hidden in
  a diff can neither read nor change your files: the model only returns text. Diffs are presented to the model
  as data, never as instructions.
- Git commands run with `--no-optional-locks` and without interactive prompts.
- The app is not sandboxed: it has to run `git` and read your repositories.

## Development

```sh
swift build                  # build everything
swift run tsuta-selftest     # 148 checks on real git repositories
./scripts/build-app.sh       # package the app
```

The tests are an executable (`tsuta-selftest`) because XCTest and swift-testing do not ship with the Command
Line Tools. They create real temporary repositories: merges with conflicts, interactive rebase, partial
staging through `git apply --cached`, stash, worktrees.

Tsuta can take its own screenshots, with no screen recording permission:

```sh
Tsuta --open /path/to/repo --mode changes --snapshot out.png --size 1280x800
```

The architecture is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Known limits

- The GitLab (`glab`) and Codex paths are covered by parser tests on sample output but have not been run
  against the real tools.
- Blame does not follow lines moved between files.
- Undo only works while the repository is where the action left it, on the same branch.
- The app is not notarized.

## Roadmap

- English interface
- Notarization and automatic updates
- Automated UI tests

Contributions are welcome: please open an issue before a large change.

## License

[MIT](LICENSE) © 2026 Alexvolkihar

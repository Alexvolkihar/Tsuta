# Architecture

Hanko est un paquet Swift en trois cibles. La règle : **le cœur ne connaît pas l'interface**, et
l'interface ne parle à Git que par le cœur.

```
Sources/
├── HankoCore/            bibliothèque, aucune dépendance UI
│   ├── Git/              GitClient, ProcessRunner, modèles, parsing, PatchBuilder
│   ├── Graph/            GraphLayout (attribution des lanes)
│   ├── Operations/       Conflicts, rebase interactif, stash, worktrees, état d'opération
│   ├── Forge/            ForgeClient (gh / glab) et parsing JSON
│   └── Assistant/        AIBackend / AIRunner / AIPrompts, AgentSessionScanner
├── Hanko/                l'application SwiftUI
│   ├── App/              HankoApp, AppModel (onglets), AppSettings, LaunchOptions
│   ├── Session/          RepoSession (+ extensions par domaine), RepositoryWatcher
│   ├── DesignSystem/     Theme, zoom, composants (avatars, chips, cartes)
│   └── Features/         Shell, History, Changes, Diff, Conflicts, Rebase, Reviews, Assistant, Sidebar
└── hanko-selftest/       vérifications exécutables sur de vrais dépôts
```

## Flux de données

```
Vue SwiftUI ──action──▶ RepoSession (+Changes, +History, +Operations, +Undo)
                              │  perform { git in … }
                              ▼
                         GitClient ──▶ /usr/bin/git        (console Git alimentée par l'observer)
                              │
                              ▼
                      GitParsing / GraphLayout ──▶ modèles immuables ──▶ @Observable ──▶ Vue
```

- **Un seul point d'entrée vers Git** : `GitClient.run`. Tout passe par `ProcessRunner`, qui ne
  bloque jamais le thread principal (les appels sont détachés) et enregistre chaque commande.
- **Modèles immuables** (`Commit`, `FileChange`, `DiffFile`…) : les vues ne mutent rien, elles
  appellent des méthodes de `RepoSession`, qui rafraîchit l'état après chaque mutation.
- **`RepoSession` par dépôt, `AppModel` pour la fenêtre.** Les onglets sont des sessions
  indépendantes ; reviews (`ReviewsModel`) et IA (`AssistantModel`) sont des modèles séparés pour
  ne pas gonfler la session.
- **Rafraîchissement** : `RepositoryWatcher` (FSEvents) écoute le dossier, ignore le bruit interne
  de `.git` (objects, logs, verrous) et regroupe les rafales d'événements.

## Choix notables

- **Indexation partielle.** `PatchBuilder` reconstruit un patch à partir des lignes cochées
  (les lignes non sélectionnées sont neutralisées en contexte ou retirées selon le sens) puis
  `git apply --cached --recount`, ou `-R` pour désindexer.
- **Rebase interactif sans éditeur.** Le todo est injecté par `GIT_SEQUENCE_EDITOR` ; un `reword`
  devient `pick` + `exec git commit --amend -F <fichier>`.
- **Forges et IA par CLI.** Pas de jeton, pas d'OAuth : on réutilise l'authentification de `gh`,
  `glab`, `claude` et `codex`.
- **Sessions d'agents.** Lues en lecture seule dans `~/.claude/projects` et `~/.codex/sessions` ;
  les identifiants sont validés avant d'être placés dans une commande shell.
- **Pas de `@State`.** Les Command Line Tools ne livrent pas le plugin de la macro `@State` ;
  l'état local passe par `@StateObject` + `ObservableObject`, et l'état partagé par `@Observable`.

## Ajouter une fonctionnalité

1. Ajoute le parsing / la logique pure dans `HankoCore`, avec sa vérification dans `hanko-selftest`
   (sur un vrai dépôt temporaire si Git est impliqué).
2. Expose une méthode dans l'extension de `RepoSession` correspondante.
3. Crée la vue dans `Features/<Domaine>`, avec `.ui(...)` pour les polices (zoom) et `Theme` pour
   les couleurs.

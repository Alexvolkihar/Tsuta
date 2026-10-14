import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        SnapshotRunner.schedule(LaunchOptions.current)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HankoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@State` is a macro that Command Line Tools do not ship; the App value is created once anyway.
    private let model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.uiZoom, model.settings.zoom)
                .tint(Theme.accent)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .environment(\.uiZoom, 1)
                .tint(Theme.accent)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Ouvrir un dépôt…") { model.chooseRepository() }.keyboardShortcut("o")
            Menu("Dépôts récents") {
                ForEach(model.recent, id: \.self) { url in
                    Button(url.lastPathComponent) { Task { await model.open(url) } }
                }
            }
            Divider()
            Button("Fermer l’onglet") { if let s = model.active { model.close(s) } }
                .keyboardShortcut("w")
                .disabled(model.active == nil)
        }
        CommandMenu("Dépôt") {
            Button("Palette de commandes…") { model.showPalette = true }.keyboardShortcut("k")
            Divider()
            Button("Actualiser") { Task { await model.active?.refresh() } }.keyboardShortcut("r")
            Button("Fetch") { Task { await model.active?.fetch() } }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Pull") { Task { await model.active?.pull() } }
            Button("Push") { Task { await model.active?.push() } }
            Divider()
            Button(model.active?.undoTitle ?? "Annuler la dernière action Git") { Task { await model.active?.undo() } }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(model.active?.undoTitle == nil)
        }
        CommandMenu("Afficher") {
            ForEach(Array(RepoSession.Mode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.title) { Task { await model.active?.setMode(mode) } }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
            Button("Console Git") { model.active?.showConsole.toggle() }.keyboardShortcut("j")
            Divider()
            Button("Agrandir") { model.settings.zoomIn() }.keyboardShortcut("+")
            Button("Réduire") { model.settings.zoomOut() }.keyboardShortcut("-")
            Button("Taille normale") { model.settings.resetZoom() }.keyboardShortcut("0")
            Divider()
            Button("Onglet suivant") { model.select(offset: 1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Onglet précédent") { model.select(offset: -1) }.keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}

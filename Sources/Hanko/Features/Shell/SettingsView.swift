import HankoCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Affichage") {
                HStack {
                    Slider(value: $settings.zoom, in: AppSettings.zoomRange, step: 0.1) { Text("Taille de l’interface") }
                    Text("\(Int((settings.zoom * 100).rounded())) %").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                Toggle("Masquer les changements d’espaces dans les diffs", isOn: $settings.hideWhitespaceChanges)
                Text("Désactive l’indexation par hunk ou par ligne, qui exige le diff exact.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Git") {
                Picker("Commits chargés", selection: $settings.commitLimit) {
                    ForEach(AppSettings.commitLimits, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Stratégie de pull", selection: $settings.pullStrategy) {
                    ForEach(AppSettings.pullStrategies, id: \.id) { Text($0.title).tag($0.id) }
                }
                Picker("Fetch automatique", selection: $settings.autoFetchMinutes) {
                    Text("Jamais").tag(0)
                    Text("Toutes les 5 min").tag(5)
                    Text("Toutes les 15 min").tag(15)
                    Text("Toutes les 30 min").tag(30)
                }
            }
            Section("Assistant") {
                Picker("Outil IA", selection: Binding(get: { settings.agent?.rawValue ?? "" },
                                                      set: { settings.preferredAgent = $0 })) {
                    ForEach(AIBackend.allCases) { backend in
                        Text(backend.title + (backend.isAvailable ? "" : " (non installé)")).tag(backend.rawValue)
                    }
                }
                Text("L’outil est lancé sur ce Mac avec ton propre compte. Hanko n’envoie rien ailleurs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: AppInfo.version)
                Link("Code source", destination: AppInfo.repositoryURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
    }
}

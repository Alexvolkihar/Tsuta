import TsutaCore
import SwiftUI

/// Every git command Tsuta ran, newest at the bottom: nothing the app does is hidden.
struct ConsoleView: View {
    let session: RepoSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Console Git", systemImage: "terminal").ui(12, .semibold)
                Text("\(session.console.count) commandes").ui(11).foregroundStyle(.tertiary)
                Spacer()
                IconButton(symbol: "trash", help: "Vider") { session.consoleReset() }
                IconButton(symbol: "xmark", help: "Fermer (⌘J)") { session.showConsole = false }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.console) { record in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(record.date.formatted(date: .omitted, time: .standard)).foregroundStyle(.tertiary)
                                Image(systemName: record.status == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(record.status == 0 ? Color.green : Color.red)
                                Text(record.commandLine).textSelection(.enabled).lineLimit(2)
                                Spacer(minLength: 8)
                                Text("\(Int(record.duration * 1000)) ms").foregroundStyle(.tertiary)
                            }
                            .ui(11, mono: true)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .id(record.id)
                            if let error = record.errorText, !error.isEmpty {
                                Text(error.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .ui(11, mono: true).foregroundStyle(.red).padding(.horizontal, 34)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: session.console.count) {
                    if let last = session.console.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

import HankoCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            Divider()
            Group {
                if let session = model.active {
                    SessionView(session: session)
                        .id(session.id)
                } else {
                    WelcomeView()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .hankoOpenRepository)) { note in
            if let url = note.object as? URL { Task { await model.open(url) } }
        }
        .sheet(isPresented: Binding(get: { model.showPalette }, set: { model.showPalette = $0 })) {
            CommandPalette()
        }
        .alert(AppInfo.name, isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
    }
}

// MARK: Tabs

struct TabBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            // Room for the traffic lights, which sit over the content with a hidden title bar.
            Color.clear.frame(width: 76, height: 1)
            ForEach(model.sessions) { session in
                RepoTab(session: session, isActive: session.id == model.activeID)
            }
            IconButton(symbol: "plus", help: "Ouvrir un dépôt (⌘O)") { model.chooseRepository() }
            Spacer(minLength: 0)
            if model.active != nil {
                IconButton(symbol: "magnifyingglass", help: "Palette de commandes (⌘K)") { model.showPalette = true }
            }
        }
        .padding(.trailing, 10)
        .frame(height: 38)
        .background(.bar)
    }
}

struct RepoTab: View {
    @Environment(AppModel.self) private var model
    let session: RepoSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").ui(11).foregroundStyle(isActive ? Theme.accent : .secondary)
            Text(session.name).ui(12.5, isActive ? .semibold : .regular).lineLimit(1)
            if session.status.changes.count > 0 {
                CountBadge(count: session.status.changes.count, tint: .orange)
            }
            Button { model.close(session) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Fermer")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isActive ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.activeID = session.id }
    }
}

// MARK: Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(Theme.accent)
            VStack(spacing: 4) {
                Text(AppInfo.name).ui(30, .semibold)
                Text(AppInfo.tagline).ui(14).foregroundStyle(.secondary)
            }
            Button { model.chooseRepository() } label: {
                Label("Ouvrir un dépôt", systemImage: "folder").ui(13, .medium).padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(title: "Récents").padding(.bottom, 4)
                    ForEach(model.recent.prefix(6), id: \.self) { url in
                        Button { Task { await model.open(url) } } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.tertiary)
                                Text(url.lastPathComponent).ui(13, .medium)
                                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                    .ui(11.5).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 380)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

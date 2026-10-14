import HankoCore
import SwiftUI

struct AvatarView: View {
    let name: String
    let email: String
    var size: CGFloat = 20

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.avatarColor(for: email.isEmpty ? name : email), in: Circle())
            .accessibilityLabel(name)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return (letters.isEmpty ? String(name.prefix(1)) : letters).uppercased()
    }
}

struct RefChip: View {
    let label: RefLabel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text(label.name).lineLimit(1)
        }
        .ui(10.5, .medium)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 0.5))
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch label.kind {
        case .head: "location.fill"
        case .local: "arrow.triangle.branch"
        case .remote: "cloud.fill"
        case .tag: "tag.fill"
        }
    }

    private var color: Color {
        switch label.kind {
        case .head: Theme.accent
        case .local: Color(red: 0.30, green: 0.72, blue: 0.45)
        case .remote: Color(red: 0.96, green: 0.62, blue: 0.20)
        case .tag: Color(red: 0.62, green: 0.45, blue: 0.92)
        }
    }
}

struct CountBadge: View {
    let count: Int
    var tint: Color = .secondary

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .ui(10, .semibold)
                .foregroundStyle(tint)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(tint.opacity(0.15), in: Capsule())
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).ui(12, .medium).frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(title).ui(14, .semibold)
            Text(message).ui(12).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SectionLabel: View {
    let title: String
    var count: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).ui(10.5, .semibold).foregroundStyle(.secondary).tracking(0.6)
            CountBadge(count: count)
            Spacer(minLength: 0)
        }
    }
}

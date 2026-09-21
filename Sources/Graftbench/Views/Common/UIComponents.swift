import SwiftUI

// MARK: - Author avatar

struct AuthorAvatar: View {
    let name: String
    let email: String
    var size: CGFloat = 24

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased().isEmpty ? "?" : letters.joined().uppercased()
    }

    private var color: Color {
        let palette = Theme.laneColors
        let hash = abs(email.isEmpty ? name.hashValue : email.hashValue)
        return palette[hash % palette.count]
    }

    var body: some View {
        Circle()
            .fill(color.gradient)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Ref pill

struct RefPill: View {
    let ref: CommitRef

    private var color: Color {
        switch ref.kind {
        case .head: return Theme.stateAdded
        case .localBranch: return Theme.accent
        case .remoteBranch: return Color(hex: 0x6C9CF0)
        case .tag: return Theme.stateModified
        case .stash: return Color.secondary
        }
    }

    private var icon: String {
        switch ref.kind {
        case .head: return "smallcircle.filled.circle"
        case .localBranch: return "arrow.triangle.branch"
        case .remoteBranch: return "cloud"
        case .tag: return "tag.fill"
        case .stash: return "tray.full"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(ref.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.16))
                .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        )
    }
}

// MARK: - Ahead / behind badge

struct SyncBadge: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 6) {
            if behind > 0 {
                Label("\(behind)", systemImage: "arrow.down")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color(hex: 0x6C9CF0))
            }
            if ahead > 0 {
                Label("\(ahead)", systemImage: "arrow.up")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.stateAdded)
            }
        }
        .font(.system(size: 10, weight: .semibold))
    }
}

// MARK: - Status letter badge

struct StatusBadge: View {
    let state: FileState

    var body: some View {
        Text(state.badge)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(state.accentColor)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(state.accentColor.opacity(0.16))
            )
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Relative date

enum RelativeDate {
    static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: .now)
    }

    static func full(_ date: Date) -> String {
        absolute.string(from: date)
    }
}

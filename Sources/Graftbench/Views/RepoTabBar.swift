import SwiftUI

/// A Fork-style strip of repository tabs, with a Home tab and a "+" to open more.
struct RepoTabBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            HomeTab(isSelected: app.showingHome) { app.showHome() }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(app.repositories) { repo in
                        RepoTab(
                            title: repo.name,
                            subtitle: repo.currentBranch?.name,
                            isSelected: !app.showingHome && app.selectedRepository?.id == repo.id,
                            onSelect: { app.selectRepository(repo) },
                            onClose: { app.closeRepository(repo) }
                        )
                    }
                }
            }

            Button {
                if let url = chooseRepositoryFolder() {
                    Task { await app.openRepository(at: url) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open another repository")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

private struct HomeTab: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Theme.accent : .secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Theme.selectionFill : (hovering ? Theme.hoverFill : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Home")
    }
}

private struct RepoTab: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                ZStack {
                    if hovering {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(.quaternary.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 14)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(maxWidth: 190)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.selectionFill : (hovering ? Theme.hoverFill : .clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isSelected ? Theme.selectionStroke : .clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

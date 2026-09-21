import SwiftUI

/// A collapsible tree of changed files.
struct FileTreeView: View {
    let diffs: [FileDiff]
    @Binding var selectedID: FileDiff.ID?

    private var nodes: [FileNode] { FileNode.build(from: diffs) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(nodes) { node in
                    FileTreeNodeRow(node: node, depth: 0, selectedID: $selectedID)
                }
            }
            .padding(6)
        }
        .surface()
    }
}

private struct FileTreeNodeRow: View {
    let node: FileNode
    let depth: Int
    @Binding var selectedID: FileDiff.ID?
    @State private var expanded = true
    @State private var hovering = false

    private var indent: CGFloat { CGFloat(depth) * 12 + 4 }

    var body: some View {
        if node.isDirectory {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent.opacity(0.85))
                    Text(node.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, indent)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(node.children) { child in
                    FileTreeNodeRow(node: child, depth: depth + 1, selectedID: $selectedID)
                }
            }
        } else {
            let selected = node.diff?.id == selectedID
            Button {
                if let diff = node.diff { selectedID = diff.id }
            } label: {
                HStack(spacing: 6) {
                    Spacer().frame(width: 12)
                    if let diff = node.diff {
                        StatusBadge(state: diff.primaryState)
                    }
                    Text(node.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let diff = node.diff, !diff.isBinary {
                        Text("+\(diff.addedLines)")
                            .foregroundStyle(Theme.stateAdded)
                        Text("−\(diff.removedLines)")
                            .foregroundStyle(Theme.stateDeleted)
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.leading, indent)
                .padding(.trailing, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Theme.selectionFill : (hovering ? Theme.hoverFill : .clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

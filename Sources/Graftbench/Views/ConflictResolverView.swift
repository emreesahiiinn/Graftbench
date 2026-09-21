import SwiftUI

struct ConflictBlock {
    let ours: String
    let theirs: String
    let base: String?
}

struct ConflictSegment: Identifiable {
    let id = UUID()
    enum Kind {
        case text(String)
        case conflict(ConflictBlock)
    }
    let kind: Kind
}

/// A practical conflict resolver: shows each conflict block with Ours / Theirs
/// and lets you pick per block, then writes the file and marks it resolved.
struct ConflictResolverView: View {
    @Bindable var repo: RepositoryModel
    let entry: StatusEntry
    @Environment(\.dismiss) private var dismiss

    @State private var segments: [ConflictSegment] = []
    @State private var resolutions: [UUID: String] = [:]
    @State private var loaded = false
    @State private var showUnresolvedAlert = false

    private var fileURL: URL { repo.root.appendingPathComponent(entry.path) }

    private var conflictCount: Int {
        segments.filter { if case .conflict = $0.kind { return true } else { return false } }.count
    }
    private var resolvedCount: Int { resolutions.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.stateConflict)
                Text("Resolve · \(entry.fileName)")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(resolvedCount)/\(conflictCount) resolved")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save & Mark Resolved") { save() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.bar)
            Divider()

            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(segments) { segment in
                            segmentView(segment)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .task { load() }
        .alert("Some conflicts are still unresolved", isPresented: $showUnresolvedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Resolve every conflict block before saving.")
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: ConflictSegment) -> some View {
        switch segment.kind {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(Theme.mono)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .conflict(let block):
            conflictCard(segment.id, block)
        }
    }

    private func conflictCard(_ id: UUID, _ block: ConflictBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let resolved = resolutions[id] {
                HStack {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.stateAdded)
                    Spacer()
                    Button("Change") { resolutions[id] = nil }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                Text(resolved.isEmpty ? " " : resolved)
                    .font(Theme.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.stateAdded.opacity(0.10)))
            } else {
                sideBox("Ours (current)", block.ours, Theme.stateAdded)
                sideBox("Theirs (incoming)", block.theirs, Color(hex: 0x6C9CF0))
                HStack(spacing: 8) {
                    Button("Take Ours") { resolutions[id] = block.ours }
                    Button("Take Theirs") { resolutions[id] = block.theirs }
                    Button("Take Both") { resolutions[id] = block.ours + "\n" + block.theirs }
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Theme.stateConflict.opacity(0.3), lineWidth: 1))
    }

    private func sideBox(_ title: String, _ content: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(content.isEmpty ? " " : content)
                .font(Theme.mono)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.10)))
        }
    }

    private func load() {
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        segments = Self.parse(content)
        loaded = true
    }

    private func save() {
        // Every conflict must be resolved.
        for segment in segments {
            if case .conflict = segment.kind, resolutions[segment.id] == nil {
                showUnresolvedAlert = true
                return
            }
        }
        var output = ""
        for segment in segments {
            switch segment.kind {
            case .text(let text): output += text
            case .conflict: output += resolutions[segment.id] ?? ""
            }
            output += "\n"
        }
        try? output.write(to: fileURL, atomically: true, encoding: .utf8)
        dismiss()
        Task { await repo.markResolved(entry) }
    }

    static func parse(_ content: String) -> [ConflictSegment] {
        var segments: [ConflictSegment] = []
        var buffer: [String] = []
        let lines = content.components(separatedBy: "\n")
        var idx = 0

        func flushText() {
            if !buffer.isEmpty {
                segments.append(ConflictSegment(kind: .text(buffer.joined(separator: "\n"))))
                buffer.removeAll()
            }
        }

        while idx < lines.count {
            let line = lines[idx]
            if line.hasPrefix("<<<<<<<") {
                flushText()
                var ours: [String] = [], theirs: [String] = [], base: [String] = []
                var section = 0
                idx += 1
                while idx < lines.count && !lines[idx].hasPrefix(">>>>>>>") {
                    let l = lines[idx]
                    if l.hasPrefix("|||||||") { section = 1 }
                    else if l.hasPrefix("=======") { section = 2 }
                    else {
                        switch section {
                        case 0: ours.append(l)
                        case 1: base.append(l)
                        default: theirs.append(l)
                        }
                    }
                    idx += 1
                }
                idx += 1
                segments.append(ConflictSegment(kind: .conflict(
                    ConflictBlock(ours: ours.joined(separator: "\n"),
                                  theirs: theirs.joined(separator: "\n"),
                                  base: base.isEmpty ? nil : base.joined(separator: "\n")))))
            } else {
                buffer.append(line)
                idx += 1
            }
        }
        flushText()
        return segments
    }
}

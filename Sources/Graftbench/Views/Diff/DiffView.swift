import SwiftUI
import AppKit

/// Per-hunk staging actions (present only in the Local Changes context).
struct HunkActions {
    var stage: ((DiffHunk) -> Void)?
    var unstage: ((DiffHunk) -> Void)?
    var discard: ((DiffHunk) -> Void)?
}

/// Renders a single file's diff, with persistent view controls (wrap, whitespace,
/// invisibles, tab width, unified/split).
struct DiffView: View {
    let diff: FileDiff
    var hunkActions: HunkActions? = nil
    var selectedLines: Set<UUID> = []
    var onToggleLine: ((DiffLine) -> Void)? = nil
    /// Called when the whitespace-ignore setting changes (needs a fresh git diff).
    var onReload: (() -> Void)? = nil

    private let prefs = Preferences.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon).foregroundStyle(iconColor)
            Text(diff.displayPath)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            if diff.isRenamed, let old = diff.oldPath {
                Text("← \(old)").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !diff.isBinary {
                Text("+\(diff.addedLines)").foregroundStyle(Theme.stateAdded)
                Text("−\(diff.removedLines)").foregroundStyle(Theme.stateDeleted).padding(.trailing, 4)
                controls
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            toggle("Word Wrap", "arrow.turn.down.left", prefs.diffWordWrap) {
                prefs.setDiffWordWrap(!prefs.diffWordWrap)
            }
            toggle("Show Invisibles", "paragraphsign", prefs.diffShowInvisibles) {
                prefs.setDiffShowInvisibles(!prefs.diffShowInvisibles)
            }
            toggle("Ignore Whitespace", "equal", prefs.ignoreWhitespaceInDiff) {
                prefs.setIgnoreWhitespaceInDiff(!prefs.ignoreWhitespaceInDiff)
                onReload?()
            }
            toggle("Show Whole File", "doc.plaintext", prefs.diffFullFile) {
                prefs.setDiffFullFile(!prefs.diffFullFile)
                onReload?()
            }
            toggle("Hide Hunk Headers", "rectangle.compress.vertical", prefs.diffHideHunkHeaders) {
                prefs.setDiffHideHunkHeaders(!prefs.diffHideHunkHeaders)
            }
            Menu {
                Picker("Tab Width", selection: Binding(
                    get: { prefs.diffTabWidth }, set: { prefs.setDiffTabWidth($0) })) {
                    Text("2").tag(2); Text("4").tag(4); Text("8").tag(8)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.right.to.line")
            }
            .menuStyle(.borderlessButton).fixedSize().help("Tab width")

            Picker("", selection: Binding(get: { prefs.diffMode }, set: { prefs.setDiffMode($0) })) {
                ForEach(DiffDisplayMode.allCases, id: \.self) { Image(systemName: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 74)
        }
    }

    private func toggle(_ title: String, _ icon: String, _ isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(isOn ? Theme.accent : .secondary)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(isOn ? Theme.accent.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain).help(title)
    }

    @ViewBuilder
    private var content: some View {
        if diff.isBinary {
            EmptyStateView(icon: "doc.badge.gearshape", title: "Binary file",
                           subtitle: "Graftbench can't show a text diff for this file.")
        } else if diff.hunks.isEmpty {
            EmptyStateView(icon: "equal.circle", title: "No changes to display")
        } else if prefs.diffMode == .unified {
            UnifiedDiffView(hunks: diff.hunks, actions: hunkActions,
                            selectedLines: selectedLines, onToggleLine: onToggleLine,
                            language: CodeLanguage.detect(path: diff.displayPath),
                            style: style)
        } else {
            SplitDiffView(hunks: diff.hunks, style: style)
        }
    }

    private var style: DiffRenderStyle {
        DiffRenderStyle(wrap: prefs.diffWordWrap, invisibles: prefs.diffShowInvisibles,
                        tabWidth: prefs.diffTabWidth, hideHunkHeaders: prefs.diffHideHunkHeaders)
    }

    private var fileIcon: String {
        if diff.isNew { return "plus.square.fill" }
        if diff.isDeleted { return "minus.square.fill" }
        if diff.isRenamed { return "arrow.right.square.fill" }
        return "doc.text.fill"
    }
    private var iconColor: Color {
        if diff.isNew { return Theme.stateAdded }
        if diff.isDeleted { return Theme.stateDeleted }
        if diff.isRenamed { return Theme.stateRenamed }
        return .secondary
    }
}

struct DiffRenderStyle {
    var wrap: Bool
    var invisibles: Bool
    var tabWidth: Int
    var hideHunkHeaders: Bool = false

    func displayText(_ text: String) -> String {
        if text.isEmpty { return " " }
        if invisibles {
            var t = text.replacingOccurrences(of: " ", with: "\u{00B7}")
            t = t.replacingOccurrences(of: "\t", with: "\u{2192}" + String(repeating: " ", count: max(0, tabWidth - 1)))
            return t
        }
        return text.replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabWidth))
    }
}

// MARK: - Unified

/// Wrap mode fills the viewport width; non-wrap mode pins an explicit,
/// content-derived width so horizontal scrolling stays aligned and stable.
private struct StackWidth: ViewModifier {
    let wrap: Bool
    let width: CGFloat
    func body(content: Content) -> some View {
        if wrap {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content.frame(width: width, alignment: .leading)
        }
    }
}

private struct UnifiedDiffView: View {
    let hunks: [DiffHunk]
    var actions: HunkActions?
    var selectedLines: Set<UUID> = []
    var onToggleLine: ((DiffLine) -> Void)? = nil
    var language: CodeLanguage = .plain
    var style: DiffRenderStyle

    var body: some View {
        ScrollView(style.wrap ? [.vertical] : [.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    if !style.hideHunkHeaders || actions != nil {
                        HunkHeaderRow(hunk: hunk, actions: actions, showHeaderText: !style.hideHunkHeaders)
                    }
                    ForEach(hunk.lines) { line in
                        let selectable = onToggleLine != nil && (line.kind == .addition || line.kind == .deletion)
                        UnifiedLineRow(
                            line: line, language: language, style: style,
                            selectable: selectable, selectableColumn: selectableColumn,
                            selected: selectedLines.contains(line.id),
                            onToggle: selectable ? { onToggleLine?(line) } : nil
                        )
                    }
                }
            }
            // Non-wrap rows scroll horizontally. Give the stack an explicit,
            // content-derived width so every row shares it: without it the
            // LazyVStack guesses its width from whichever rows happen to be
            // realized (short rows vs one very long line) and the whole block
            // jitters/shifts sideways until a relayout — which is why toggling
            // wrap "fixed" it. The text is monospaced, so the width is exact.
            .modifier(StackWidth(wrap: style.wrap, width: contentWidth))
            .padding(.bottom, 8)
        }
    }

    /// Reserve the selection-checkbox column for every row (even context lines)
    /// whenever this diff supports line staging, so columns line up.
    private var selectableColumn: Bool { onToggleLine != nil }

    /// Width of one monospaced character in the diff body font, measured once.
    private static let charWidth: CGFloat =
        ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width

    /// Deterministic width of the widest possible row: fixed leading columns
    /// (optional checkbox + two gutters + marker) plus the longest expanded
    /// line, with a small margin so the longest line never clips.
    private var contentWidth: CGFloat {
        let cols = hunks.reduce(0) { m, hunk in
            max(m, hunk.lines.reduce(0) { mm, line in max(mm, style.displayText(line.text).count) })
        }
        let leading: CGFloat = (selectableColumn ? 16 : 0) + 50 + 50 + 16
        return leading + CGFloat(cols) * Self.charWidth + 24
    }
}

private struct HunkHeaderRow: View {
    let hunk: DiffHunk
    var actions: HunkActions?
    var showHeaderText: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            if showHeaderText {
                Text(hunk.header).font(Theme.monoSmall).foregroundStyle(Theme.accentSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let actions {
                if let stage = actions.stage { button("Stage Hunk", "plus.circle", Theme.stateAdded) { stage(hunk) } }
                if let unstage = actions.unstage { button("Unstage Hunk", "minus.circle", Theme.stateModified) { unstage(hunk) } }
                if let discard = actions.discard { button("Discard", "trash", Theme.stateDeleted) { discard(hunk) } }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08))
    }

    private func button(_ title: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 10, weight: .medium))
                .labelStyle(.titleAndIcon).foregroundStyle(color)
        }
        .buttonStyle(.plain).help(title)
    }
}

private struct UnifiedLineRow: View {
    let line: DiffLine
    var language: CodeLanguage = .plain
    var style: DiffRenderStyle
    var selectable: Bool = false
    /// Whether the diff reserves a selection column at all (keeps context and
    /// changed lines column-aligned even though only changed lines are tappable).
    var selectableColumn: Bool = false
    var selected: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            if selectableColumn {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.4))
                    .opacity(selectable ? 1 : 0)
                    .frame(width: 16)
            }
            gutter(line.oldLineNumber)
            gutter(line.newLineNumber)
            Text(marker).frame(width: 16).foregroundStyle(markerColor)
            contentText.textSelection(.enabled)
                .fixedSize(horizontal: !style.wrap, vertical: false)
            if !style.wrap { Spacer(minLength: 0) }
        }
        .font(Theme.mono)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.accent.opacity(0.12) : background)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Theme.accent).frame(width: 2) } }
        .contentShape(Rectangle())
        .onTapGesture { onToggle?() }
    }

    private var contentText: Text {
        let dt = style.displayText(line.text)
        if style.invisibles {
            var attr = AttributedString(dt)
            attr.foregroundColor = textColor.opacity(0.8)
            return Text(attr)
        }
        var attr = SyntaxHighlighter.highlight(dt, language: language)
        if language == .plain { attr.foregroundColor = textColor }
        if let range = line.emphasis, !line.text.contains("\t") {
            let count = attr.characters.count
            let lo = min(max(range.lowerBound, 0), count)
            let hi = min(max(range.upperBound, lo), count)
            if lo < hi {
                let start = attr.characters.index(attr.characters.startIndex, offsetBy: lo)
                let end = attr.characters.index(start, offsetBy: hi - lo)
                attr[start..<end].font = .system(size: 12, weight: .bold, design: .monospaced)
            }
        }
        return Text(attr)
    }

    private func gutter(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(Theme.monoSmall).foregroundStyle(Theme.diffGutter)
            .frame(width: 44, alignment: .trailing).padding(.trailing, 6)
    }
    private var marker: String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "−"
        case .noNewline: return "\\"
        case .context: return " "
        }
    }
    private var markerColor: Color {
        switch line.kind {
        case .addition: return Theme.stateAdded
        case .deletion: return Theme.stateDeleted
        default: return .secondary
        }
    }
    private var textColor: Color {
        switch line.kind {
        case .addition: return Theme.diffAddText
        case .deletion: return Theme.diffDelText
        case .noNewline: return .secondary
        case .context: return .primary.opacity(0.9)
        }
    }
    private var background: Color {
        switch line.kind {
        case .addition: return Theme.diffAddBackground
        case .deletion: return Theme.diffDelBackground
        default: return .clear
        }
    }
}

// MARK: - Split (side-by-side)

private struct SplitRow: Identifiable {
    let id = UUID()
    let left: DiffLine?
    let right: DiffLine?
}

private struct SplitDiffView: View {
    let hunks: [DiffHunk]
    var style: DiffRenderStyle

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { hunk in
                    if !style.hideHunkHeaders {
                        Text(hunk.header)
                            .font(Theme.monoSmall).foregroundStyle(Theme.accentSoft)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.accent.opacity(0.08))
                    }
                    ForEach(rows(for: hunk)) { row in
                        HStack(spacing: 0) {
                            SplitCell(line: row.left, side: .left, style: style)
                            Divider()
                            SplitCell(line: row.right, side: .right, style: style)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func rows(for hunk: DiffHunk) -> [SplitRow] {
        var rows: [SplitRow] = []
        var dels: [DiffLine] = [], adds: [DiffLine] = []
        func flush() {
            let n = max(dels.count, adds.count)
            for i in 0..<n {
                rows.append(SplitRow(left: i < dels.count ? dels[i] : nil,
                                     right: i < adds.count ? adds[i] : nil))
            }
            dels.removeAll(keepingCapacity: true); adds.removeAll(keepingCapacity: true)
        }
        for line in hunk.lines {
            switch line.kind {
            case .context: flush(); rows.append(SplitRow(left: line, right: line))
            case .deletion: dels.append(line)
            case .addition: adds.append(line)
            case .noNewline: continue
            }
        }
        flush()
        return rows
    }
}

private enum SplitSide { case left, right }

private struct SplitCell: View {
    let line: DiffLine?
    let side: SplitSide
    var style: DiffRenderStyle

    var body: some View {
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .font(Theme.monoSmall).foregroundStyle(Theme.diffGutter)
                .frame(width: 40, alignment: .trailing).padding(.trailing, 6)
            Text(line.map { style.displayText($0.text) } ?? " ")
                .font(Theme.mono).foregroundStyle(textColor)
                .lineLimit(1).truncationMode(.tail).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var number: Int? {
        guard let line else { return nil }
        return side == .left ? line.oldLineNumber : line.newLineNumber
    }
    private var textColor: Color {
        guard let line else { return .clear }
        switch line.kind {
        case .addition: return Theme.diffAddText
        case .deletion: return Theme.diffDelText
        default: return .primary.opacity(0.9)
        }
    }
    private var background: Color {
        guard let line else { return Color.secondary.opacity(0.05) }
        switch line.kind {
        case .addition: return side == .right ? Theme.diffAddBackground : .clear
        case .deletion: return side == .left ? Theme.diffDelBackground : .clear
        default: return .clear
        }
    }
}

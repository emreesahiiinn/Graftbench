import SwiftUI
import AppKit

/// The user-selectable appearance for the whole app.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Selectable accent color themes.
enum AccentTheme: String, CaseIterable, Identifiable {
    case blue, teal, green, purple, pink, orange, graphite
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .teal: return "Sea Green"
        case .green: return "Green"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .graphite: return "Graphite"
        }
    }

    var hex: UInt32 {
        switch self {
        case .blue: return 0x3E7BF5
        case .teal: return 0x14B8A6
        case .green: return 0x22C55E
        case .purple: return 0x8B5CF6
        case .pink: return 0xEC4899
        case .orange: return 0xF59E0B
        case .graphite: return 0x6B7280
        }
    }
    var softHex: UInt32 {
        switch self {
        case .blue: return 0x6E9BFB
        case .teal: return 0x5EEAD4
        case .green: return 0x86EFAC
        case .purple: return 0xC4B5FD
        case .pink: return 0xF9A8D4
        case .orange: return 0xFCD34D
        case .graphite: return 0x9CA3AF
        }
    }
    var gradient: (UInt32, UInt32, UInt32) {
        switch self {
        case .blue: return (0x22C1F1, 0x3478F6, 0x6D39F5)
        case .teal: return (0x2DD4BF, 0x14B8A6, 0x0E7490)
        case .green: return (0x4ADE80, 0x22C55E, 0x15803D)
        case .purple: return (0xA78BFA, 0x8B5CF6, 0x6D28D9)
        case .pink: return (0xF472B6, 0xEC4899, 0xBE185D)
        case .orange: return (0xFBBF24, 0xF59E0B, 0xB45309)
        case .graphite: return (0x9CA3AF, 0x6B7280, 0x374151)
        }
    }

    var color: Color { Color(hex: hex) }
}

/// Central design tokens for Graftbench.
enum Theme {
    // MARK: Brand (accent is user-selectable at runtime)
    nonisolated(unsafe) static var accentHex: UInt32 = 0x3E7BF5
    nonisolated(unsafe) static var accentSoftHex: UInt32 = 0x6E9BFB
    nonisolated(unsafe) static var gradientHexes: (UInt32, UInt32, UInt32) = (0x22C1F1, 0x3478F6, 0x6D39F5)

    static var accent: Color { Color(hex: accentHex) }
    static var accentSoft: Color { Color(hex: accentSoftHex) }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: gradientHexes.0), Color(hex: gradientHexes.1), Color(hex: gradientHexes.2)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func applyAccent(_ theme: AccentTheme) {
        accentHex = theme.hex
        accentSoftHex = theme.softHex
        gradientHexes = theme.gradient
    }

    // MARK: Commit-graph lanes
    static let laneColors: [Color] = [
        Color(hex: 0x6C8CF5),   // blue
        Color(hex: 0xB06CF0),   // purple
        Color(hex: 0xF06CB0),   // pink
        Color(hex: 0xF08A6C),   // coral
        Color(hex: 0xE0B84C),   // amber
        Color(hex: 0x66C08A),   // green
        Color(hex: 0x4CC0C0),   // teal
        Color(hex: 0x8C9AA8)    // slate
    ]

    static func laneColor(_ index: Int) -> Color {
        let count = laneColors.count
        return laneColors[((index % count) + count) % count]
    }

    // MARK: File-state colors
    static let stateAdded = Color(hex: 0x53C08A)
    static let stateModified = Color(hex: 0xE0A94C)
    static let stateDeleted = Color(hex: 0xE86C6C)
    static let stateRenamed = Color(hex: 0x6C9CF0)
    static let stateUntracked = Color(hex: 0x8C9AA8)
    static let stateConflict = Color(hex: 0xF0704C)

    // MARK: Diff colors (tuned for both light and dark)
    static let diffAddText = Color(light: 0x1C7C43, dark: 0x8FE3B4)
    static let diffDelText = Color(light: 0xB23636, dark: 0xF2A0A0)
    static var diffAddBackground: Color { Color(light: 0x53C08A, dark: 0x53C08A).opacity(0.15) }
    static var diffDelBackground: Color { Color(light: 0xE86C6C, dark: 0xE86C6C).opacity(0.15) }
    static var diffGutter: Color { Color.secondary.opacity(0.55) }

    // MARK: Typography
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    // MARK: Syntax highlighting (adaptive)
    static let synKeyword = Color(light: 0x8E24AA, dark: 0xC792EA)
    static let synString = Color(light: 0xB4530E, dark: 0xE0975C)
    static let synNumber = Color(light: 0x1E6FD0, dark: 0x82AAFF)
    static let synComment = Color(light: 0x8A93A5, dark: 0x7E8796)

    // MARK: Selection & hover
    static var selectionFill: Color { accent.opacity(0.15) }
    static var selectionStroke: Color { accent.opacity(0.30) }
    static var hoverFill: Color { Color.primary.opacity(0.055) }

    // MARK: Metrics
    static let corner: CGFloat = 10
    static let laneWidth: CGFloat = 15
    static let rowHeight: CGFloat = 30
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// A dynamic color that resolves differently for light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - File-state helpers

extension FileState {
    var accentColor: Color {
        switch self {
        case .added: return Theme.stateAdded
        case .modified, .typeChanged: return Theme.stateModified
        case .deleted: return Theme.stateDeleted
        case .renamed, .copied: return Theme.stateRenamed
        case .unmerged: return Theme.stateConflict
        case .untracked: return Theme.stateUntracked
        case .ignored: return Color.secondary
        case .unmodified: return Color.secondary
        }
    }

    /// A one-letter badge like Fork's status column.
    var badge: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .typeChanged: return "T"
        case .unmerged: return "U"
        case .untracked: return "?"
        case .ignored: return "!"
        case .unmodified: return " "
        }
    }

    var systemImage: String {
        switch self {
        case .added: return "plus.circle.fill"
        case .modified, .typeChanged: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed, .copied: return "arrow.right.circle.fill"
        case .unmerged: return "exclamationmark.triangle.fill"
        case .untracked: return "questionmark.circle.fill"
        case .ignored: return "eye.slash.circle.fill"
        case .unmodified: return "circle"
        }
    }
}

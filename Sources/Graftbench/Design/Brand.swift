import SwiftUI
import AppKit

/// Loads the bundled brand artwork (rasterized from the source SVGs).
enum Brand {
    static let mark: NSImage? = load("BrandMark")
    static let wordmark: NSImage? = load("BrandWordmark")

    /// The app icon, resolved from the bundle for use as the Dock icon.
    static var appIcon: NSImage? {
        NSImage(named: "AppIcon") ?? mark
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
}

/// The G mark, with a graceful gradient fallback if the asset is missing.
struct BrandMark: View {
    var size: CGFloat = 30
    var cornerRadius: CGFloat = 8

    var body: some View {
        if let mark = Brand.mark {
            Image(nsImage: mark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.accentGradient)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: size * 0.46, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}

/// The full wordmark, with a text fallback.
struct BrandWordmark: View {
    var height: CGFloat = 72

    var body: some View {
        if let wordmark = Brand.wordmark {
            Image(nsImage: wordmark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
        } else {
            HStack(spacing: 12) {
                BrandMark(size: height * 0.8, cornerRadius: 14)
                Text("Graftbench")
                    .font(.system(size: height * 0.42, weight: .bold, design: .rounded))
            }
        }
    }
}

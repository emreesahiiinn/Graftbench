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
        guard let url = resourceURL(name, ext: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }

    /// Locate a bundled resource without going through the generated
    /// `Bundle.module` accessor. That accessor calls `fatalError` when it can't
    /// find the bundle, and *where* it looks depends on the build toolchain:
    /// with the embedded Info.plist, some toolchains resolve
    /// `Bundle.main.resourceURL` to the `.app` root instead of
    /// `Contents/Resources`, so the SwiftPM resource bundle is never found and
    /// the app traps on launch. Search the likely locations ourselves and
    /// return nil on failure so the views fall back to their placeholder art.
    private static func resourceURL(_ name: String, ext: String) -> URL? {
        let bundleName = "Graftbench_Graftbench.bundle"
        let bases: [URL] = [
            // Standard app layout — works regardless of how the toolchain
            // resolves resourceURL, since bundleURL is reliably the `.app`.
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ].compactMap { $0 }

        for base in bases {
            if let bundle = Bundle(url: base.appendingPathComponent(bundleName)),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        // Last resort: the image sitting directly in the app's Resources.
        return Bundle.main.url(forResource: name, withExtension: ext)
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

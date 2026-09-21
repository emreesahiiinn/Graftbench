import SwiftUI
import AppKit

/// A behind-window vibrancy background (frosted-glass effect).
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Makes the hosting window opaque or translucent.
struct WindowConfigurator: NSViewRepresentable {
    let translucent: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = !translucent
        window.backgroundColor = translucent ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = translucent
    }
}

/// A panel background that becomes transparent in translucent mode so the
/// behind-window vibrancy (desktop blur) shows through.
struct SurfaceBackground: View {
    private let prefs = Preferences.shared
    var body: some View {
        if prefs.translucentWindow {
            Color.clear
        } else {
            Rectangle().fill(.background)
        }
    }
}

extension View {
    /// Use instead of `.background(.background)` so translucency can show through.
    func surface() -> some View {
        background(SurfaceBackground())
    }
}

import SwiftUI
import AppKit

struct ImageDiffView: View {
    let client: GitClient
    var oldRef: String? = nil
    var oldPath: String? = nil
    var newRef: String? = nil
    var newPath: String? = nil
    var newFileURL: URL? = nil

    @State private var oldImage: NSImage?
    @State private var newImage: NSImage?
    @State private var loading = true

    static func isImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico"]
            .contains((path as NSString).pathExtension.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    pane("Before", oldImage)
                    Divider()
                    pane("After", newImage)
                }
            }
        }
        .surface()
        .task { await load() }
    }

    private func pane(_ title: String, _ image: NSImage?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("\(Int(image.size.width))×\(Int(image.size.height))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                Spacer()
                Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("—").foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        if let oldRef, let oldPath, let data = try? await client.blob(ref: oldRef, path: oldPath) {
            oldImage = NSImage(data: data)
        }
        if let newRef, let newPath, let data = try? await client.blob(ref: newRef, path: newPath) {
            newImage = NSImage(data: data)
        } else if let newFileURL, let data = try? Data(contentsOf: newFileURL) {
            newImage = NSImage(data: data)
        }
        loading = false
    }
}

import Foundation

/// A node in a tree of changed files (for the File Tree view).
struct FileNode: Identifiable, Hashable {
    let id: String            // full path
    let name: String
    let isDirectory: Bool
    var children: [FileNode]
    let diff: FileDiff?       // set for leaf files

    /// OutlineGroup children accessor (nil for leaves so they show no triangle).
    var childrenOrNil: [FileNode]? {
        isDirectory ? children : nil
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func build(from diffs: [FileDiff]) -> [FileNode] {
        let root = TreeBuilder(name: "", path: "")
        for diff in diffs {
            let components = diff.displayPath.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var node = root
            var accumulated = ""
            for (index, component) in components.enumerated() {
                accumulated = accumulated.isEmpty ? component : accumulated + "/" + component
                if let existing = node.children[component] {
                    node = existing
                } else {
                    let child = TreeBuilder(name: component, path: accumulated)
                    node.children[component] = child
                    node = child
                }
                if index == components.count - 1 { node.diff = diff }
            }
        }
        return root.convertedChildren()
    }
}

/// Mutable helper used while assembling the tree.
private final class TreeBuilder {
    let name: String
    let path: String
    var children: [String: TreeBuilder] = [:]
    var diff: FileDiff?

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    func convertedChildren() -> [FileNode] {
        let directories = children.values
            .filter { !$0.children.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let files = children.values
            .filter { $0.children.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var result: [FileNode] = []
        for dir in directories {
            result.append(FileNode(id: dir.path, name: dir.name, isDirectory: true,
                                   children: dir.convertedChildren(), diff: nil))
        }
        for file in files {
            result.append(FileNode(id: file.path, name: file.name, isDirectory: false,
                                   children: [], diff: file.diff))
        }
        return result
    }
}

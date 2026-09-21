import Foundation

/// One rendered row of the commit graph, parallel to a `Commit` at the same index.
struct GraphRow: Identifiable, Sendable {
    enum EdgeKind: Sendable { case passThrough, mergeIntoNode, forkFromNode }

    struct Edge: Identifiable, Sendable {
        let id = UUID()
        let fromColumn: Int
        let toColumn: Int
        let colorIndex: Int
        let kind: EdgeKind
    }

    let id: String          // commit SHA
    let column: Int         // the node's lane
    let colorIndex: Int
    let width: Int          // number of lanes occupied at this row
    let edges: [Edge]
}

struct CommitGraph: Sendable {
    let rows: [GraphRow]
    let laneCount: Int

    static let empty = CommitGraph(rows: [], laneCount: 1)
}

/// Assigns lanes to commits and produces drawable edges — the classic
/// "railway" git graph layout.
enum GraphLayout {
    static func compute(commits: [Commit]) -> CommitGraph {
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        // lanes[k] = SHA expected to appear in column k (a child is waiting for it).
        var lanes: [String?] = []
        var maxLanes = 1

        func firstFreeColumn(in array: [String?]) -> Int {
            if let idx = array.firstIndex(where: { $0 == nil }) { return idx }
            return array.count
        }

        for commit in commits {
            let incoming = lanes
            let childColumns = incoming.indices.filter { incoming[$0] == commit.id }

            let nodeColumn: Int
            if let minChild = childColumns.min() {
                nodeColumn = minChild
            } else {
                nodeColumn = firstFreeColumn(in: incoming)
            }

            // Build the outgoing lane state.
            var outgoing = incoming
            for c in childColumns { outgoing[c] = nil }
            while outgoing.count <= nodeColumn { outgoing.append(nil) }
            outgoing[nodeColumn] = nil   // node's own lane resolved for now

            var parentColumns: [Int] = []
            for (parentIndex, parent) in commit.parents.enumerated() {
                if let existing = outgoing.firstIndex(where: { $0 == parent }) {
                    parentColumns.append(existing)
                } else if parentIndex == 0 {
                    outgoing[nodeColumn] = parent
                    parentColumns.append(nodeColumn)
                } else {
                    let free = firstFreeColumn(in: outgoing)
                    if free < outgoing.count { outgoing[free] = parent } else { outgoing.append(parent) }
                    parentColumns.append(free)
                }
            }

            // Assemble edges.
            var edges: [GraphRow.Edge] = []

            for k in incoming.indices where incoming[k] != nil {
                if childColumns.contains(k) {
                    edges.append(.init(fromColumn: k, toColumn: nodeColumn,
                                       colorIndex: k, kind: .mergeIntoNode))
                } else if let dest = outgoing.firstIndex(where: { $0 == incoming[k] }) {
                    edges.append(.init(fromColumn: k, toColumn: dest,
                                       colorIndex: dest, kind: .passThrough))
                }
            }

            for pc in parentColumns {
                edges.append(.init(fromColumn: nodeColumn, toColumn: pc,
                                   colorIndex: pc, kind: .forkFromNode))
            }

            // Trim trailing empties to keep the width tight.
            while let last = outgoing.last, last == nil { outgoing.removeLast() }

            let rowWidth = max(incoming.count, outgoing.count, nodeColumn + 1)
            maxLanes = max(maxLanes, rowWidth)

            rows.append(GraphRow(id: commit.id, column: nodeColumn,
                                 colorIndex: nodeColumn, width: rowWidth, edges: edges))
            lanes = outgoing
        }

        return CommitGraph(rows: rows, laneCount: max(1, maxLanes))
    }
}

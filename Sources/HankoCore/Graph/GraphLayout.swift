import Foundation

/// One row of the commit graph. All lane numbers are column indices.
public struct GraphRow: Sendable, Equatable {
    public let commitID: String
    /// Column of the commit's own node.
    public let column: Int
    /// Lanes whose line arrives at the node from the top edge of the row.
    public let incoming: [Int]
    /// Lanes that simply pass straight through the row.
    public let through: [Int]
    /// Lanes the node's line leaves toward (one per parent).
    public let outgoing: [Int]
    public let laneCount: Int
}

public enum GraphLayout {
    /// Assigns lanes to commits given in topological (child-before-parent) order.
    public static func build(_ commits: [Commit]) -> [GraphRow] {
        var lanes: [String?] = []
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            let incoming = lanes.indices.filter { lanes[$0] == commit.id }

            let column: Int
            if let first = incoming.first {
                column = first
            } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                column = free
            } else {
                lanes.append(nil)
                column = lanes.count - 1
            }

            let before = lanes
            let through = before.indices.filter { before[$0] != nil && before[$0] != commit.id }
            for lane in incoming { lanes[lane] = nil }

            var outgoing: [Int] = []
            for (index, parent) in commit.parents.enumerated() {
                if let existing = lanes.firstIndex(of: parent) {
                    outgoing.append(existing)
                } else if index == 0 {
                    lanes[column] = parent
                    outgoing.append(column)
                } else {
                    let slot: Int
                    if let free = lanes.firstIndex(where: { $0 == nil }) { slot = free } else { lanes.append(nil); slot = lanes.count - 1 }
                    lanes[slot] = parent
                    outgoing.append(slot)
                }
            }

            rows.append(GraphRow(
                commitID: commit.id,
                column: column,
                incoming: incoming,
                through: through,
                outgoing: outgoing,
                laneCount: max(before.count, lanes.count, column + 1)
            ))

            while let last = lanes.last, last == nil { lanes.removeLast() }
        }
        return rows
    }
}

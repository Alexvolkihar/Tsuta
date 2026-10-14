import Foundation

public struct ConflictBlock: Equatable, Sendable {
    public var ours: [String]
    public var base: [String]?
    public var theirs: [String]
    public var oursLabel: String
    public var theirsLabel: String
}

public enum ConflictSegment: Equatable, Sendable {
    case text([String])
    case conflict(ConflictBlock)
}

public enum ConflictChoice: String, CaseIterable, Sendable {
    case ours, theirs, both, bothReversed
}

public enum ConflictParser {
    public static func parse(_ text: String) -> [ConflictSegment] {
        let lines = text.components(separatedBy: "\n")
        var segments: [ConflictSegment] = []
        var plain: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("<<<<<<< ") || line == "<<<<<<<" else {
                plain.append(line); i += 1; continue
            }
            // Look ahead for a well-formed block; otherwise treat the line as plain text.
            var j = i + 1
            var ours: [String] = [], base: [String]? = nil, theirs: [String] = []
            var oursLabel = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            var theirsLabel = ""
            var stage = 0   // 0 ours, 1 base, 2 theirs
            var closed = false
            while j < lines.count {
                let l = lines[j]
                if stage == 0, l.hasPrefix("|||||||") { stage = 1; base = []; j += 1; continue }
                if stage <= 1, l == "=======" { stage = 2; j += 1; continue }
                if stage == 2, l.hasPrefix(">>>>>>>") {
                    theirsLabel = String(l.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    closed = true; break
                }
                switch stage {
                case 0: ours.append(l)
                case 1: base?.append(l)
                default: theirs.append(l)
                }
                j += 1
            }
            if closed {
                if !plain.isEmpty { segments.append(.text(plain)); plain = [] }
                segments.append(.conflict(ConflictBlock(ours: ours, base: base, theirs: theirs,
                                                        oursLabel: oursLabel, theirsLabel: theirsLabel)))
                i = j + 1
            } else {
                oursLabel = ""
                plain.append(line); i += 1
            }
        }
        if !plain.isEmpty { segments.append(.text(plain)) }
        return segments
    }

    public static func conflictCount(_ segments: [ConflictSegment]) -> Int {
        segments.reduce(0) { if case .conflict = $1 { return $0 + 1 } else { return $0 } }
    }

    public static func lines(for block: ConflictBlock, choice: ConflictChoice) -> [String] {
        switch choice {
        case .ours: block.ours
        case .theirs: block.theirs
        case .both: block.ours + block.theirs
        case .bothReversed: block.theirs + block.ours
        }
    }

    /// Rebuilds the file. `choices[n]` resolves the n-th conflict; nil keeps its markers.
    public static func render(_ segments: [ConflictSegment], choices: [ConflictChoice?]) -> String {
        var out: [String] = []
        var n = 0
        for segment in segments {
            switch segment {
            case .text(let lines):
                out += lines
            case .conflict(let block):
                let choice = n < choices.count ? choices[n] : nil
                n += 1
                if let choice {
                    out += lines(for: block, choice: choice)
                } else {
                    out.append("<<<<<<< \(block.oursLabel)")
                    out += block.ours
                    if let base = block.base { out.append("||||||| base"); out += base }
                    out.append("=======")
                    out += block.theirs
                    out.append(">>>>>>> \(block.theirsLabel)")
                }
            }
        }
        return out.joined(separator: "\n")
    }
}

import Foundation

/// Parses `git diff` unified-diff text into structured `FileDiff` values.
enum DiffParser {
    static func parse(_ text: String) -> [FileDiff] {
        var files: [FileDiff] = []

        // Current file accumulator.
        var fileOpen = false
        var oldPath: String?
        var newPath: String?
        var isBinary = false
        var isNew = false
        var isDeleted = false
        var isRenamed = false
        var hunks: [DiffHunk] = []

        // Current hunk accumulator.
        var hunkOpen = false
        var hunkHeader = ""
        var hOldStart = 0, hOldCount = 0, hNewStart = 0, hNewCount = 0
        var hunkLines: [DiffLine] = []
        var oldNo = 0, newNo = 0

        func flushHunk() {
            guard hunkOpen else { return }
            DiffParser.computeWordEmphasis(&hunkLines)
            hunks.append(DiffHunk(header: hunkHeader,
                                  oldStart: hOldStart, oldCount: hOldCount,
                                  newStart: hNewStart, newCount: hNewCount,
                                  lines: hunkLines))
            hunkOpen = false
            hunkLines = []
        }

        func flushFile() {
            flushHunk()
            guard fileOpen else { return }
            let id = newPath ?? oldPath ?? "file-\(files.count)"
            files.append(FileDiff(id: id, oldPath: oldPath, newPath: newPath,
                                  isBinary: isBinary, isNew: isNew, isDeleted: isDeleted,
                                  isRenamed: isRenamed, hunks: hunks))
            fileOpen = false
            oldPath = nil; newPath = nil
            isBinary = false; isNew = false; isDeleted = false; isRenamed = false
            hunks = []
        }

        func strip(_ pathToken: Substring) -> String? {
            let token = String(pathToken)
            if token == "/dev/null" { return nil }
            if token.hasPrefix("a/") || token.hasPrefix("b/") { return String(token.dropFirst(2)) }
            return token
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("diff --git ") {
                flushFile()
                fileOpen = true
                continue
            }

            if line.hasPrefix("@@") {
                flushHunk()
                hunkOpen = true
                hunkHeader = line
                (hOldStart, hOldCount, hNewStart, hNewCount) = parseHunkHeader(line)
                oldNo = hOldStart
                newNo = hNewStart
                continue
            }

            if hunkOpen {
                guard let marker = line.first else {
                    // Blank line inside a hunk = empty context line.
                    hunkLines.append(DiffLine(kind: .context, text: "", oldLineNumber: oldNo, newLineNumber: newNo))
                    oldNo += 1; newNo += 1
                    continue
                }
                let content = String(line.dropFirst())
                switch marker {
                case " ":
                    hunkLines.append(DiffLine(kind: .context, text: content, oldLineNumber: oldNo, newLineNumber: newNo))
                    oldNo += 1; newNo += 1
                case "+":
                    hunkLines.append(DiffLine(kind: .addition, text: content, oldLineNumber: nil, newLineNumber: newNo))
                    newNo += 1
                case "-":
                    hunkLines.append(DiffLine(kind: .deletion, text: content, oldLineNumber: oldNo, newLineNumber: nil))
                    oldNo += 1
                case "\\":
                    hunkLines.append(DiffLine(kind: .noNewline, text: content, oldLineNumber: nil, newLineNumber: nil))
                default:
                    // Shouldn't happen inside a well-formed hunk; treat as context.
                    hunkLines.append(DiffLine(kind: .context, text: line, oldLineNumber: oldNo, newLineNumber: newNo))
                    oldNo += 1; newNo += 1
                }
                continue
            }

            // Header region (between `diff --git` and the first `@@`).
            if line.hasPrefix("new file mode") {
                isNew = true
            } else if line.hasPrefix("deleted file mode") {
                isDeleted = true
            } else if line.hasPrefix("rename from ") {
                isRenamed = true
                oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                isRenamed = true
                newPath = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("copy from ") {
                oldPath = String(line.dropFirst("copy from ".count))
            } else if line.hasPrefix("copy to ") {
                newPath = String(line.dropFirst("copy to ".count))
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                isBinary = true
            } else if line.hasPrefix("--- ") {
                oldPath = strip(rawLine.dropFirst(4))
            } else if line.hasPrefix("+++ ") {
                newPath = strip(rawLine.dropFirst(4))
            }
        }

        flushFile()
        return files
    }

    /// Parse `@@ -oldStart,oldCount +newStart,newCount @@` into its four numbers.
    private static func parseHunkHeader(_ header: String) -> (Int, Int, Int, Int) {
        let parts = header.split(separator: " ")
        var oldStart = 0, oldCount = 1, newStart = 0, newCount = 1
        for part in parts {
            if part.hasPrefix("-") {
                let nums = part.dropFirst().split(separator: ",")
                oldStart = Int(nums.first ?? "0") ?? 0
                oldCount = nums.count > 1 ? (Int(nums[1]) ?? 1) : 1
            } else if part.hasPrefix("+") {
                let nums = part.dropFirst().split(separator: ",")
                newStart = Int(nums.first ?? "0") ?? 0
                newCount = nums.count > 1 ? (Int(nums[1]) ?? 1) : 1
            }
        }
        return (oldStart, oldCount, newStart, newCount)
    }

    /// Pair consecutive deletion/addition lines and mark the changed character
    /// range on each, for intra-line (word) diff highlighting.
    static func computeWordEmphasis(_ lines: inout [DiffLine]) {
        var i = 0
        while i < lines.count {
            guard lines[i].kind == .deletion else { i += 1; continue }
            var deletions: [Int] = []
            while i < lines.count, lines[i].kind == .deletion { deletions.append(i); i += 1 }
            var additions: [Int] = []
            while i < lines.count, lines[i].kind == .addition { additions.append(i); i += 1 }
            for k in 0..<min(deletions.count, additions.count) {
                let (delRange, addRange) = wordRange(lines[deletions[k]].text, lines[additions[k]].text)
                lines[deletions[k]].emphasis = delRange
                lines[additions[k]].emphasis = addRange
            }
        }
    }

    /// The differing middle ranges (after common prefix/suffix) of two lines.
    static func wordRange(_ old: String, _ new: String) -> (Range<Int>?, Range<Int>?) {
        let o = Array(old), n = Array(new)
        if o.isEmpty && n.isEmpty { return (nil, nil) }
        var prefix = 0
        let maxPrefix = min(o.count, n.count)
        while prefix < maxPrefix, o[prefix] == n[prefix] { prefix += 1 }
        var suffix = 0
        let maxSuffix = min(o.count - prefix, n.count - prefix)
        while suffix < maxSuffix, o[o.count - 1 - suffix] == n[n.count - 1 - suffix] { suffix += 1 }
        let oRange = (o.count - suffix) > prefix ? prefix..<(o.count - suffix) : nil
        let nRange = (n.count - suffix) > prefix ? prefix..<(n.count - suffix) : nil
        return (oRange, nRange)
    }
}

import SwiftUI

enum CodeLanguage: String {
    case swift, cLike, jsLike, python, ruby, shell, go, rust, css, json, plain

    static func detect(path: String) -> CodeLanguage {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return .swift
        case "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue": return .jsLike
        case "py": return .python
        case "rb": return .ruby
        case "sh", "bash", "zsh": return .shell
        case "go": return .go
        case "rs": return .rust
        case "c", "h", "cpp", "cc", "hpp", "hh", "m", "mm", "cs", "java", "kt", "kts": return .cLike
        case "css", "scss", "less": return .css
        case "json": return .json
        default: return .plain
        }
    }

    var lineComments: [String] {
        switch self {
        case .python, .ruby, .shell: return ["#"]
        default: return ["//"]
        }
    }

    var keywords: Set<String> {
        switch self {
        case .swift:
            return ["func", "let", "var", "if", "else", "guard", "return", "for", "while", "switch", "case",
                    "struct", "class", "enum", "protocol", "extension", "import", "in", "self", "init",
                    "try", "await", "async", "throws", "throw", "do", "catch", "nil", "true", "false",
                    "public", "private", "internal", "static", "some", "where", "as", "is", "defer"]
        case .jsLike:
            return ["function", "const", "let", "var", "if", "else", "return", "for", "while", "switch",
                    "case", "class", "extends", "import", "export", "from", "new", "this", "await", "async",
                    "try", "catch", "throw", "typeof", "instanceof", "null", "undefined", "true", "false",
                    "interface", "type", "enum", "public", "private", "readonly", "default"]
        case .python:
            return ["def", "class", "if", "elif", "else", "return", "for", "while", "import", "from", "as",
                    "in", "is", "not", "and", "or", "try", "except", "finally", "with", "lambda", "None",
                    "True", "False", "self", "yield", "async", "await", "pass", "raise", "global"]
        case .cLike:
            return ["int", "float", "double", "char", "void", "bool", "if", "else", "return", "for", "while",
                    "switch", "case", "class", "struct", "public", "private", "protected", "static", "const",
                    "new", "delete", "this", "true", "false", "null", "nullptr", "namespace", "using",
                    "template", "typename", "virtual", "override", "import", "package"]
        case .go:
            return ["func", "package", "import", "var", "const", "type", "struct", "interface", "if", "else",
                    "for", "range", "return", "go", "defer", "chan", "map", "nil", "true", "false", "switch", "case"]
        case .ruby:
            return ["def", "class", "module", "if", "elsif", "else", "end", "return", "do", "while", "for",
                    "require", "yield", "nil", "true", "false", "self", "begin", "rescue", "ensure"]
        case .shell:
            return ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case", "esac", "function", "echo", "return", "export"]
        case .rust:
            return ["fn", "let", "mut", "if", "else", "match", "for", "while", "loop", "return", "struct",
                    "enum", "impl", "trait", "use", "pub", "mod", "self", "Self", "true", "false", "async", "await"]
        case .css:
            return []
        case .json, .plain:
            return []
        }
    }
}

/// A lightweight, dependency-free syntax highlighter for diff lines.
enum SyntaxHighlighter {
    private struct Regexes {
        let keyword: NSRegularExpression?
        let number: NSRegularExpression?
        let string: NSRegularExpression?
        let comment: NSRegularExpression?
    }

    nonisolated(unsafe) private static var cache: [String: Regexes] = [:]

    static func highlight(_ text: String, language: CodeLanguage) -> AttributedString {
        var attr = AttributedString(text)
        guard language != .plain, !text.isEmpty else { return attr }

        let regexes = regexes(for: language)
        // Apply in order so later categories override earlier ones inside overlaps.
        apply(regexes.keyword, Theme.synKeyword, to: &attr, text: text)
        apply(regexes.number, Theme.synNumber, to: &attr, text: text)
        apply(regexes.string, Theme.synString, to: &attr, text: text)
        apply(regexes.comment, Theme.synComment, to: &attr, text: text)
        return attr
    }

    private static func apply(_ regex: NSRegularExpression?, _ color: Color,
                              to attr: inout AttributedString, text: String) {
        guard let regex else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let count = attr.characters.count
        for match in regex.matches(in: text, range: range) {
            let loc = match.range.location, len = match.range.length
            guard loc != NSNotFound, len > 0, loc + len <= count else { continue }
            let start = attr.characters.index(attr.characters.startIndex, offsetBy: loc)
            let end = attr.characters.index(start, offsetBy: len)
            attr[start..<end].foregroundColor = color
        }
    }

    private static func regexes(for language: CodeLanguage) -> Regexes {
        if let cached = cache[language.rawValue] { return cached }

        let keyword: NSRegularExpression? = language.keywords.isEmpty ? nil : try? NSRegularExpression(
            pattern: "\\b(" + language.keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b")
        let number = try? NSRegularExpression(pattern: "\\b\\d[\\d_]*(?:\\.\\d+)?\\b")
        let string = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`")
        var commentPatterns = language.lineComments.map { NSRegularExpression.escapedPattern(for: $0) + ".*" }
        commentPatterns.append("/\\*.*?\\*/")
        let comment = try? NSRegularExpression(pattern: commentPatterns.joined(separator: "|"))

        let result = Regexes(keyword: keyword, number: number, string: string, comment: comment)
        cache[language.rawValue] = result
        return result
    }
}

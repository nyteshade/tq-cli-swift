import Foundation

// MARK: - Color Mode

/// Whether colorized output is enabled.
enum ColorMode {
    /// Colorize only when stdout is a terminal (and NO_COLOR is unset).
    case auto
    /// Always colorize, regardless of TTY.
    case always
    /// Never colorize.
    case never

    /// Resolve the mode to a concrete on/off decision for the current process.
    var isEnabled: Bool {
        switch self {
        case .always:
            return true
        case .never:
            return false
        case .auto:
            // Honor the NO_COLOR convention (https://no-color.org).
            if let noColor = ProcessInfo.processInfo.environment["NO_COLOR"], !noColor.isEmpty {
                return false
            }
            // Only colorize when stdout is an interactive terminal.
            return isatty(fileno(stdout)) != 0
        }
    }
}

// MARK: - ANSI Palette

/// SGR color codes used to highlight TOON and JSON output.
private enum ANSI {
    static let reset = "\u{001B}[0m"

    static let key = "\u{001B}[34m"      // blue   — object keys / table headers
    static let string = "\u{001B}[32m"   // green  — string values
    static let number = "\u{001B}[33m"   // yellow — int / double values
    static let bool = "\u{001B}[35m"     // magenta — true / false
    static let null = "\u{001B}[90m"     // bright black — null
    static let punct = "\u{001B}[2m"     // dim    — structural punctuation
}

// MARK: - Highlighter

/// Tokenizes already-serialized TOON or JSON text and wraps tokens in ANSI
/// color codes. Operating on the serialized string (rather than the node tree)
/// keeps highlighting orthogonal to encoding: the encoders decide layout, the
/// highlighter only paints.
enum Highlighter {
    /// Colorize a block of JSON text.
    static func json(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count + text.count / 2)

        let chars = Array(text)
        var i = 0
        let n = chars.count

        while i < n {
            let c = chars[i]
            switch c {
            case "\"":
                // Scan a full quoted string (with escapes).
                let start = i
                i += 1
                while i < n {
                    if chars[i] == "\\", i + 1 < n {
                        i += 2
                        continue
                    }
                    if chars[i] == "\"" {
                        i += 1
                        break
                    }
                    i += 1
                }
                let literal = String(chars[start..<i])
                // A string immediately followed by a colon is a key.
                var j = i
                while j < n, chars[j] == " " { j += 1 }
                let isKey = j < n && chars[j] == ":"
                out += (isKey ? ANSI.key : ANSI.string) + literal + ANSI.reset
                continue
            case "{", "}", "[", "]", ":", ",":
                out += ANSI.punct + String(c) + ANSI.reset
            case "t", "f", "n":
                // Match bare literals true / false / null at a value boundary.
                if let (token, color) = matchLiteral(chars, at: i) {
                    out += color + token + ANSI.reset
                    i += token.count
                    continue
                }
                out.append(c)
            case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                let (token, next) = scanNumber(chars, at: i, count: n)
                if !token.isEmpty {
                    out += ANSI.number + token + ANSI.reset
                    i = next
                    continue
                }
                out.append(c)
            default:
                out.append(c)
            }
            i += 1
        }
        return out
    }

    /// Colorize a block of TOON text, line by line.
    ///
    /// TOON is indentation-sensitive and uses `key: value`, table headers like
    /// `users[2]{id,name}:`, and comma-separated tabular rows. We highlight by
    /// structural position rather than re-parsing the grammar.
    static func toon(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { toonLine(String($0)) }
            .joined(separator: "\n")
    }

    // MARK: - TOON line highlighting

    private static func toonLine(_ line: String) -> String {
        // Preserve leading indentation verbatim.
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let indent = String(line.prefix(indentCount))
        let rest = String(line.dropFirst(indentCount))

        if rest.isEmpty {
            return line
        }

        // List item dash: "- value"
        if rest.hasPrefix("- ") {
            let value = String(rest.dropFirst(2))
            return indent + ANSI.punct + "- " + ANSI.reset + highlightToonValue(value)
        }
        if rest == "-" {
            return indent + ANSI.punct + "-" + ANSI.reset
        }

        // Find a top-level "key: rest" split — the first colon that isn't inside
        // a bracketed header (e.g. users[2]{id,name}:) or a quoted string.
        if let colon = topLevelColonIndex(rest) {
            let keyPart = String(rest[rest.startIndex..<colon])
            let afterColon = rest.index(after: colon)
            let valuePart = afterColon < rest.endIndex ? String(rest[afterColon...]) : ""

            let coloredKey = highlightToonKey(keyPart)
            if valuePart.isEmpty {
                return indent + coloredKey + ANSI.punct + ":" + ANSI.reset
            }
            // Leading space before the value is conventional; keep it plain.
            if valuePart.hasPrefix(" ") {
                let v = String(valuePart.dropFirst())
                return indent + coloredKey + ANSI.punct + ":" + ANSI.reset + " " + highlightToonValue(v)
            }
            return indent + coloredKey + ANSI.punct + ":" + ANSI.reset + highlightToonValue(valuePart)
        }

        // No key — this is a bare value or a tabular data row (comma-separated).
        return indent + highlightToonRow(rest)
    }

    /// A key may be a plain field name or a table header `name[count]{a,b}`.
    private static func highlightToonKey(_ key: String) -> String {
        guard let bracket = key.firstIndex(where: { $0 == "[" || $0 == "{" }) else {
            return ANSI.key + key + ANSI.reset
        }
        let name = String(key[key.startIndex..<bracket])
        let decoration = String(key[bracket...])
        return ANSI.key + name + ANSI.reset + ANSI.punct + decoration + ANSI.reset
    }

    /// Highlight a single scalar value or, if it contains top-level commas,
    /// a tabular row.
    private static func highlightToonValue(_ value: String) -> String {
        if value.contains(",") {
            return highlightToonRow(value)
        }
        return colorScalar(value)
    }

    /// Highlight a comma-separated row of scalar fields.
    private static func highlightToonRow(_ row: String) -> String {
        var out = ""
        for (idx, field) in splitTopLevelCommas(row).enumerated() {
            if idx > 0 {
                out += ANSI.punct + "," + ANSI.reset
            }
            out += colorScalar(field)
        }
        return out
    }

    /// Color a single scalar according to its apparent type.
    private static func colorScalar(_ raw: String) -> String {
        // Preserve surrounding whitespace but classify the trimmed token.
        let leading = raw.prefix { $0 == " " }
        let trailing = raw.reversed().prefix { $0 == " " }.count
        let core = String(raw.dropFirst(leading.count).dropLast(trailing))
        let trail = String(raw.suffix(trailing))

        let color: String
        if core.isEmpty {
            return raw
        } else if core.hasPrefix("\"") {
            color = ANSI.string
        } else if core == "true" || core == "false" {
            color = ANSI.bool
        } else if core == "null" {
            color = ANSI.null
        } else if isNumeric(core) {
            color = ANSI.number
        } else {
            // Unquoted string value.
            color = ANSI.string
        }
        return String(leading) + color + core + ANSI.reset + trail
    }

    // MARK: - Scanning helpers

    /// The index of the first colon that is not inside brackets/braces or a
    /// quoted string — i.e. the `key:` separator.
    private static func topLevelColonIndex(_ s: String) -> String.Index? {
        var depth = 0
        var inQuote = false
        var idx = s.startIndex
        while idx < s.endIndex {
            let c = s[idx]
            if inQuote {
                if c == "\"" { inQuote = false }
            } else {
                switch c {
                case "\"": inQuote = true
                case "[", "{": depth += 1
                case "]", "}": depth -= 1
                case ":" where depth == 0: return idx
                default: break
                }
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    /// Split on commas that are not inside brackets/braces or quoted strings.
    private static func splitTopLevelCommas(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        for c in s {
            if inQuote {
                current.append(c)
                if c == "\"" { inQuote = false }
                continue
            }
            switch c {
            case "\"":
                inQuote = true
                current.append(c)
            case "[", "{":
                depth += 1
                current.append(c)
            case "]", "}":
                depth -= 1
                current.append(c)
            case "," where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(c)
            }
        }
        parts.append(current)
        return parts
    }

    private static func isNumeric(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        if Int64(s) != nil { return true }
        if Double(s) != nil { return true }
        return false
    }

    /// Match `true` / `false` / `null` starting at `i`, returning the token and
    /// its color, but only when the surrounding characters are word boundaries.
    private static func matchLiteral(_ chars: [Character], at i: Int) -> (String, String)? {
        let candidates: [(String, String)] = [
            ("true", ANSI.bool),
            ("false", ANSI.bool),
            ("null", ANSI.null),
        ]
        for (word, color) in candidates {
            let wordChars = Array(word)
            guard i + wordChars.count <= chars.count else { continue }
            if Array(chars[i..<(i + wordChars.count)]) == wordChars {
                let after = i + wordChars.count
                let nextIsBoundary = after >= chars.count || !chars[after].isLetter
                if nextIsBoundary {
                    return (word, color)
                }
            }
        }
        return nil
    }

    /// Scan a JSON number starting at `i`. Returns the literal and the index
    /// just past it.
    private static func scanNumber(_ chars: [Character], at i: Int, count n: Int) -> (String, Int) {
        var j = i
        if chars[j] == "-" { j += 1 }
        let numberSet: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "e", "E", "+", "-"]
        var start = j
        while j < n, numberSet.contains(chars[j]) {
            j += 1
        }
        // Require at least one digit.
        guard start < j else { return ("", i) }
        _ = start
        start = i
        return (String(chars[start..<j]), j)
    }
}

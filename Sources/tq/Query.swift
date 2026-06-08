import Foundation

// MARK: - Query Expression

/// A parsed query expression, similar to jq's expression syntax.
indirect enum QueryExpr: Equatable, CustomStringConvertible {
    /// Identity: `.` - returns the input as-is
    case identity
    /// Key access: `.key`
    case key(String)
    /// Index access: `.[0]`, `.[-1]`
    case index(Int)
    /// Array iteration: `.[]` - expands each element
    case iterator
    /// Slice: `.[start:end]`
    case slice(start: Int?, end: Int?)
    /// Sequence of expressions: `.key1.key2.[0]`
    case sequence([QueryExpr])

    var description: String {
        switch self {
        case .identity: return "."
        case let .key(k): return ".\(k)"
        case let .index(i): return "[\(i)]"
        case .iterator: return "[]"
        case let .slice(s, e):
            let sStr = s.map(String.init) ?? ""
            let eStr = e.map(String.init) ?? ""
            return "[\(sStr):\(eStr)]"
        case let .sequence(exprs):
            return exprs.map(\.description).joined()
        }
    }
}

// MARK: - Query Parser

enum QueryParser {
    /// Parse a jq-like expression string into a `QueryExpr`.
    ///
    /// Supported syntax:
    /// - `.`              → identity
    /// - `.key`           → key access
    /// - `.key1.key2`     → nested key access
    /// - `.[0]`, `.[-1]`  → array index
    /// - `.[]`            → array iterator (flatten)
    /// - `.[0:2]`, `.[:2]`, `.[1:]` → array slice
    ///
    /// Multiple expressions compose via chaining.
    static func parse(_ expr: String) throws -> QueryExpr {
        let trimmed = expr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.hasPrefix(".") else {
            throw QueryError.invalidExpression("Expression must start with '.'")
        }

        var exprs: [QueryExpr] = []
        var idx = trimmed.startIndex
        // Skip leading dot
        idx = trimmed.index(after: idx)

        while idx < trimmed.endIndex {
            let remaining = trimmed[idx...]
            if remaining.isEmpty {
                exprs.append(.identity)
                break
            }

            if remaining.first == "." {
                // Nested dot: move past it and treat next token as key
                idx = trimmed.index(after: idx)
                let key = readKey(from: trimmed, at: &idx)
                exprs.append(.key(key))
            } else if remaining.first == "[" {
                // Bracket expression: index, slice, or iterator
                let bracketResult = try readBracketExpr(from: trimmed, at: &idx)
                exprs.append(bracketResult)
            } else {
                // Plain key after initial dot
                let key = readKey(from: trimmed, at: &idx)
                exprs.append(.key(key))
            }
        }

        // If no expressions were parsed but input was "." or ".", treat as identity
        if exprs.isEmpty {
            return .identity
        }

        return exprs.count == 1 ? exprs[0] : .sequence(exprs)
    }

    private static func readKey(from str: String, at idx: inout String.Index) -> String {
        var key = ""
        while idx < str.endIndex {
            let ch = str[idx]
            if ch == "." || ch == "[" || ch == "]" || ch == ":" || ch.isWhitespace {
                break
            }
            key.append(ch)
            idx = str.index(after: idx)
        }
        return key
    }

    private static func readBracketExpr(from str: String, at idx: inout String.Index) throws -> QueryExpr {
        // Skip past '['
        idx = str.index(after: idx)

        // Check for iterator: "[]"
        if idx < str.endIndex, str[idx] == "]" {
            idx = str.index(after: idx)
            return .iterator
        }

        // Read the first part (could be a number, empty for slice, or a key string)
        var firstPart = ""
        var sawColon = false
        var secondPart = ""

        while idx < str.endIndex {
            let ch = str[idx]
            if ch == "]" {
                idx = str.index(after: idx)
                break
            }
            if ch == ":" {
                sawColon = true
                idx = str.index(after: idx)
                // Read second part for slice
                while idx < str.endIndex, str[idx] != "]" {
                    secondPart.append(str[idx])
                    idx = str.index(after: idx)
                }
                continue
            }
            if !sawColon {
                firstPart.append(ch)
            }
            idx = str.index(after: idx)
        }

        if sawColon {
            let startIdx = firstPart.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : Int(firstPart.trimmingCharacters(in: .whitespaces))
            let endIdx = secondPart.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : Int(secondPart.trimmingCharacters(in: .whitespaces))
            return .slice(start: startIdx, end: endIdx)
        }

        // Plain index
        guard let intVal = Int(firstPart.trimmingCharacters(in: .whitespaces)) else {
            throw QueryError.invalidExpression("Invalid index: \(firstPart)")
        }
        return .index(intVal)
    }
}

// MARK: - Query Evaluator

enum QueryEvaluator {
    /// Evaluate a query expression against a TOON node, returning zero or more results.
    static func evaluate(_ expr: QueryExpr, on node: TOONNode) throws -> [TOONNode] {
        switch expr {
        case .identity:
            return [node]

        case let .key(key):
            guard let value = node[key] else {
                return []
            }
            return [value]

        case let .index(idx):
            guard let value = node[idx] else {
                return []
            }
            return [value]

        case .iterator:
            guard case let .array(arr) = node else {
                throw QueryError.typeMismatch("Cannot iterate over non-array value")
            }
            return arr

        case let .slice(start, end):
            guard case let .array(arr) = node else {
                throw QueryError.typeMismatch("Cannot slice non-array value")
            }
            let s = start ?? 0
            let e = end ?? arr.count
            let clamped = arr.clampedSlice(from: s, to: e)
            return [.array(Array(clamped))]

        case let .sequence(exprs):
            // Chain evaluation: each step applies to all results from previous step
            var results = [node]
            for expr in exprs {
                results = try results.flatMap { try evaluate(expr, on: $0) }
            }
            return results
        }
    }
}

// MARK: - Errors

enum QueryError: Error, LocalizedError {
    case invalidExpression(String)
    case typeMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .invalidExpression(msg):
            return "Invalid expression: \(msg)"
        case let .typeMismatch(msg):
            return "Type mismatch: \(msg)"
        }
    }
}

// MARK: - Array Slice Helper

extension Array {
    func clampedSlice(from start: Int, to end: Int) -> ArraySlice<Element> {
        let s = Swift.max(0, start)
        let e = Swift.min(count, Swift.max(s, end))
        guard s < e else { return [] }
        return self[s..<e]
    }
}

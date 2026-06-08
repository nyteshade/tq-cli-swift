import Foundation

// MARK: - Path Segment

/// A single segment in a document path, used for mutations.
enum PathSegment: Equatable, CustomStringConvertible {
    case key(String)
    case index(Int)

    var description: String {
        switch self {
        case let .key(k): return ".\(k)"
        case let .index(i): return "[\(i)]"
        }
    }
}

// MARK: - Path Extraction from QueryExpr

extension QueryExpr {
    /// Extract a linear path (no iterators or slices) from a query expression.
    /// Returns nil if the expression contains iterator or slice segments.
    func asPath() -> [PathSegment]? {
        switch self {
        case .identity:
            return []
        case let .key(k):
            return [.key(k)]
        case let .index(i):
            return [.index(i)]
        case .iterator, .slice:
            return nil
        case let .sequence(exprs):
            var segments: [PathSegment] = []
            for expr in exprs {
                guard let subPath = expr.asPath() else { return nil }
                segments.append(contentsOf: subPath)
            }
            return segments
        }
    }
}

// MARK: - Mutation Operations

extension TOONNode {
    /// Set a value at the given path, auto-creating intermediate objects.
    /// Returns a new tree with the mutation applied.
    func setting(_ segments: [PathSegment], to value: TOONNode) -> TOONNode {
        guard let first = segments.first else {
            return value
        }
        let rest = Array(segments.dropFirst())

        switch first {
        case let .key(key):
            // Ensure we have an object to work with
            let (dict, keyOrder): ([String: TOONNode], [String])
            if case let .object(d, o) = self {
                dict = d
                keyOrder = o
            } else {
                // Auto-create: wrap non-object in a new object
                var d: [String: TOONNode] = [:]
                var o: [String] = []
                d[key] = TOONNode.object([:]).setting(rest, to: value)
                o.append(key)
                return .object(d, keyOrder: o)
            }

            var newDict = dict
            var newOrder = keyOrder
            if rest.isEmpty {
                newDict[key] = value
            } else {
                let child = newDict[key] ?? .object([:])
                newDict[key] = child.setting(rest, to: value)
            }
            if !newOrder.contains(key) {
                newOrder.append(key)
            }
            return .object(newDict, keyOrder: newOrder)

        case let .index(idx):
            let arr: [TOONNode]
            if case let .array(a) = self {
                arr = a
            } else {
                arr = []
            }
            var newArr = arr
            let resolved = idx < 0 ? max(0, newArr.count + idx) : idx
            while newArr.count <= resolved {
                newArr.append(.null)
            }
            if rest.isEmpty {
                newArr[resolved] = value
            } else {
                newArr[resolved] = newArr[resolved].setting(rest, to: value)
            }
            return .array(newArr)
        }
    }

    /// Delete the value at the given path. Returns nil if the root would be deleted,
    /// or the modified tree otherwise.
    func deleting(_ segments: [PathSegment]) -> TOONNode? {
        guard let first = segments.first else {
            return nil // Deleting root
        }
        let rest = Array(segments.dropFirst())

        switch first {
        case let .key(key):
            guard case let .object(dict, order) = self else {
                return self // Not an object, nothing to delete
            }
            var newDict = dict
            var newOrder = order
            if rest.isEmpty {
                newDict.removeValue(forKey: key)
                newOrder.removeAll { $0 == key }
            } else if let child = newDict[key] {
                if let modified = child.deleting(rest) {
                    newDict[key] = modified
                } else {
                    newDict.removeValue(forKey: key)
                    newOrder.removeAll { $0 == key }
                }
            }
            return .object(newDict, keyOrder: newOrder)

        case let .index(idx):
            guard case let .array(arr) = self else {
                return self
            }
            var newArr = arr
            let resolved = idx < 0 ? newArr.count + idx : idx
            guard resolved >= 0, resolved < newArr.count else {
                return self // Index out of bounds, no-op
            }
            if rest.isEmpty {
                newArr.remove(at: resolved)
            } else {
                if let modified = newArr[resolved].deleting(rest) {
                    newArr[resolved] = modified
                } else {
                    newArr.remove(at: resolved)
                }
            }
            return .array(newArr)
        }
    }

    /// Deep-merge another node into this one.
    /// - Objects are merged recursively; incoming values win on conflict.
    /// - Arrays: incoming replaces entirely.
    /// - Primitives: incoming wins.
    func merging(with other: TOONNode) -> TOONNode {
        switch (self, other) {
        case let (.object(dict, keyOrder), .object(otherDict, otherKeyOrder)):
            var merged = dict
            var order = keyOrder
            for key in otherKeyOrder {
                guard let otherVal = otherDict[key] else { continue }
                if let existing = merged[key] {
                    merged[key] = existing.merging(with: otherVal)
                } else {
                    merged[key] = otherVal
                    order.append(key)
                }
            }
            return .object(merged, keyOrder: order)

        case (.array, .array):
            return other

        default:
            return other
        }
    }
}

// MARK: - Mutation Command

enum MutationCommand: Equatable {
    case set(path: String, value: TOONNode)
    case del(path: String)
    case merge(node: TOONNode)
}

// MARK: - Mutation Runner

enum MutationRunner {
    /// Apply a mutation command to the given document, returning the modified document.
    static func apply(_ command: MutationCommand, to node: TOONNode) throws -> TOONNode {
        switch command {
        case let .set(pathStr, value):
            let expr = try QueryParser.parse(pathStr)
            guard let segments = expr.asPath() else {
                throw MutationError.invalidPath(
                    "Path '\(pathStr)' contains iterator or slice, which are not allowed for set"
                )
            }
            return node.setting(segments, to: value)

        case let .del(pathStr):
            let expr = try QueryParser.parse(pathStr)
            guard let segments = expr.asPath() else {
                throw MutationError.invalidPath(
                    "Path '\(pathStr)' contains iterator or slice, which are not allowed for del"
                )
            }
            guard segments.count > 0 else {
                throw MutationError.invalidPath("Cannot delete the root document")
            }
            guard let result = node.deleting(segments) else {
                throw MutationError.invalidPath("Cannot delete the root document")
            }
            return result

        case let .merge(other):
            return node.merging(with: other)
        }
    }
}

// MARK: - Mutation Errors

enum MutationError: Error, LocalizedError {
    case invalidPath(String)
    case missingValue
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPath(msg): return "Invalid path: \(msg)"
        case .missingValue: return "Missing value argument for set command"
        case let .invalidValue(msg): return "Invalid value: \(msg)"
        }
    }
}

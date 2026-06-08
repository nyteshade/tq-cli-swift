import Foundation
import ToonFormat

// MARK: - Output Mode

enum OutputMode: String, CaseIterable {
    case toon
    case json
}

// MARK: - Tq Mode

enum TqMode {
    /// Query mode: evaluate an expression against the document
    case query(expression: String)
    /// Mutation mode: apply a mutation to the document
    case mutation(command: MutationCommand)
}

// MARK: - Tq Command Options

struct TqOptions {
    var mode: TqMode = .query(expression: ".")
    var outputMode: OutputMode = .toon
    var rawOutput: Bool = false
    var compactOutput: Bool = false
    var inPlace: Bool = false
    var files: [String] = []
}

// MARK: - TqCommand

enum TqCommand {
    /// Run the tq command with the given arguments.
    static func run(arguments: [String]) async throws {
        let options = try parseArguments(Array(arguments.dropFirst()))

        // Read input
        let input: String
        if options.files.isEmpty {
            input = try readStdin()
        } else if options.inPlace {
            // With -i: if file doesn't exist, start with empty document
            input = options.files.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
                .joined(separator: "\n")
        } else {
            input = try options.files.map { try String(contentsOfFile: $0, encoding: .utf8) }
                .joined(separator: "\n")
        }

        // Decode input into TOONNode
        let node = try decodeInput(input)

        // Execute mode
        switch options.mode {
        case let .query(expression):
            let query = try QueryParser.parse(expression)
            let results = try QueryEvaluator.evaluate(query, on: node)
            if options.inPlace, !options.files.isEmpty {
                try writeResultsInPlace(results, options: options)
            } else {
                try outputResults(results, options: options)
            }

        case let .mutation(command):
            let modified = try MutationRunner.apply(command, to: node)
            let results = [modified]
            if options.inPlace, !options.files.isEmpty {
                try writeResultsInPlace(results, options: options)
            } else {
                // Hint: file given but no -i
                if !options.files.isEmpty {
                    fputs("tq: output written to stdout (use -i to modify the file in place)\n", stderr)
                }
                try outputResults(results, options: options)
            }
        }
    }

    // MARK: - Argument Parsing

    private static func parseArguments(_ args: [String]) throws -> TqOptions {
        // Check for subcommand as first positional argument
        let nonFlags = args.filter { !$0.hasPrefix("-") }

        if let subcmd = nonFlags.first, isSubcommand(subcmd) {
            return try parseMutationMode(args: args)
        }

        return try parseQueryMode(args: args)
    }

    private static func isSubcommand(_ word: String) -> Bool {
        return word == "set" || word == "del" || word == "delete" || word == "merge"
    }

    // MARK: - Query Mode Parsing

    private static func parseQueryMode(args: [String]) throws -> TqOptions {
        var options = TqOptions()
        var positional: [String] = []
        var i = 0

        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-h", "--help":
                printHelp()
                throw ExitError.help
            case "-V", "--version":
                printVersion()
                throw ExitError.help
            case "-r", "--raw-output":
                options.rawOutput = true
            case "-c", "--compact-output":
                options.compactOutput = true
            case "-j", "--json-output":
                options.outputMode = .json
            case "-t", "--toon-output":
                options.outputMode = .toon
            case "-i", "--in-place":
                options.inPlace = true
            case "-f", "--from-json":
                break
            default:
                if arg.hasPrefix("-") {
                    throw TqError.unknownOption(arg)
                }
                positional.append(arg)
            }
            i += 1
        }

        options.mode = .query(expression: positional.first ?? ".")
        if positional.count > 1 {
            options.files = Array(positional.dropFirst())
        }

        return options
    }

    // MARK: - Mutation Mode Parsing

    private static func parseMutationMode(args: [String]) throws -> TqOptions {
        var options = TqOptions()
        var i = 0
        var positional: [String] = []
        var inlineJSON: String? = nil
        var inlineTOON: String? = nil
        var mergeStdin: Bool = false

        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("-") {
                switch arg {
                case "-h", "--help":
                    printHelp()
                    throw ExitError.help
                case "-V", "--version":
                    printVersion()
                    throw ExitError.help
                case "-r", "--raw-output":
                    options.rawOutput = true
                case "-c", "--compact-output":
                    options.compactOutput = true
                case "-j", "--json-output":
                    options.outputMode = .json
                case "-t", "--toon-output":
                    options.outputMode = .toon
                case "-i", "--in-place":
                    options.inPlace = true
                case "--json":
                    i += 1
                    guard i < args.count else {
                        throw TqError.unknownOption("--json requires a value")
                    }
                    inlineJSON = args[i]
                case "--toon":
                    i += 1
                    guard i < args.count else {
                        throw TqError.unknownOption("--toon requires a value")
                    }
                    inlineTOON = args[i]
                case "-":
                    mergeStdin = true
                default:
                    throw TqError.unknownOption(arg)
                }
            } else {
                positional.append(arg)
            }
            i += 1
        }

        guard let subcommand = positional.first else {
            throw TqError.invalidInput("Missing subcommand")
        }

        switch subcommand {
        case "set":
            guard positional.count >= 2 else {
                throw TqError.invalidInput("set requires a path and a value")
            }
            let path = positional[1]
            let value: TOONNode

            if let jsonStr = inlineJSON {
                value = try decodeJSON(jsonStr)
            } else if let toonStr = inlineTOON {
                value = try decodeTOON(toonStr)
            } else if positional.count >= 3 {
                value = try parseLiteralValue(positional[2])
            } else {
                throw TqError.invalidInput("set requires a value (use --json or --toon for structured values, or a literal)")
            }

            options.mode = .mutation(command: .set(path: path, value: value))
            if positional.count > 3 {
                options.files = Array(positional.dropFirst(3))
            }

        case "del", "delete":
            guard positional.count >= 2 else {
                throw TqError.invalidInput("del requires a path")
            }
            options.mode = .mutation(command: .del(path: positional[1]))
            if positional.count > 2 {
                options.files = Array(positional.dropFirst(2))
            }

        case "merge":
            let sourceNode: TOONNode
            if let jsonStr = inlineJSON {
                sourceNode = try decodeJSON(jsonStr)
            } else if let toonStr = inlineTOON {
                sourceNode = try decodeTOON(toonStr)
            } else if mergeStdin {
                let stdinInput = try readStdin()
                sourceNode = try decodeInput(stdinInput)
            } else if positional.count >= 2 {
                let sourcePath = positional[1]
                let sourceInput = try String(contentsOfFile: sourcePath, encoding: .utf8)
                sourceNode = try decodeInput(sourceInput)
            } else {
                throw TqError.invalidInput("merge requires a source: file, --json, --toon, or - for stdin")
            }

            options.mode = .mutation(command: .merge(node: sourceNode))
            if positional.count > 2 {
                options.files = Array(positional.dropFirst(2))
            }

        default:
            throw TqError.invalidInput("Unknown subcommand: \(subcommand)")
        }

        return options
    }

    // MARK: - Literal Value Parsing

    /// Parse a literal value string into a TOONNode.
    /// - `true`, `false` → bool
    /// - `null` → null
    /// - integer → int
    /// - decimal → double
    /// - quoted string → string (strip quotes)
    /// - everything else → string
    private static func parseLiteralValue(_ raw: String) throws -> TOONNode {
        switch raw.lowercased() {
        case "null":
            return .null
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        default:
            break
        }

        // Quoted string
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") {
            let inner = String(raw.dropFirst().dropLast())
            return .string(inner)
        }

        // Number
        if let intVal = Int64(raw) {
            return .int(intVal)
        }
        if let doubleVal = Double(raw) {
            return .double(doubleVal)
        }

        // Default: unquoted string
        return .string(raw)
    }

    // MARK: - Input

    private static func readStdin() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8) else {
            throw TqError.invalidInput("Stdin is not valid UTF-8")
        }
        return str
    }

    private static func decodeInput(_ input: String) throws -> TOONNode {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .object([:])
        }

        let looksLikeJSON: Bool
        if trimmed.hasPrefix("{") {
            looksLikeJSON = true
        } else if trimmed.hasPrefix("[") {
            if let bracketEnd = trimmed.firstIndex(of: "]") {
                let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<bracketEnd]
                let cleaned = inside.trimmingCharacters(in: CharacterSet(charactersIn: "|\t"))
                if cleaned.allSatisfy(\.isNumber), !cleaned.isEmpty,
                   bracketEnd < trimmed.endIndex
                {
                    let after = trimmed[trimmed.index(after: bracketEnd)...]
                    let afterTrimmed = after.trimmingCharacters(in: .whitespaces)
                    if afterTrimmed.hasPrefix(":") || afterTrimmed.hasPrefix("{") {
                        looksLikeJSON = false
                    } else {
                        looksLikeJSON = true
                    }
                } else {
                    looksLikeJSON = true
                }
            } else {
                looksLikeJSON = true
            }
        } else if trimmed.hasPrefix("\"") || trimmed == "null"
            || trimmed == "true" || trimmed == "false"
        {
            looksLikeJSON = true
        } else if Double(trimmed) != nil {
            looksLikeJSON = true
        } else {
            looksLikeJSON = false
        }

        if looksLikeJSON {
            return try decodeJSON(trimmed)
        } else {
            return try decodeTOON(trimmed)
        }
    }

    private static func decodeTOON(_ text: String) throws -> TOONNode {
        guard let data = text.data(using: .utf8) else {
            throw TqError.invalidInput("TOON input is not valid UTF-8")
        }
        let decoder = TOONDecoder()
        return try decoder.decode(TOONNode.self, from: data)
    }

    private static func decodeJSON(_ text: String) throws -> TOONNode {
        guard let data = text.data(using: .utf8) else {
            throw TqError.invalidInput("JSON input is not valid UTF-8")
        }
        let jsonObj = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        return try convertToTOONNode(jsonObj)
    }

    private static func convertToTOONNode(_ obj: Any) throws -> TOONNode {
        switch obj {
        case is NSNull:
            return .null
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(try arr.map { try convertToTOONNode($0) })
        case let dict as [String: Any]:
            var values: [String: TOONNode] = [:]
            for (k, v) in dict {
                values[k] = try convertToTOONNode(v)
            }
            return .object(values, keyOrder: Array(dict.keys))
        case let num as NSNumber:
            let cfTypeID = CFGetTypeID(num as CFTypeRef)
            if cfTypeID == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            let type = String(cString: num.objCType)
            if type.contains("f") || type.contains("d") {
                return .double(num.doubleValue)
            } else {
                return .int(num.int64Value)
            }
        default:
            throw TqError.invalidInput("Unsupported JSON type: \(type(of: obj))")
        }
    }

    // MARK: - Output

    /// Write results back to the input file(s), overwriting them.
    private static func writeResultsInPlace(_ results: [TOONNode], options: TqOptions) throws {
        guard !options.files.isEmpty else {
            // Fall back to stdout
            try outputResults(results, options: options)
            return
        }

        for file in options.files {
            let output: String
            switch options.outputMode {
            case .json:
                // For in-place JSON, combine multiple results into an array if needed
                if results.count == 1 {
                    let pretty = !options.compactOutput
                    output = try results[0].toJSONString(pretty: pretty)
                } else {
                    let array = TOONNode.array(results)
                    let pretty = !options.compactOutput
                    output = try array.toJSONString(pretty: pretty)
                }
            case .toon:
                output = results.map { (try? $0.toTOONString()) ?? "" }
                    .joined(separator: "\n---\n")
            }
            try output.write(toFile: file, atomically: true, encoding: .utf8)
        }
    }

    private static func outputResults(_ results: [TOONNode], options: TqOptions) throws {
        if results.isEmpty {
            return
        }

        switch options.outputMode {
        case .json:
            try outputJSON(results, options: options)
        case .toon:
            try outputTOON(results, options: options)
        }
    }

    private static func outputJSON(_ results: [TOONNode], options: TqOptions) throws {
        for result in results {
            if options.rawOutput, case let .string(s) = result {
                print(s)
            } else {
                let pretty = !options.compactOutput
                let json = try result.toJSONString(pretty: pretty && results.count == 1)
                print(json)
                if results.count > 1, !options.compactOutput {
                    print("---")
                }
            }
        }
    }

    private static func outputTOON(_ results: [TOONNode], options: TqOptions) throws {
        for result in results {
            if options.rawOutput, case let .string(s) = result {
                print(s)
            } else {
                let toon = try result.toTOONString()
                print(toon)
                if results.count > 1 {
                    print("---")
                }
            }
        }
    }

    // MARK: - Help & Version

    private static func printHelp() {
        print("""
        tq - TOON query & mutation tool (jq for TOON)

        Query mode:
          tq [options] <expression> [file...]

        Mutation subcommands:
          tq set [options] <path> <value> [file]
          tq del [options] <path> [file]
          tq merge [options] <source> [file]

        Options:
          -j, --json-output    Output as JSON instead of TOON
          -r, --raw-output     Output raw strings (no quotes/formatting)
          -c, --compact-output Compact output (no pretty printing)
          -i, --in-place       Edit file in place (writes output back to input file)
          -h, --help           Show this help message
          -V, --version        Show version information

        Query expression syntax (jq-like):
          .                    Identity (pass through)
          .key                 Object field access
          .key1.key2           Nested field access
          .[0]                 Array index (0-based, negative for end)
          .[]                  Array iterator (flatten array)
          .[0:2]               Array slice (start:end)

        Mutation commands:
          set  <path> <value>  Set a value (auto-creates parent objects/arrays)
                               Use --json for JSON, --toon for TOON values
                               Literal examples: "hello", 42, true, null
          del  <path>          Delete a key or array element
          merge <source>       Deep-merge another document
                               <source>: file path, - (stdin),
                               --json '<json>', or --toon '<toon>'

        Examples:
          # Query
          echo 'name: Ada' | tq .name
          tq -j .users data.toon

          # Set (stdout by default)
          echo 'name: Ada' | tq set .age 36
          echo 'items:' | tq set .items[0] --json '{"id":1}'
          echo '{}' | tq set .user.name "Alice"

          # Set (in-place, modifies the file)
          tq -i set .name "Brielle" data.toon

          # Delete
          echo 'name:Ada\\nage:36' | tq del .age
          tq -i del .age data.toon

          # Merge
          echo 'a: 1' | tq merge --json '{"b":2}'
          tq -i merge extra.toon data.toon

          # Chaining
          cat data.toon | tq set .count 10 | tq del .temp | tq .users

        If no file is given, tq reads from stdin.
        Input can be either TOON or JSON (auto-detected).
        """)
    }

    private static func printVersion() {
        print("tq 0.2.0")
    }
}

// MARK: - Errors

enum TqError: Error, LocalizedError {
    case unknownOption(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case let .unknownOption(opt):
            return "Unknown option: \(opt). Use -h for help."
        case let .invalidInput(msg):
            return "Invalid input: \(msg)"
        }
    }
}

enum ExitError: Error {
    case help
}

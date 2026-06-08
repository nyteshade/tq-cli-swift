import Foundation

// tq - TOON query tool
do {
    try await TqCommand.run(arguments: CommandLine.arguments)
} catch let error as ExitError {
    // Graceful exit for --help/--version
    if case .help = error {
        Foundation.exit(0)
    }
} catch {
    fputs("tq: \(error.localizedDescription)\n", stderr)
    Foundation.exit(1)
}

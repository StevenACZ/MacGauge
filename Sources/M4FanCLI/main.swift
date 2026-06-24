import Darwin
import Foundation
import M4FanCore

do {
    try CLI(arguments: Array(CommandLine.arguments.dropFirst())).run()
} catch let error as CLIError {
    stderrLine("error: \(error.message)")
    exit(Int32(error.exitCode))
} catch let error as LocalizedError {
    stderrLine("error: \(error.errorDescription ?? String(describing: error))")
    exit(1)
} catch {
    stderrLine("error: \(error)")
    exit(1)
}

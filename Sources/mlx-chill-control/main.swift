import Foundation
import FanControlCore

do {
    let command = try FanControlCommand.parse(Array(CommandLine.arguments.dropFirst()))
    print("Parsed active fan-control command: \(command)")
    print("Execution remains disabled until crash and sleep/wake recovery are validated.")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

import FanProbeCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    mlx-chill

    Read-only Mac fan and thermal SMC probe.

    Usage:
      mlx-chill              Print host, fan, temperature, and power snapshot
      mlx-chill FNum F0Ac    Read explicit four-character SMC keys

    This tool does not expose any SMC write operation.
    """)
    exit(0)
}

if arguments.isEmpty {
    print(FanProbe.render(FanProbe.snapshot()))
    exit(0)
}

do {
    let client = try SMCClient()
    let readings = arguments.map { argument -> Result<SMCReading, Error> in
        do {
            return .success(try client.read(argument))
        } catch {
            return .failure(error)
        }
    }

    print(renderExplicitReadings(readings))
    exit(readings.contains { if case .failure = $0 { true } else { false } } ? 1 : 0)
} catch {
    print("ERROR  \(error)")
    exit(1)
}

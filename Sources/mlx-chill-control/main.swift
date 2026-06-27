import Foundation
import FanControlCore

do {
    let command = try FanControlCommand.parse(Array(CommandLine.arguments.dropFirst()))
    let capability = FanCapability.mac165ValidatedOneShot

    switch command {
    case .boostMax, .runBoostMax:
        guard capability.validation.activeControlEnabled else {
            let response = try FanControlCommandContract.disabledActiveControlResponse(
                for: command,
                capability: capability
            )
            print(response.stdout, terminator: "")
            exit(response.exitCode)
        }

        print(FanControlCommandContract.disabledActiveControlMessage(model: capability.model))

    case .auto:
        let store = FanLeaseStore.defaultStore()
        guard let lease = try store.readIfPresent() else {
            print("no active MLX & Chill fan-control lease; no recovery write attempted")
            exit(0)
        }

        guard lease.capabilityFingerprint == capability.fingerprint else {
            print("lease capability fingerprint mismatch; no recovery write attempted")
            exit(1)
        }

        print("auto is recovery-only for compatible existing MLX & Chill leases; recovery write execution remains disabled until recovery validation is complete")

    case .statusJSON:
        let response = try FanControlCommandContract.disabledActiveControlResponse(
            for: command,
            capability: capability
        )
        print(response.stdout, terminator: "")
        exit(response.exitCode)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}

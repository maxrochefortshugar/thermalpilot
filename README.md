# MLX & Chill

MLX & Chill is a read-only macOS fan and thermal probe for local AI workloads.

The first release focuses on trustworthy telemetry: fan count, current/min/max
RPM, selected temperature sensors, selected power sensors, and explicit SMC key
reads with raw bytes for auditability.

The longer-term goal is a native open source thermal assistant for Apple
Silicon machines: boost fans before local MLX/AI inference, then restore
Apple's automatic fan control.

## Status

- macOS only
- Apple Silicon tested on `Mac16,5` / M4 Max
- read-only SMC access
- no fan-control writes
- no background daemon
- no sudo requirement for the default probe

`mlx-chill-control` is present for active-control development and command
parsing, but boost execution remains disabled until crash recovery,
parent-death recovery, missed-heartbeat recovery, lease-expiry recovery, signal
recovery, and sleep/wake recovery are validated on hardware. `auto` remains
recovery-only for compatible existing MLX & Chill leases. The default
`mlx-chill` executable remains read-only.

## Build

```sh
swift build -c release
```

## Run

```sh
.build/release/mlx-chill
```

Read explicit SMC keys:

```sh
.build/release/mlx-chill FNum F0Ac F0Mn F0Mx F0Tg
```

Example output:

```text
MLX & Chill (read-only)

SMC
  Status: readable
  Key count: 3385
  Fan count: 2

Fans
  Fan 0
    Current: 0 [flt ]
    Minimum: 1350 [flt ]
    Maximum: 5777 [flt ]
    Target: 0 [flt ]
```

## Test

The installed Command Line Tools on the original development machine did not
expose `XCTest` or Swift `Testing` to SwiftPM, so the project uses a small
executable test runner for deterministic decoder coverage:

```sh
swift run FanProbeCoreTestRunner
```

## Safety model

The default `mlx-chill` executable intentionally exposes no SMC write API. The
C bridge only supports:

- open SMC user client
- close SMC user client
- read SMC key
- read SMC key by index

Active fan-control development lives behind the separate `mlx-chill-control`
executable. Boost and workload execution remain disabled until crash recovery,
parent-death recovery, missed-heartbeat recovery, lease-expiry recovery, signal
recovery, and sleep/wake recovery are validated on hardware.

## Roadmap

- Improve sensor labeling for Apple Silicon models.
- Add a compact menu-bar or terminal dashboard.
- Record bounded local thermal history.
- Add native max-boost and auto-restore fan control.
- Add a workload wrapper for MLX inference commands.
- Keep all active fan-control work opt-in and auditable.

## License

Apache-2.0

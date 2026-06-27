# ThermalPilot

ThermalPilot is a read-only macOS fan and thermal probe.

The first release focuses on trustworthy telemetry: fan count, current/min/max
RPM, selected temperature sensors, selected power sensors, and explicit SMC key
reads with raw bytes for auditability.

The longer-term goal is a smarter open source thermal assistant for Apple
Silicon machines: use local workload signals, MLX/AI inference activity, and
thermal history to avoid performance throttling before it happens.

## Status

- macOS only
- Apple Silicon tested on `Mac16,5` / M4 Max
- read-only SMC access
- no fan-control writes
- no background daemon
- no sudo requirement for the default probe

## Build

```sh
swift build -c release
```

## Run

```sh
.build/release/thermalpilot
```

Read explicit SMC keys:

```sh
.build/release/thermalpilot FNum F0Ac F0Mn F0Mx F0Tg
```

Example output:

```text
ThermalPilot (read-only)

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

This repository intentionally exposes no SMC write API today. The C bridge only
supports:

- open SMC user client
- close SMC user client
- read SMC key
- read SMC key by index

Future fan-control work should live behind explicit safety rails: clamp targets
to discovered hardware ranges, restore automatic mode on exit and wake, and
make read-only mode the default.

## Roadmap

- Improve sensor labeling for Apple Silicon models.
- Add a compact menu-bar or terminal dashboard.
- Record bounded local thermal history.
- Correlate thermal state with MLX inference workloads.
- Add predictive recommendations before considering any control loop.
- Keep all active fan-control work opt-in and auditable.

## License

MIT

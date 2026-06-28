# Read-Only Fan Probe Plan

Status: implemented
Updated: 2026-06-28

## Goal

Build the read-only foundation for Coldfront: a Swift CLI that can inspect
macOS SMC fan and thermal telemetry without sudo or write access.

## Current Shape

| Area | Implementation |
| --- | --- |
| CLI | `coldfront` |
| Package | Swift Package Manager |
| Read bridge | `Sources/CSMC` |
| Swift probe core | `Sources/FanProbeCore` |
| Tests | `FanProbeCoreTestRunner` |

## Commands

```sh
swift build -c release
.build/release/coldfront
.build/release/coldfront read FNum F0Ac F0Mn F0Mx F0Tg
swift run FanProbeCoreTestRunner
```

## Read Boundary

The read-only bridge exposes:

- open SMC user client
- close SMC user client
- read SMC key
- read SMC key by index

It does not expose a write function. Active fan writes live in the separate
`SMCControlTransport` module and are reachable only through explicit control
commands in the single `coldfront` binary.

## Completed

- FourCC conversion.
- `fpe2`, `sp78`, unsigned integer, and `flt ` decoding.
- Host and SMC snapshot output.
- Explicit key reads.
- Raw byte rendering for auditability.
- Release build.

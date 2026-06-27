# Mac16,5 Fan Control Validation

Date: 2026-06-27
Model: Mac16,5
Platform: j616c
macOS: Version 26.5.1 (Build 25F80)

## Result

One-shot max boost and restore succeeded.

## Observed Sequence

- `Ftst=1` required polling before readback changed.
- `F0Md/F1Md=1` initially returned SMC result `0x82`, then accepted.
- `F0Tg/F1Tg=5777` stuck after manual mode readback.
- Fan 0 reached `5505 RPM`.
- Fan 1 reached `5199 RPM`.
- Restore settled to `F0Md/F1Md=3`, `F0Tg/F1Tg=0`, `Ftst=0`, actual RPM `0`.

## Still Unverified

- Crash recovery.
- Sleep/wake recovery.
- Parent process death recovery.
- Missed-heartbeat recovery.
- Lease-expiry recovery.
- Signal handling recovery.
- Long-running workload wrapper.

## Active Control Decision

Keep `activeControlEnabled=false` until every recovery flag in `FanValidationState` is validated on hardware.

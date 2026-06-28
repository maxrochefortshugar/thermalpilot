# Mac16,5 Fan Control Validation

Date: 2026-06-27
Model: Mac16,5
Platform: j616c
macOS: Version 26.5.1 (Build 25F80)

## Result

One-shot max boost and restore succeeded. The current `coldfront` executable
enables manual `boost` and `auto` on this exact model/platform.

## Observed Sequence

- `Ftst=1` required polling before readback changed.
- `F0Md/F1Md=1` initially returned SMC result `0x82`, then accepted.
- `F0Tg/F1Tg=5777` stuck after manual mode readback.
- Fan 0 reached `5505 RPM`.
- Fan 1 reached `5199 RPM`.
- Restore settled to `F0Md/F1Md=3`, `F0Tg/F1Tg=0`, `Ftst=0`, actual RPM `0`.

## Still Unverified

- Background daemon recovery.
- Sleep/wake recovery invoked by a daemon.
- Parent process death recovery invoked by a daemon.
- Missed-heartbeat recovery invoked by a daemon.
- Lease-expiry recovery invoked by a daemon.
- Signal handling around a future workload wrapper.
- Long-running workload wrapper.

## Active Control Decision

Manual active control is enabled for `Mac16,5` / `j616c` in the current CLI.
There is no daemon yet, so the supported operator flow is:

```sh
sudo coldfront boost --for 10m -y
sudo coldfront auto
```

The static capability keeps daemon-oriented recovery flags separate from the
manual flow so future recovery work can be validated explicitly.

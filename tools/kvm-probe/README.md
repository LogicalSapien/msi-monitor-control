# MD342CQP HID probe tools

Small, dependency-free Swift scripts used to reverse-engineer the MSI MD342CQP's
USB-HID control protocol on real hardware. They are **guided probes**: each sends
one candidate report at a time and asks you to observe what the monitor does — the
monitor is output-only over HID (it does not report state back), so a human at the
screen is the detector.

All scripts:

- Match the monitor by **VID `0x1462` / PID `0x3FA4`**.
- Send the 53-byte ASCII command grammar documented in [`../../docs/PROTOCOL.md`](../../docs/PROTOCOL.md).
- **Open-and-retry** before each send: switching the KVM can detach USB from this
  Mac mid-run, which makes a stale handle return `kIOReturnNotOpen` (`0xe00002cd`).
- Run with plain `swift <file>` — no Xcode, no packages.

> ⚠️ These write to the monitor. The worst realistic case is "nothing happens"
> (monitors ignore reports they don't understand), but quit the main app first and
> keep keyboard/USB control on the machine running the probe.

## The scripts

| Script | Purpose |
|---|---|
| `kvm-probe.swift` | Cycle KVM positions 0–3 (feature `0x38 0x3e`) and map which value selects which source. |
| `kvm-send.swift`  | Send **one** KVM position and exit — relocates the device each run, so a KVM-induced USB detach can't break a follow-up. `swift kvm-send.swift <0-9>`. |
| `pbp-values.swift` | Cycle the value byte of a feature (default `0x36 0x30`, the PIP/PBP **mode** feature) to map off/PIP/PBP. `swift pbp-values.swift [hi lo]`. |
| `pbp-source-probe.swift` | Cycle a PBP **source-select** feature's value (the input enum) to find which window's source it sets. `swift pbp-source-probe.swift <hi> <lo>`. |
| `pbp-probe.swift` | General **feature-code sweep** — sends candidate 2-byte feature codes to discover an unknown feature. (PBP turned out to be a value of `0x36 0x30`, not a new code; kept as a discovery aid for future unknowns.) |
| `read-probe.swift` | Tests whether the monitor will **report its state back** via the read opcode + `IOHIDDeviceGetReport`. Result: it won't (`kIOReturnUnsupported`), so the app tracks last-sent state instead. |

## Confirmed mapping (from these probes)

Byte index 10 is the value; feature code is at indices 5–6.

- **Input** `0x35 0x30` — `0x30`=HDMI 1, `0x31`=HDMI 2, `0x32`=DisplayPort, `0x33`=USB-C/Type-C.
- **KVM** `0x38 0x3e` — `0x30`=Auto, `0x31`=Upstream, `0x32`=USB-C.
- **PIP/PBP mode** `0x36 0x30` — `0x30`=Off, `0x31`=PIP, `0x32`=PBP (`0x33`=an alternate PBP layout).
- **PBP sub-window source** `0x36 0x31` — value = the input enum above.
- **PBP main-window source** `0x36 0x32` — assumed same enum (not yet hardware-verified).

Tested on the MD342CQP only. Other MSI models may differ — these tools let you
confirm before trusting any value.

© 2026 LogicalSapien — MIT licence.

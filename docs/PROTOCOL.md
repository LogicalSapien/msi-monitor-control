# MSI Monitor HID Protocol

Single source of truth for all HID payloads sent to MSI monitors.
Both the macOS and Windows apps send byte-identical reports sourced from this file.

> **Safety note:** Payloads were obtained by reverse engineering. Use at your own risk.

---

## Device (VID/PID)

| Field      | Value    | Notes                          |
|:-----------|:---------|:-------------------------------|
| Vendor ID  | `0x1462` | MSI (Micro-Star International) |
| Product ID | `0x3FA4` | MD342CQP — tested              |

Obtained from: [Phaseowner/MSI-Display-Switch](https://github.com/Phaseowner/MSI-Display-Switch),
confirmed tested on MD342CQP.

---

## HID interface

| Field        | Value                | Notes                                                  |
|:-------------|:---------------------|:-------------------------------------------------------|
| Report type  | Output (`kIOHIDReportTypeOutput`) | `IOHIDDeviceSetReport` with `kIOHIDReportTypeOutput` |
| Report ID    | `0x01`               | First byte of every payload                            |
| Report size  | 64 bytes (`0x40`)    | Payload is always 64 bytes; unused bytes are `0x00`   |
| Usage page   | N/A (matched by VID/PID only) | The reference uses VID/PID matching, not usage page |

### macOS: device open-state can go stale (`kIOReturnNotOpen`)

On real hardware (MD342CQP, enumerates as "MSI Gaming Controller", VID `0x1462`
PID `0x3FA4`) the following was observed: input switching worked once via the app,
then a later send (KVM) failed with `IOReturn 0x10000003` = `kIOReturnNotOpen`.
The identical KVM bytes sent from a standalone script (open device →
`IOHIDDeviceSetReport` → send, in one context) returned `kIOReturnSuccess`. So the
payload and the SetReport API path are correct; the failure was that the app's
`IOHIDDevice` handle was no longer in an *open* state at send time.

Root cause: the device's open state is maintained by the `IOHIDManager`, which is
tied to the run loop it was scheduled on. In a SwiftUI `MenuBarExtra` app the
device is created during early app init, on a run-loop/thread context that is not
guaranteed to be the continuously-serviced one menu actions fire on; when that
run loop is not serviced the kernel can drop the handle back to not-open.

Fix (implemented in `MSIDevice.send`): open the device on demand at send time and,
if `SetReport` returns `kIOReturnNotOpen`/`kIOReturnNotPermitted`, re-locate +
re-open the device and retry the send exactly once. `IOHIDDeviceOpen` on an
already-open device is a success no-op, so this is safe to do before every send.

---

## Command grammar

The monitor speaks a UART-style ASCII command framed inside the HID report. This
grammar was decoded from [kdar/msi-monitor-ctrl](https://github.com/kdar/msi-monitor-ctrl)
(Rust) and is consistent with the input-switching payloads in
[Phaseowner/MSI-Display-Switch](https://github.com/Phaseowner/MSI-Display-Switch).

Every command is 12 meaningful bytes, zero-padded to the report size:

| Index | Value           | Meaning                                              |
|:------|:----------------|:-----------------------------------------------------|
| 0     | `0x01`          | Report ID                                            |
| 1     | `0x35`          | Header (fixed)                                       |
| 2     | RW              | `0x62` (`'b'`) = write, `0x38` (`'8'`) = read        |
| 3     | `0x30`          | Fixed                                                |
| 4     | `0x30`          | Fixed                                                |
| 5     | FEATURE_HI      | Feature code, high byte                              |
| 6     | FEATURE_LO      | Feature code, low byte                               |
| 7     | `0x30`          | Fixed                                                |
| 8     | `0x30`          | Fixed                                                |
| 9     | `0x30`          | Fixed                                                |
| 10    | `0x30` + value  | Value byte (`0x30` + position, ASCII digit)          |
| 11    | `0x0D`          | Carriage return — command terminator                 |

**Known feature codes** (at indices [5],[6]) — all HARDWARE-CONFIRMED on the
MD342CQP via `tools/kvm-probe` unless noted:

| Feature             | Code        | Values (index [10])                                   |
|:--------------------|:------------|:------------------------------------------------------|
| Input source        | `0x35 0x30` | `0`=HDMI1, `1`=HDMI2, `2`=DisplayPort, `3`=Type-C      |
| KVM                 | `0x38 0x3E` | `0`=Auto, `1`=Upstream, `2`=USB-C (`3`=no-op)          |
| PBP/PIP mode        | `0x36 0x30` | `0`=Off, `1`=PIP, `2`=PBP (`3`=2nd PBP variant)        |
| PBP source — sub    | `0x36 0x31` | input enum (`0`=HDMI1 … `3`=Type-C) for the sub window |
| PBP source — main   | `0x36 0x32` | input enum — **ASSUMED, not hardware-verified** (see note) |

> The **input enum** `0=HDMI1, 1=HDMI2, 2=DP, 3=Type-C` is reused as the value for
> both the Input feature and the PBP source-select features.
>
> **`0x36 0x32` (main/left window source) is ASSUMED**, not confirmed: the user
> couldn't probe it safely because the KVM/USB-C sits on the main window (switching
> it risks losing the control connection). It is assumed to use the same input enum
> as the sub-window feature `0x36 0x31`; verify when safe and update here.

---

## Payloads

All payloads are 64 bytes. Bytes not listed are `0x00`. The report ID (`0x01`)
is included as the first byte and passed to `IOHIDDeviceSetReport` as the
`reportID` argument.

### Input switching

These payloads were confirmed in the reference implementation (Phaseowner/MSI-Display-Switch,
tested on MD342CQP). Only byte[10] differs between inputs.

Feature `0x35 0x30`; byte[10] = the input enum. **All four inputs are
hardware-confirmed** (HDMI1/HDMI2 confirmed on the MD342CQP in v0.2.2 — previously
parked):

| Action           | Byte[10] | Byte[1..9] / [11]                              |
|:-----------------|:---------|:-----------------------------------------------|
| Input → HDMI 1   | `0x30`   | `35 62 30 30 35 30 30 30 30` … `0D`            |
| Input → HDMI 2   | `0x31`   | (same, byte[10]=`0x31`)                         |
| Input → DP       | `0x32`   | (same, byte[10]=`0x32`)                         |
| Input → Type-C   | `0x33`   | (same, byte[10]=`0x33`)                         |

Full byte arrays (53 bytes each; `IOHIDDeviceSetReport` uses `data.count`):

**Input → HDMI 1 (byte[10] = 0x30):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x30, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

**Input → HDMI 2 (byte[10] = 0x31):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x31, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

**Input → DP (byte[10] = 0x32):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

**Input → Type-C (byte[10] = 0x33):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

### KVM switching

Sourced from a second reference implementation,
[kdar/msi-monitor-ctrl](https://github.com/kdar/msi-monitor-ctrl) (Rust), which
targets the same monitor (VID `0x1462` / PID `0x3FA4`). KVM uses the 2-byte
feature code `0x38 0x3E` at indices [5],[6] (see **Command grammar** below).

**HARDWARE-CONFIRMED mapping (MD342CQP, 2026-06-22, via `tools/kvm-probe`):**
byte[10] selects the KVM port. The user cycled 0x30–0x33 on the real monitor:

| Action          | byte[10] | Payload (12 bytes, zero-padded)                       |
|:----------------|:---------|:------------------------------------------------------|
| KVM → Auto      | `0x30`   | `01 35 62 30 30 38 3E 30 30 30 30 0D`                 |
| KVM → Upstream  | `0x31`   | `01 35 62 30 30 38 3E 30 30 30 31 0D`                 |
| KVM → USB-C     | `0x32`   | `01 35 62 30 30 38 3E 30 30 30 32 0D`                 |
| (no 4th port)   | `0x33`   | no change observed                                    |

This **corrects** the earlier reference-guessed mapping (USB-C was wrongly `0x30`,
which is actually **Auto**) and supplies the previously-UNKNOWN **Auto** value
(`0x30`). All three are now live commands (`Command.kvmAuto` is no longer `nil`;
its hotkey is `⌃⇧⌘A`). Confirmed via `swift tools/kvm-probe/kvm-probe.swift`.

Full byte arrays:

**KVM → Auto (byte[10] = 0x30):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x30, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

**KVM → Upstream (byte[10] = 0x31):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x31, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

**KVM → USB-C (byte[10] = 0x32):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x38, 0x3E, 0x30, 0x30, 0x30, 0x32, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

> **KVM transport: HID SetReport (confirmed working).** The kdar reference sends KVM
> bytes over libusb interrupt OUT; we send via **HID SetReport**
> (`IOHIDDeviceSetReport` on macOS, `stream.Write` on Windows). Hardware-confirmed:
> the above payloads switch KVM correctly over HID SetReport. **Do not switch the
> transport to libusb; keep HID.**

### PBP / PIP (Picture-by-Picture / Picture-in-Picture)

HARDWARE-CONFIRMED on the MD342CQP (v0.2.2). PBP/PIP is **three distinct features**:
a mode selector and two per-window source selectors.

**Mode — feature `0x36 0x30`, byte[10] = mode:**

| Action      | byte[10] | Notes                                  |
|:------------|:---------|:---------------------------------------|
| PBP/PIP Off | `0x30`   | single full-screen input               |
| PIP         | `0x31`   | small inset window                     |
| PBP         | `0x32`   | side-by-side split                      |
| (PBP alt)   | `0x33`   | a 2nd PBP layout variant — optional     |

**Window source — byte[10] = the input enum (`0`=HDMI1,`1`=HDMI2,`2`=DP,`3`=Type-C):**

| Window            | Feature     | Status                                  |
|:------------------|:------------|:----------------------------------------|
| Sub  (right/PIP)  | `0x36 0x31` | hardware-confirmed                      |
| Main (left)       | `0x36 0x32` | **ASSUMED — not hardware-verified**     |

> **`0x36 0x32` (main-window source) is ASSUMED**, not confirmed: the user couldn't
> probe it safely (the KVM/USB-C control connection lives on the main window, so
> switching its source risks losing control). It is assumed to take the same input
> enum as the sub-window feature `0x36 0x31`. Apps must flag it as unverified in the
> UI; verify when safe and update here.

**Example payloads** (53 bytes; only feature bytes[5][6] + value byte[10] vary):

**PBP mode = PBP (feature 0x36 0x30, byte[10]=0x32):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

**PBP sub-source = HDMI2 (feature 0x36 0x31, byte[10]=0x31):**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x36, 0x31, 0x30, 0x30, 0x30, 0x31, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```

(The old `pbpOn`/`pbpOff` nil-payload stubs are REPLACED by this off/PIP/PBP model
— see the v0.2.2 design doc for the Command-enum mapping.)

---

## Reverse-engineering notes

### What is known (from Phaseowner/MSI-Display-Switch)

The reference app implements input switching only (HDMI 1, HDMI 2, DisplayPort, Type-C).
The payload structure follows an ASCII-like protocol: bytes[1..11] form the string
`5b00500000X\r` where `X` is the input selector:

| Byte[10] value | Input       |
|:---------------|:------------|
| `0x30` (`'0'`) | HDMI 1      |
| `0x31` (`'1'`) | HDMI 2      |
| `0x32` (`'2'`) | DisplayPort |
| `0x33` (`'3'`) | Type-C      |

This is an ASCII command protocol: the report body is a text command terminated
with `\r` (`0x0D`), zero-padded to the report size.

### Report-ID framing — RESOLVED (v0.2.6, Windows field debugging)

The two OS HID stacks treat the buffer's first byte differently, and this
matters because the monitor firmware needs the frame's leading `0x01` to arrive
**as report data**:

- **macOS** (`IOHIDDeviceSetReport`): the report ID is a separate argument; the
  buffer is delivered **verbatim** as report data. Passing the 53-byte frame
  (which begins `0x01`) with `reportID = 1` — as the working reference
  (Phaseowner/MSI-Display-Switch) does — delivers data beginning
  `01 35 62 …`. Hardware-confirmed working. Keep as-is.
- **Windows** (HidSharp `stream.Write`, i.e. `WriteFile` to the HID class
  driver): `buffer[0]` is **consumed as the report ID** and only the remaining
  bytes are delivered as report data. Passing the frame directly (the
  v0.2.0–v0.2.5 behaviour) delivered data beginning `35 62 30 …` — shifted one
  byte left — which the monitor **silently ignores** (the write itself
  succeeds). Observed in the field 2026-07-17: `Send … OK` logged, no input
  switch. Fix: prepend a report-ID byte (`0x01`) so the wire buffer is
  `[0x01] + frame` (54 bytes) and the full frame survives as data
  (`MsiDevice.ToWireReport`).

So the earlier "double-count" note had it backwards: the leading `0x01` in the
frame is genuine report **data** the firmware expects (the report ID also being
`0x01` is a coincidence of the protocol). macOS never double-sent; Windows was
under-sending.

### What is NOT known / unverified (Needs-decision)

As of v0.2.2, nearly everything is hardware-confirmed. Outstanding items:

- **PBP main-window source — feature `0x36 0x32`** — ASSUMED to take the input enum
  (same as the sub-window `0x36 0x31`) but NOT hardware-verified: the user couldn't
  probe it safely (KVM/USB-C control connection is on the main window). Apps flag it
  unverified in the UI. Verify when safe.
- **`0x33` for PBP mode** (a 2nd PBP layout variant) — observed but its exact layout
  isn't characterised; exposing it is optional.

(KVM, PBP/PIP mode, the PBP sub-window source, and all four inputs incl. HDMI 1/2
are now **hardware-confirmed** — see the sections above.)

- **No state read-back.** `IOHIDDeviceGetReport` for current input/KVM/mode returns
  `kIOReturnUnsupported` (`0xE0005000`) — the MD342CQP does not report its state.
  Apps therefore track the **last-sent** command to show a "current" highlight; this
  can go stale if the user switches via the physical OSD. See the v0.2.2 design doc.

### Reference

- Source: https://github.com/Phaseowner/MSI-Display-Switch (MIT licence)
- Tested hardware: MSI MD342CQP
- Extraction date: 2026-06-22

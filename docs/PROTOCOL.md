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

**Known feature codes** (at indices [5],[6]):

| Feature      | Code        | Values (index [10])                          |
|:-------------|:------------|:---------------------------------------------|
| Input source | `0x35 0x30` | `0`=HDMI1, `1`=HDMI2, `2`=DisplayPort, `3`=Type-C |
| KVM          | `0x38 0x3E` | `0`, `1` (USB-C vs Upstream — TODO confirm)   |
| PBP          | UNKNOWN     | almost certainly a distinct 2-byte feature code |

To discover PBP, sweep the **feature-code pair** at [5],[6] (not the value byte).

---

## Payloads

All payloads are 64 bytes. Bytes not listed are `0x00`. The report ID (`0x01`)
is included as the first byte and passed to `IOHIDDeviceSetReport` as the
`reportID` argument.

### Input switching

These payloads were confirmed in the reference implementation (Phaseowner/MSI-Display-Switch,
tested on MD342CQP). Only byte[10] differs between inputs.

| Action           | Byte[0] | Byte[1] | Byte[2] | Byte[3..9]              | Byte[10] | Byte[11] | Bytes[12..63] |
|:-----------------|:--------|:--------|:--------|:------------------------|:---------|:---------|:--------------|
| Input → Type-C   | `0x01`  | `0x35`  | `0x62`  | `0x30 0x30 0x35 0x30 0x30 0x30 0x30` | `0x33`   | `0x0D`   | `0x00` ×52   |
| Input → DP       | `0x01`  | `0x35`  | `0x62`  | `0x30 0x30 0x35 0x30 0x30 0x30 0x30` | `0x32`   | `0x0D`   | `0x00` ×52   |

Full byte arrays (64 bytes each):

**Input → Type-C:**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x33, 0x0D,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
0x00, 0x00, 0x00, 0x00, 0x00
```
(53 bytes — padded to 64 total including report ID; reference sends `reportSize = 0x40 = 64`,
 array length in reference is 53, `IOHIDDeviceSetReport` uses `data.count`)

**Input → DP:**
```
0x01, 0x35, 0x62, 0x30, 0x30, 0x35, 0x30, 0x30, 0x30, 0x30, 0x32, 0x0D,
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

### PBP (Picture-by-Picture)

| Action  | Payload                                        |
|:--------|:-----------------------------------------------|
| PBP On  | `UNKNOWN — needs hardware reverse-engineering` |
| PBP Off | `UNKNOWN — needs hardware reverse-engineering` |

PBP is **almost certainly another 2-byte feature code** at indices [5],[6] (the
same slot that holds `0x35 0x30` for input and `0x38 0x3E` for KVM). A hardware
probe to discover PBP should **sweep the feature-code pair** at [5],[6] — not the
value byte at [10] — while capturing HID traffic from MSI Productivity
Intelligence. See **Command grammar** below.

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

### Open question: report-ID handling (verify on hardware)

Both apps pass `byte[0]` (`0x01`) **twice**: once as the explicit report-ID
argument to the send call (`IOHIDDeviceSetReport` on macOS, `stream.Write` on
Windows) AND as the first byte of the buffer. Depending on how the OS HID stack
strips the leading report ID, the monitor may receive the `0x01` byte once or
twice. The reference implementation does the same and works on the MD342CQP, so
the current behaviour is kept as-is. This should be confirmed with a USB HID
capture against real hardware; if the byte is double-counted, drop the leading
`0x01` from the buffer (keeping it only as the report-ID argument). Tracked in
code with `// TODO(verify-on-hardware)` near the send call in both apps.

### What is NOT known (Needs-decision)

Only the **PBP** payloads remain unknown:

- **PBP On / PBP Off** — the reference README mentions "KVM like official MSI
  Productivity Intelligence" but the source only implements input switching; PBP
  payloads are not present, and the PBP feature code has not been captured.

(KVM → USB-C / Upstream / Auto were unknown/reference-guessed but are now
**hardware-confirmed** on the MD342CQP — see the KVM switching section above.)

To discover the PBP payloads, one approach is:
1. On Windows, run the official **MSI Productivity Intelligence** software while
   capturing USB HID traffic with Wireshark + USBPcap; OR
2. Use `tools/hid-probe` to sweep the 2-byte feature code at indices [5],[6] while
   toggling PBP from the OSD and watching for the picture to split.
3. Record the byte arrays here.

Until the PBP payloads are confirmed, `Command.pbpOn` / `pbpOff` return `payload =
nil` and are marked unavailable (hidden from the menu, no hotkey). All input and KVM
actions are live.

### Reference

- Source: https://github.com/Phaseowner/MSI-Display-Switch (MIT licence)
- Tested hardware: MSI MD342CQP
- Extraction date: 2026-06-22

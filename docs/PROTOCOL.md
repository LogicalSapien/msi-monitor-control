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

| Action          | Payload                                         |
|:----------------|:------------------------------------------------|
| KVM → USB-C     | `UNKNOWN — needs hardware reverse-engineering`  |
| KVM → Upstream  | `UNKNOWN — needs hardware reverse-engineering`  |

### PBP (Picture-by-Picture)

| Action  | Payload                                        |
|:--------|:-----------------------------------------------|
| PBP On  | `UNKNOWN — needs hardware reverse-engineering` |
| PBP Off | `UNKNOWN — needs hardware reverse-engineering` |

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

### What is NOT known (Needs-decision)

The following actions are **not implemented in the reference** and their payloads
are unknown:

- **PBP On / PBP Off** — the reference README mentions "KVM like official MSI
  Productivity Intelligence" but the source only implements input switching.
  PBP payloads are not present.
- **KVM → USB-C / KVM → Upstream** — similarly absent from the reference source.

To discover these payloads, one approach is:
1. On Windows, run the official **MSI Productivity Intelligence** software while
   capturing USB HID traffic with Wireshark + USBPcap.
2. Trigger PBP toggle and KVM switch from the official app and observe the HID
   output reports.
3. Record the byte arrays here.

Until those payloads are confirmed, the macOS and Windows apps will expose only
the two known input-switching actions (Type-C and DP) in the menu/hotkeys. The
`Command` enum stubs `pbpOn`, `pbpOff`, `kvmUSBC`, and `kvmUpstream` but these
are marked unavailable pending hardware reverse-engineering.

### Reference

- Source: https://github.com/Phaseowner/MSI-Display-Switch (MIT licence)
- Tested hardware: MSI MD342CQP
- Extraction date: 2026-06-22

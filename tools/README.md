# MSI MD342CQP — Capture & Probe Tools

These tools help you discover the unknown HID payloads for **PBP** (Picture-by-Picture)
and **KVM** switching on the MD342CQP.  They are single-file Swift scripts — no
installation, no Xcode project, no dependencies beyond macOS itself.

---

## Quick start — the realistic path

> **Short version:** The monitor does not send HID traffic back to the host when you
> press OSD buttons.  The practical way to find PBP/KVM payloads is to **send candidate
> opcodes one at a time and watch the monitor react.**  That is what `hid-probe` does.

---

## Prerequisites

- macOS 11 or later
- Monitor connected via **USB-A upstream cable** (not just DisplayPort/HDMI — the HID
  control channel rides over USB)
- `swift` in your PATH (comes with Xcode Command Line Tools):
  ```
  xcode-select --install
  ```

Run all commands from the **repository root** (the folder containing `macos/`, `windows/`, `tools/`).

---

## Step 1 — Confirm the device is visible

```bash
swift tools/hid-info/hid-info.swift
```

This enumerates every HID interface on VID=0x1462 PID=0x3FA4 and prints usage pages,
report sizes, and a live 3-second input-report listener.

**What you should see:** one or more interfaces, `maxOutputSize` > 0, and at the end
a message confirming that zero input reports arrived — which is expected.

If you see "Device NOT found", check the USB upstream cable.

---

## Step 2 — Probe for PBP / KVM opcodes (interactive)

```bash
swift tools/hid-probe/hid-probe.swift
```

You will see a numbered menu:

```
  1) 0x30  Input → HDMI 1     (known-good)
  2) 0x31  Input → HDMI 2     (known-good)
  3) 0x32  Input → DisplayPort (known-good)
  4) 0x33  Input → Type-C     (known-good)
  5) 0x34  ? candidate — observe monitor
  6) 0x35  ? candidate — observe monitor
  ...
 c) Enter a custom opcode
 q) Quit
```

**Start with opcodes 1–4 as a baseline** — they are known-good and confirm that sends
are reaching the monitor.  The monitor should switch its input when you choose option 3
(DisplayPort) or 4 (Type-C).

Then work through the `?` candidates (options 5 onwards).  For each one:
1. Choose the number and press Enter.
2. The tool sends the payload and prints `OK`.
3. **Watch the monitor's OSD or picture** for about 2 seconds.
4. Note what happened (input switch? PBP activated? nothing?).
5. Press Enter to continue to the next candidate.

---

## Step 3 — Record what you find

When a candidate causes PBP to toggle or KVM to switch, note the opcode byte shown in
the output:

```
Opcode: 0x36  (ASCII '6')
Payload (53 bytes):
  01 35 62 30 30 35 30 30 30 30 36 0d [..zeros..]
```

Paste the full payload hex into [`docs/PROTOCOL.md`](../docs/PROTOCOL.md) under the
relevant action.  The macOS and Windows apps will be updated to use it.

---

## Sweep mode (optional — faster search)

To walk through a range of opcodes without re-invoking the tool each time:

```bash
swift tools/hid-probe/hid-probe.swift --sweep 0x34 0x50
```

The tool sends each opcode, pauses, and waits for Enter before moving on.
Type `q` + Enter at any pause to stop.

---

## Single opcode (non-interactive, for scripting)

```bash
swift tools/hid-probe/hid-probe.swift --opcode 0x33
```

Sends one opcode and exits.  Useful for scripting or confirming a specific payload.

---

## Passive capture (probably not useful — but here for completeness)

```bash
swift tools/hid-capture/hid-capture.swift
```

Listens for input reports from the monitor for 30 seconds.  **Almost certainly captures
nothing** — the MD342CQP protocol is output-only (host sends, monitor acts silently).
OSD button presses do not generate any host-visible HID traffic.

If you are running MSI Productivity Intelligence on Windows over the same USB bus, that
software sends output reports which USBPcap can capture.  See
[`docs/REVERSE-ENGINEERING.md`](../docs/REVERSE-ENGINEERING.md) for the Wireshark method.

---

## Why passive capture doesn't work here

The MSI MD342CQP uses a **pure output-report protocol**:

- The host (your Mac) sends a 53-byte ASCII command to the monitor.
- The monitor acts on it silently — no acknowledgement report is sent back.
- Pressing OSD buttons on the monitor triggers internal firmware logic only.

An `IOHIDManager` input-report callback fires only when the device sends data **to** the
host.  For this monitor, that never happens during normal use.  Therefore `hid-capture`
captures nothing, and Wireshark on macOS is equally useless for this use-case.

**The opcode probe (`hid-probe`) is the correct method.**

---

## Tool reference

| Tool | File | Purpose |
|:-----|:-----|:--------|
| `hid-info` | `tools/hid-info/hid-info.swift` | Enumerate device, print HID interfaces, confirm connectivity |
| `hid-capture` | `tools/hid-capture/hid-capture.swift` | Listen for input reports (expected: none) |
| `hid-probe` | `tools/hid-probe/hid-probe.swift` | **Primary RE tool** — send opcode candidates, observe monitor |

---

## Safety note

Sending an unrecognised opcode to the monitor is low-risk.  The monitor firmware
ignores commands it does not recognise — the realistic outcome is "nothing happens".
`hid-probe` only sends payloads that match the known 53-byte structure; it does not
send arbitrary data.

© 2026 LogicalSapien — MIT licence

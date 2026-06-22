# MSI MD342CQP — Capture & Probe Tools

These tools help you discover the unknown HID payloads for **PBP** (Picture-by-Picture)
and **KVM** switching on the MD342CQP.  They are single-file Swift scripts — no
installation, no Xcode project, no dependencies beyond macOS itself.

---

## Quick start — the realistic path

> **Short version:** The monitor does not send HID traffic back to the host when you
> press OSD buttons.  The practical way to find PBP/KVM payloads is to **send candidate
> commands one at a time and watch the monitor react.**  That is what `hid-probe` does.

---

## The command grammar (read this first)

Thanks to the [kdar/msi-monitor-ctrl](https://github.com/kdar/msi-monitor-ctrl) reference
(`src/device.rs`) we now know the full command shape.  Every command is a 53-byte ASCII
report:

```
Index  0    1    2    3    4    5       6       7    8    9    10          11    12..
Byte   01   35   RW   30   30   FEAT_HI FEAT_LO 30   30   30   (30+value)  0d    00 (padding)
            '5'                 └── feature ──┘                 value           '\r'
```

- **RW** (index 2): `0x62` = write, `0x38` = read.
- **FEATURE** (indices 5,6): a **2-byte** selector — this picks *what* you are changing.
- **VALUE** (index 10): `0x30 + position`, picks *which option* within the feature.

**Known feature codes:**

| Feature | FEAT_HI, FEAT_LO | Values |
|:--------|:-----------------|:-------|
| Input   | `0x35, 0x30` (`'5','0'`) | `0`=HDMI 1, `1`=HDMI 2, `2`=DP, `3`=Type-C |
| KVM     | `0x38, 0x3e` (`'8','>'`) | selects KVM source |
| **PBP** | **UNKNOWN** | **what we hunt for below** |

> **Key insight:** PBP is almost certainly *another 2-byte feature code* at indices 5,6 —
> **not** a different value byte.  So to find PBP we sweep the **feature pair**, holding
> the value byte fixed at `1` ("on").

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

## Step 2 — Confirm a known feature works (baseline)

Before hunting for PBP, prove that commands are reaching the monitor.  Send a known
command and watch the monitor react:

```bash
# Input → Type-C — the monitor should switch its input source
swift tools/hid-probe/hid-probe.swift --feature 0x35 0x30 --value 3

# KVM — the known KVM feature
swift tools/hid-probe/hid-probe.swift --feature 0x38 0x3e --value 1
```

If the input switches, sends are working and you are ready to hunt for PBP.

---

## Step 3 — Hunt for PBP (the guided feature sweep)

```bash
swift tools/hid-probe/hid-probe.swift
```

You will see a menu.  Choose **`f`** — "PBP discovery — guided feature sweep".

The tool will walk you through it:

1. **First, on the monitor's OSD, turn PBP / PIP OFF.**  This is your baseline so you can
   see it turn on.  Make sure two sources are connected so a split picture is visible.
2. Accept the default sweep range (`0x30`–`0x3f`) and value (`1` = "on").
3. The tool sends one candidate feature pair at a time (the value byte fixed at `1`).
   The known Input and KVM features are skipped automatically so a real input/KVM switch
   is not mistaken for PBP.
4. After each send, **watch the screen for ~2 seconds**:
   - Picture splits / a second source appears → **PBP just turned on.**  Answer `y`.
   - Nothing → press **Enter** for the next candidate.
   - Want to stop → type `q`.
5. When you answer `y`, the tool prints the PBP-On payload, then sends value `0` to find
   the PBP-Off payload, and prints both ready to paste into PROTOCOL.md.

### Faster: semi-automatic feature sweep

To send the whole range automatically with a delay between each (watch the screen and
note which feature pair causes the change):

```bash
swift tools/hid-probe/hid-probe.swift --sweep-feature 0x30 0x3f --delay 2.5
```

Then re-run the feature pair that reacted in interactive mode to capture both on/off values.

---

## Step 4 — Record what you find

When the guided flow finds PBP it prints exactly what to record, e.g.:

```
RECORD THESE IN docs/PROTOCOL.md:
PBP On  = 01 35 62 30 30 3a 31 30 30 30 31 0d 00 00 ...
PBP Off = 01 35 62 30 30 3a 31 30 30 30 30 0d 00 00 ...
```

(The `3a 31` above is an illustrative feature pair, not a confirmed value.)
Paste the full payload hex into [`docs/PROTOCOL.md`](../docs/PROTOCOL.md) under the
relevant action.  The macOS and Windows apps will then be wired to use it.

---

## Single command (non-interactive, for scripting)

```bash
swift tools/hid-probe/hid-probe.swift --feature <hi> <lo> --value <n>
```

Sends one command and exits.  Useful for re-confirming a discovered payload, e.g.
`--feature 0x35 0x30 --value 2` for Input → DisplayPort.

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

**The feature probe (`hid-probe`) is the correct method.**

---

## Tool reference

| Tool | File | Purpose |
|:-----|:-----|:--------|
| `hid-info` | `tools/hid-info/hid-info.swift` | Enumerate device, print HID interfaces, confirm connectivity |
| `hid-capture` | `tools/hid-capture/hid-capture.swift` | Listen for input reports (expected: none) |
| `hid-probe` | `tools/hid-probe/hid-probe.swift` | **Primary RE tool** — send feature-code candidates, observe monitor |
| `kvm-probe` | `tools/kvm-probe/kvm-probe.swift` | Guided KVM byte[10]→port mapper — sends feature `0x38 0x3e`, byte[10] cycling 0x30–0x33 one per Enter, so you record which source each value selects. Mapping CONFIRMED: 0x30=Auto, 0x31=Upstream, 0x32=USB-C |
| `kvm-send` | `tools/kvm-probe/kvm-send.swift` | Send ONE KVM position then exit (`swift … 0..3`). Locates the device fresh each run so a KVM-induced USB detach can't break a follow-up send — handy when probing one value at a time |

---

## Safety note

Sending an unrecognised command to the monitor is low-risk.  The monitor firmware
ignores commands it does not recognise — the realistic outcome is "nothing happens".
`hid-probe` only sends payloads that match the known 53-byte grammar (correct prefix,
feature pair, value byte and terminator); it does not send arbitrary data.

© 2026 LogicalSapien — MIT licence

# Reverse-engineering MSI HID payloads (PBP & KVM)

The Phaseowner reference only reliably provides **input-source** switching payloads. **PBP**
(Picture-by-Picture) and **KVM** switching almost certainly need to be captured from your own
MD342CQP. This guide walks through capturing those raw USB HID reports on macOS, then dropping
the bytes into [`PROTOCOL.md`](PROTOCOL.md).

You only need to do this **once**. It takes ~30–45 minutes. You must be at the machine the
monitor is plugged into.

---

## What we're doing

When you toggle PBP or KVM from the monitor's own on-screen menu (OSD) — or from MSI's own
desktop software if you have it — the host or the monitor exchanges a short USB HID report.
We watch the USB bus, perform the toggle, and read off the exact bytes that changed. Those bytes
are the payload our app will send.

There are two capture methods. **Method A (Wireshark) is recommended** — it's the standard tool
and shows everything. Method B is a fallback if Wireshark/USBPcap-equivalent gives you trouble.

---

## Before you start — identify the device

We need the monitor's USB Vendor ID (VID) and Product ID (PID), and which HID interface carries
the control reports. Run:

```bash
# Lists every HID device with vendor/product IDs and usage pages
ioreg -p IOUSB -l -w 0 | grep -iE "MSI|idVendor|idProduct|USB Product Name" | sed -n '1,80p'
```

or, more readable:

```bash
system_profiler SPUSBDataType | grep -iA8 "MSI\|MD342\|Display"
```

Note the **Vendor ID** (MSI is typically `0x1462`) and **Product ID** for the monitor. Write them
down — they go in PROTOCOL.md's Device section and confirm the macOS teammate's extracted values.

---

## Method A — Wireshark USB capture (recommended)

macOS can capture USB traffic through Wireshark once a capture interface is enabled.

### 1. Install

```bash
brew install --cask wireshark
```

Wireshark on macOS captures USB via the `XHC*`/`usbmon`-equivalent interfaces exposed by Apple's
`IOUSBHost`. On a first run it will ask to install the ChmodBPF helper — allow it (needed for the
capture interfaces to appear). Reboot if the USB interfaces don't show up.

### 2. Start capturing

1. Open Wireshark.
2. In the interface list, pick the USB capture interface that corresponds to the bus your monitor
   is on (often named like `XHC20` / `usbmonN`). If unsure, start capture on each in turn and
   wiggle a USB device to see which one shows traffic.
3. Apply a display filter to cut noise. Filter by your monitor's VID (example for MSI `0x1462`):

   ```
   usb.idVendor == 0x1462
   ```

   or filter to HID SET_REPORT control transfers (where output/feature reports usually ride):

   ```
   usb.bmRequestType == 0x21 && usb.setup.bRequest == 0x09
   ```

### 3. Capture one action at a time (the key discipline)

Do these **one at a time**, clearing the capture between each so you know exactly which bytes map
to which action:

| Step | What you do on the hardware | Label the capture |
|------|------------------------------|-------------------|
| 1 | Toggle **PBP ON** from the monitor OSD (or MSI software) | `pbp-on` |
| 2 | Toggle **PBP OFF** | `pbp-off` |
| 3 | Switch **KVM → USB-C** | `kvm-usbc` |
| 4 | Switch **KVM → Upstream** | `kvm-upstream` |

For each: clear the capture (or note the packet number), perform exactly one toggle on the
monitor, stop. You're looking for a **SET_REPORT / output / feature report** packet that appears
right when you toggle. Click it; in the packet detail expand **HID Data** / **Leftover Capture
Data** — that byte string is the payload.

### 4. Read off the bytes

The relevant packet shows something like:

```
HID Data: 53 84 03 e1 01 ...
```

Copy the **full report payload** (all the data bytes — keep leading report-ID byte if present).
That's your payload for that action.

> Tip: do each toggle 2–3 times and confirm you get the **same** bytes each time. Consistent bytes
> = real payload. If the bytes change every time, you may be capturing the wrong transfer (e.g. a
> status poll) — keep the tighter `bRequest == 0x09` filter on.

---

## Method B — fallback: compare against the working input payload

If Wireshark is painful, we can exploit a shortcut. The reference's **input-switch payload is
known and working**. MSI's reports usually share a structure: a fixed header + an opcode byte +
a value byte. So:

1. From PROTOCOL.md, look at the known input-switch payloads (Type-C vs DP) side by side. The bytes
   that **differ** between them tell you which position is the "value" and which is the "opcode".
2. PBP and KVM are likely the **same structure with a different opcode**. Sometimes MSI exposes
   these as VCP-like feature codes. This narrows the search a lot — but it's still a guess until
   confirmed on hardware, so we'd verify by sending a candidate and watching the monitor react
   (safe: the worst case is "nothing happens").

This method gets us a hypothesis fast; Method A confirms it. **We will not ship guessed bytes
without confirming the monitor actually responds.**

---

## Putting the bytes into the app

Once you have the bytes for an action, paste them to the lead (Claude) like:

```
PBP ON   = 53 84 03 e1 01
PBP OFF  = 53 84 03 e1 00
KVM USB-C    = ...
KVM Upstream = ...
```

The lead hands them to the macOS teammate, who:
1. Records them in [`PROTOCOL.md`](PROTOCOL.md) (single source of truth).
2. Wires them into `Command.payload`.
3. The Windows teammate copies the identical bytes into `Command.PayloadFor`.

Then you smoke-test: click the action in the menu/tray app and confirm the monitor actually
toggles PBP / switches KVM.

---

## Safety

- Sending an unexpected HID report to a monitor is low-risk — monitors ignore reports they don't
  understand. The realistic failure mode is "nothing happens", not damage.
- Still: we confirm each captured payload reproduces the OSD behaviour before committing it as
  final. No invented bytes ship to `main`.

---

## Tooling (preferred path — use these first)

The `tools/` directory contains three single-file Swift scripts that run directly on
macOS with no dependencies beyond the system Swift toolchain (from Xcode Command Line
Tools).  No Wireshark, no extra software, no Windows required.

### Honest assessment — does passive HID capture work?

**No, not for OSD-triggered actions.** The MD342CQP protocol is purely output-report:
the host writes 53-byte ASCII commands to the monitor; the monitor acts silently with
no HID report sent back.  Pressing OSD buttons on the monitor triggers internal firmware
state changes that are invisible to the host over HID.  An `IOHIDManager` input-report
listener (Method B in the Wireshark-alternative approaches) captures nothing.

The only scenario where Wireshark on macOS would help is if MSI's own desktop software
(Windows-only) were running on the same machine and issuing output reports — but that
software does not exist for macOS.

### The command grammar (kdar reference)

A second reference, [kdar/msi-monitor-ctrl](https://github.com/kdar/msi-monitor-ctrl)
(`src/device.rs`), revealed the full command grammar for this monitor.  Every command is a
53-byte ASCII report:

```
Index  0    1    2    3    4    5       6       7    8    9    10          11    12..
Byte   01   35   RW   30   30   FEAT_HI FEAT_LO 30   30   30   (30+value)  0d    00 (padding)
            '5'                 └── feature ──┘                 value           '\r'
```

- **RW** (index 2): `0x62` = write, `0x38` = read.
- **FEATURE** (indices 5,6): a **2-byte** selector — picks *what* you are changing.
- **VALUE** (index 10): `0x30 + position` — picks *which option* within the feature.

| Feature | FEAT_HI, FEAT_LO | Values |
|:--------|:-----------------|:-------|
| Input   | `0x35, 0x30`     | `0`=HDMI 1, `1`=HDMI 2, `2`=DP, `3`=Type-C |
| KVM     | `0x38, 0x3e`     | selects KVM source (confirmed in kdar) |
| **PBP** | **UNKNOWN**      | the target of the feature sweep below |

This corroborates the known Input payloads in PROTOCOL.md exactly (`RW=0x62`,
`FEAT=0x35,0x30`, value at index 10).

> **Key insight:** PBP is almost certainly *another 2-byte feature code* at indices 5,6 —
> **not** a different value byte at index 10.  A value-byte sweep will never find it.
> The realistic discovery route is a **feature-pair sweep** holding the value byte fixed
> at `1` ("on").

### Recommended method: feature probing via `hid-probe`

```bash
# Step 1 — confirm the device is visible (run from repo root)
swift tools/hid-info/hid-info.swift

# Step 2 — confirm a known feature reaches the monitor (baseline)
swift tools/hid-probe/hid-probe.swift --feature 0x35 0x30 --value 3   # Input → Type-C

# Step 3 — hunt for PBP: interactive guided feature sweep
swift tools/hid-probe/hid-probe.swift            # then choose menu option "f"

# Or — semi-automatic feature sweep with a delay between sends:
swift tools/hid-probe/hid-probe.swift --sweep-feature 0x30 0x3f --delay 2.5
```

**OSD sequence for the PBP hunt:**

1. On the monitor OSD, set **PBP / PIP to OFF** — this is your baseline.  Connect two
   sources so a split picture is visible when PBP turns on.
2. Run `hid-probe` and choose menu option **`f`** (PBP discovery).  Accept the default
   sweep range `0x30`–`0x3f` and value `1`.
3. The tool sends one **feature pair** candidate at a time (value fixed at `1`), skipping
   the known Input and KVM features.  After each send:
   - Picture splits / second source appears → **PBP found.**  Answer `y`.
   - Nothing → press **Enter** for the next candidate (`q` to stop).
4. On `y`, the tool prints the PBP-On payload, then sends value `0` to capture PBP-Off,
   and prints both ready to paste into PROTOCOL.md.

### Tool reference

| Tool | Command | Purpose |
|:-----|:--------|:--------|
| `hid-info` | `swift tools/hid-info/hid-info.swift` | Enumerate HID interfaces, verify connectivity, confirm passive-capture yields nothing |
| `hid-capture` | `swift tools/hid-capture/hid-capture.swift` | Listen for input reports — expected to capture nothing; run once to verify |
| `hid-probe` | `swift tools/hid-probe/hid-probe.swift` | **Primary RE tool.** Sweep feature-code candidates, observe monitor |

See [`../tools/README.md`](../tools/README.md) for full usage, the grammar, and sweep modes.

### When Method A (Wireshark) IS the right choice

Use Wireshark + USBPcap on Windows if:
- You have a Windows machine with MSI Productivity Intelligence installed.
- You want to capture the exact bytes MSI's own software sends for PBP/KVM (highest
  confidence — you're reading the official payload, not probing for it).

In that case, follow the Wireshark guide above (Method A).  The feature-probe approach
and Wireshark are complementary — either route eventually gives you the same bytes.

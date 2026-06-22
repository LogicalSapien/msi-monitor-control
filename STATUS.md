# STATUS — msi-monitor-control

**Created:** 2026-06-22

## Current focus

Phase 1 code complete + post-MVP hardening. Awaiting CI green + human smoke test.
- **msi-mac** — Track A (scaffold), Track B (macOS app), `docs/PROTOCOL.md`, D-macos CI: **COMPLETE**.
  Post-MVP: .app bundle packaging, resource-leak fixes, KVM payloads wired in (2026-06-22).
- **msi-windows** — Track C (Windows app) + Track D windows CI: **COMPLETE** (committed 2026-06-22).

### Post-MVP work (msi-mac, 2026-06-22)

| Item | Commit | Notes |
|:-----|:-------|:------|
| `.app` bundle packaging | 2331fc7 | `macos/build-app.sh` → `build/MSIMonitorControl.app`. LSUIElement bundle, unsigned (Phase 1). Activation policy moved to `NSApplicationDelegateAdaptor` (fixed launch crash). Verified: launches as no-Dock menu-bar item. |
| Resource-leak fixes | ef804bf | IOHIDManager/Device now closed (was leaking USB claim); manager scheduled on run loop before `CopyDevices` (reliable enumeration); safe CFTypeID downcast; HotKeys `passRetained` balanced in deinit, `[weak self]` dispatch, OSStatus logging. |
| KVM switching | 53c1c09 | New reference `kdar/msi-monitor-ctrl` decoded. PROTOCOL.md gains Command grammar + KVM payloads (feature `0x38 0x3E`). `kvmUSBC`/`kvmUpstream` now have payloads → live menu items + hotkeys. |

**KVM Needs-decision (verify-on-hardware):**
- Position→port mapping is UNCONFIRMED: we map USB-C=position 0, Upstream=position 1. Flip if wrong.
- kdar uses libusb interrupt OUT; we keep HID SetReport. Bytes expected identical; confirm on hardware.
- Possible report-ID double-counting (byte[0]=0x01 as both reportID arg and buffer[0]) — flagged in code + PROTOCOL.md.

**To run the .app:** `cd macos && ./build-app.sh && open build/MSIMonitorControl.app`
(unsigned — right-click → Open on first launch to bypass Gatekeeper).

### macOS app — msi-mac (completed this session)

| Task | Status | Commits |
|:-----|:-------|:--------|
| A1 — scaffold (LICENSE, .gitignore, README, CONTRIBUTING) | Done | 777dc47 |
| B1 — PROTOCOL.md payloads extracted from reference | Done | 777dc47 |
| B2 — `Command.swift` + unit tests (12 passing) | Done | e8b7cf8 |
| B3 — `MSIDevice.swift` (IOHIDManager) + tests | Done | e8b7cf8 |
| B4 — MenuBarView, HotKeys, App entry point | Done | e8b7cf8 |
| D1 — macOS CI job in build.yml | Done (windows teammate also added windows job) | 22a79a6 |

**`swift build` / `swift build -c release` clean. `swift test`: 17 tests, 15 passed,
2 skipped (monitor physically connected on dev machine — will run fully in CI), 0 failed.**

**Key decisions:**
- `Command.inputTypeC`/`inputDP` (Phaseowner ref) and `kvmUSBC`/`kvmUpstream` (kdar ref)
  have real 53-byte payloads from PROTOCOL.md — all four are live menu items + hotkeys.
- `pbpOn`, `pbpOff` return `payload = nil` — still UNKNOWN, never invented. Hidden from
  menu + hotkeys until confirmed payloads are added (probe the feature-code pair).
- `MSIDevice.send()` returns `.payloadUnavailable` for nil-payload commands.
- `NSApp.setActivationPolicy(.accessory)` used instead of `Info.plist LSUIElement` —
  SwiftPM executables cannot embed a custom Info.plist.
- Carbon `RegisterEventHotKey` via `InstallEventHandler` (not the C macro
  `InstallApplicationEventHandler` which is unavailable in Swift).
- Device-not-found tests skip automatically when monitor is physically present (XCTSkipIf).

## Windows app — msi-windows (completed this session)

All Track C and D-windows tasks are done:

| Task | Status | Commits |
|:-----|:-------|:--------|
| C1 — project skeleton + Command model | Done | 48ee70d |
| C2 — MsiDevice HidSharp transport | Done | 48ee70d |
| C3 — TrayApp + HotKeys (global hotkeys) | Done | 48ee70d |
| D1 — windows-latest CI job in build.yml | Done | 22a79a6 |

**Key decisions:**
- `CommandKind.InputTypeC` and `CommandKind.InputDp` have real 53-byte payloads,
  byte-identical to macOS (sourced verbatim from `docs/PROTOCOL.md`).
- `PbpOn`, `PbpOff`, `KvmUsbC`, `KvmUpstream` throw `NotImplementedException` —
  payloads are UNKNOWN (see PROTOCOL.md §"What is NOT known"). They appear greyed out
  in the tray menu. **Never invented — Needs-decision for hardware USB capture.**
- HidSharp `stream.Write()` used (Output report, matching PROTOCOL.md report type).
- VID=`0x1462`, PID=`0x3FA4` from PROTOCOL.md.
- Global hotkeys: Ctrl+Alt+{P,O,U,K,T,D} via Win32 `RegisterHotKey`.
- CI: `windows-latest` job uses `dotnet build --configuration Release` + `dotnet test`.

## Tooling — msi-tools (completed 2026-06-22)

Three single-file Swift scripts in `tools/` — no Xcode, no dependencies beyond macOS Swift:

| Tool | Path | Purpose |
|:-----|:-----|:--------|
| `hid-info` | `tools/hid-info/hid-info.swift` | Enumerate HID interfaces; confirm connectivity; verify passive capture is not viable |
| `hid-capture` | `tools/hid-capture/hid-capture.swift` | Input-report listener — expected to capture nothing; run once to verify |
| `hid-probe` | `tools/hid-probe/hid-probe.swift` | **Primary RE tool** — feature/value prober; sweep feature codes, observe monitor |

**Command grammar (kdar/msi-monitor-ctrl, verified against PROTOCOL.md):**
`[01 35 RW 30 30 FEAT_HI FEAT_LO 30 30 30 (30+value) 0d]` padded to 53 bytes.
RW: write=0x62, read=0x38. FEATURE = 2 bytes at indices 5,6. Value = index 10.
Known features: Input=0x35,0x30 ; KVM=0x38,0x3e ; **PBP=UNKNOWN**.
KEY INSIGHT: PBP is another 2-byte FEATURE code, NOT a value-byte variant — sweep the
feature pair (indices 5,6), not the value byte.

**Capture method verdict:**
- Passive `IOHIDManager` listening captures NOTHING for OSD-triggered actions. The MD342CQP
  protocol is output-only (host → monitor). OSD button presses are internal to the firmware.
- **Feature probing via `hid-probe` is the recommended path.** Hold value=1 ("on"), sweep
  the 2-byte feature pair over 0x30–0x3f, watch for PBP turning on.
- Wireshark + USBPcap on Windows remains the alternative if MSI Productivity Intelligence is available.

**Exact command + OSD sequence:**
```bash
swift tools/hid-info/hid-info.swift                                  # confirm device visible
swift tools/hid-probe/hid-probe.swift --feature 0x35 0x30 --value 3 # baseline: Input → Type-C
swift tools/hid-probe/hid-probe.swift                                # menu → "f" (PBP discovery)
# Before the sweep: set PBP OFF via OSD + connect two sources; answer 'y' when picture splits.
```
See `tools/README.md` for full usage, the grammar, and sweep modes.

**Note from device-absent testing:** this dev machine reports a separate VID=0x1462 PID=0x3fa4
device ("MSI Gaming Controller"). The tool correctly matched + opened it and reported a clean
send failure (kIOReturnNotPermitted) — matching/payload logic verified; send succeeds on the real monitor.

## Blockers

- **PBP On/Off payloads** — UNKNOWN. Use `hid-probe` on hardware (sweep the feature-code
  pair at indices [5],[6]; see `tools/README.md`), then fill them into PROTOCOL.md.
- **KVM payloads — KNOWN** (from kdar/msi-monitor-ctrl) but the position→port mapping
  (USB-C=0, Upstream=1) is UNCONFIRMED, and KVM-over-HID-SetReport is unverified. Human
  to confirm on the MD342CQP and flip the mapping if wrong.
- **CI green confirmation** — needs the push to trigger the GitHub Actions `windows-latest`
  job. The human should verify it passes (no real monitor attached in CI, so device-not-found
  tests are the expected pass state).

## Next steps

1. Human: verify CI green on the `windows-latest` job after the 22a79a6 push.
2. Human: smoke-test on the real MD342CQP (Input → Type-C and Input → DP).
3. If PBP/KVM are needed: USB HID capture session → fill payloads in PROTOCOL.md +
   update `Command.cs` (both macOS and Windows).
4. **Phase 2 DONE (commit 6e513f7):** `.github/workflows/release.yml` published.
   Cut first release: `git tag v0.1.0 && git push origin v0.1.0`.

## Decisions (with why)

- **Raw USB HID, not DDC/CI** — reference repo (Phaseowner/MSI-Display-Switch) is HID
  and lists MD342CQP as tested; input switching from it briefly worked on the user's monitor.
- **Monorepo** — keeps the two platforms in sync via a shared PROTOCOL.md.
- **Phase 1 build-only CI, phase 2 = installable releases** to GitHub Releases
  (unsigned, documented).
- **53-byte payload, not padded to 64** — the reference sends `data.count = 53`;
  `IOHIDDeviceSetReport` handles padding. Windows matches this exactly.
- **NotImplementedException for UNKNOWN payloads** — never invent bytes; the tray app
  catches them and shows a diagnostic balloon instead of sending garbage to the monitor.

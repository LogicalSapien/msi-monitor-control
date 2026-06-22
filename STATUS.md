# STATUS — msi-monitor-control

**Created:** 2026-06-22

## Current focus

Phase 1 (Functional MVP) in progress. Two teammates building against
`docs/superpowers/plans/2026-06-22-msi-monitor-control.md`:
- **msi-mac** — Track A (scaffold), Track B (macOS app), `docs/PROTOCOL.md`, D-macos CI.
- **msi-windows** — Track C (Windows app) + Track D windows CI: **COMPLETE** (committed 2026-06-22).

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

## Blockers

- **PBP On/Off and KVM USB-C/Upstream payloads** — UNKNOWN. Require USB HID capture
  on hardware (Wireshark + USBPcap while triggering via MSI Productivity Intelligence).
  See `docs/PROTOCOL.md §Reverse-engineering notes` for the runbook.
- **CI green confirmation** — needs the push to trigger the GitHub Actions `windows-latest`
  job. The human should verify it passes (no real monitor attached in CI, so device-not-found
  tests are the expected pass state).

## Next steps

1. Human: verify CI green on the `windows-latest` job after the 22a79a6 push.
2. Human: smoke-test on the real MD342CQP (Input → Type-C and Input → DP).
3. If PBP/KVM are needed: USB HID capture session → fill payloads in PROTOCOL.md +
   update `Command.cs` (both macOS and Windows).
4. Phase 2: packaging (`.exe` installer / `.dmg`) and GitHub Releases — separate plan.

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

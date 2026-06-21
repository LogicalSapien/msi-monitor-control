# MSI Monitor Control — Design Spec

**Date:** 2026-06-22
**Repo:** `logicalspine/msi-monitor-control` (public, MIT, GitHub org `logicalspine`)
**Status:** Approved design → implementation

## Goal

A lightweight, open-source dual-platform desktop utility to control an **MSI MD342CQP**
monitor by sending **reverse-engineered USB HID commands**. Four actions on each platform:

1. Toggle PBP (Picture-by-Picture) mode on/off
2. Switch KVM: USB-C ↔ Upstream
3. Switch input source: Type-C ↔ DP
4. Global hotkeys for all of the above

**Reference:** [github.com/Phaseowner/MSI-Display-Switch](https://github.com/Phaseowner/MSI-Display-Switch)
— confirmed to use **raw USB HID** (not DDC/CI), written in Swift, and lists **MD342CQP as the
tested model**. The user has confirmed input switching from this reference briefly worked on their
real monitor, so the HID approach is correct.

## Control protocol (confirmed)

Raw USB HID, payloads reverse-engineered. The macOS teammate extracts the exact byte sequences
from the reference repo's Swift source and documents them in `docs/PROTOCOL.md` (see below). Both
apps then send **byte-identical HID reports**.

## Supported monitors

- **Tested:** MSI MD342CQP (the only verified model).
- **May work (unverified, use at own risk):** MS321UP, MD272QP, MD272P, MD272XP, MD272QXP,
  MP275QPDG, MD272UPH — these share the reference repo's "possibly suitable" list. The README
  must state plainly that only MD342CQP is tested and the rest are best-effort.

## Repository layout (monorepo)

```
msi-monitor-control/
├── README.md            # what it is, tested vs may-work models, build/run steps, safety note
├── LICENSE              # MIT, © logicalspine
├── CONTRIBUTING.md      # how to build, where the protocol lives, how to add a model
├── .gitignore           # macOS (.build, *.xcuserdata) + Windows (bin/, obj/) + general
├── docs/
│   └── PROTOCOL.md      # SINGLE SOURCE OF TRUTH: VID/PID, HID usage page/usage, report type,
│                        #   and exact payload bytes for each of the 4 actions. Both apps cite it.
├── macos/               # Swift / SwiftUI menu-bar app
└── windows/             # C# system-tray app (HidSharp)
```

### `docs/PROTOCOL.md` — the keystone

This document is how two independent apps stay in sync. The macOS teammate writes it first
(extracted + verified from the reference repo). The Windows teammate builds against it without
re-reverse-engineering. It must contain, for the MD342CQP:

- USB Vendor ID / Product ID
- HID usage page + usage (or report ID) used for control
- Report type (output report vs feature report) and report length
- The exact byte array sent for each action: PBP on, PBP off, KVM→USB-C, KVM→Upstream,
  Input→Type-C, Input→DP
- Any notes/caveats from reverse engineering

## Components

### macOS app (`/macos`)
- SwiftUI `MenuBarExtra` (menu-bar-only app, no Dock icon — `LSUIElement`).
- **HID transport:** `IOHIDManager` — open device by VID/PID, send output/feature reports.
- **Structure:**
  - `MSIDevice` — find/open the monitor's HID device, send a payload, handle absent device gracefully.
  - `Command` enum — the 4 actions, each mapping to a payload from PROTOCOL.md.
  - `HotKeys` — global hotkeys via Carbon `RegisterEventHotKey` (works without Accessibility prompt)
    or `NSEvent` global monitor; defaults documented in README.
  - `MenuBarView` — SwiftUI menu listing the actions + current device-connected indicator.
- **Build:** Xcode project or SwiftPM (`swift build`); target macOS 13+ (MenuBarExtra requirement).

### Windows app (`/windows`)
- System-tray app using `NotifyIcon` (WinForms host, minimal/headless window).
- **HID transport:** **HidSharp** — enumerate by VID/PID, open, write the identical report bytes.
- **Structure mirrors macOS:**
  - `MsiDevice` — find/open device, send payload, handle absent device.
  - `Command` enum — same 4 actions, same payloads (from PROTOCOL.md).
  - `HotKeys` — global hotkeys via Win32 `RegisterHotKey`.
  - Tray menu listing the actions + connected indicator.
- **Build:** `dotnet build` (.NET 8, `net8.0-windows`).

## Phasing

### Phase 1 — Functional MVP (current)
- Menu-bar (Mac) / system-tray (Windows) app with the 4 actions + global hotkeys.
- Sends real HID payloads to a connected MD342CQP.
- **No** signing/notarisation/installers/auto-update — build-and-run from source.
- Open-source hygiene: README (incl. tested-vs-may-work models + reverse-engineering safety note),
  MIT LICENSE, CONTRIBUTING, `.gitignore`.
- **CI (build-only):** GitHub Actions on push/PR — `macos-latest` builds the Swift app,
  `windows-latest` builds the C# app. Proves both compile. No deploys, no releases yet.

### Phase 2 — Installable releases (after phase 1 verified)
- GitHub Actions (free unlimited minutes on public repos) builds **and packages**:
  - macOS: `.app` zipped and/or `.dmg`.
  - Windows: standalone `.exe` (and/or a simple installer).
- Publishes artifacts to **GitHub Releases** on tag push.
- **Known gap:** apps are **unsigned** (no Apple Developer / Windows code-signing certs in scope),
  so users see Gatekeeper / SmartScreen warnings on first launch. README documents how to bypass
  (right-click → Open on macOS; "More info → Run anyway" on Windows). Signing is a future task.

## Process & rules

- Desktop software → **TEAM_RULES RULE #1 (no direct server changes) is trivially satisfied**:
  there are no servers. All work is edit → commit → push → CI builds on GitHub-hosted runners.
- Each teammate still: acknowledges RULE #1 in its first reply, reads its repo files +
  `~/.claude/TEAM_RULES.md`, **plans first and waits for human approval before coding**.
- **Mandatory diff review on every commit:** `agy` reviews the diff (report-only, no edits).
  **If agy quota is exhausted, fall back to Codex (`codex exec --model gpt-5.5`) for the review.**
  Only merge if the reviewer finds no blocking issues.
- **British English everywhere** (docs, UI copy, identifiers, commits).
- House style: minimal diffs, minimal components, no over-engineering.

## Verification

- **macOS teammate:** extract payloads from reference repo → write `docs/PROTOCOL.md` →
  confirm device enumerates by VID/PID → confirm at least input switching works on the real
  monitor (user runs the physical smoke test; the monitor is on the user's machine).
- **Each app:** builds clean in CI; manual smoke test of all 4 actions against the physical
  MD342CQP (user-run).
- Every commit diff passes agy (or Codex) review before merge.

## Out of scope (phase 1, YAGNI)

Signing/notarisation, installers/releases (→ phase 2), auto-update, multi-monitor selection UI,
config persistence beyond hotkey defaults, and full support/testing for the 7 non-MD342CQP models
(documented as may-work only).

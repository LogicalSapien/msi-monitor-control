# MSI Monitor Control

A dual-platform (macOS + Windows) menu-bar/tray utility that controls MSI monitors
via raw USB HID — no DDC/CI, no proprietary driver. Supports input switching, KVM
switching, PBP/PIP modes, configurable global hotkeys, a quick-launcher palette,
live status, launch-at-login, and a PBP edge-switch KVM feature.

> **Safety note:** HID payloads were obtained by reverse engineering. Use at your
> own risk. Neither the authors nor LogicalSapien accept responsibility for any damage
> caused to hardware or data.

---

## Supported monitors

| Model      | Status                    |
|:-----------|:--------------------------|
| MD342CQP   | Tested ✓                  |
| MS321UP    | May work, unverified — use at your own risk |
| MD272QP    | May work, unverified — use at your own risk |
| MD272P     | May work, unverified — use at your own risk |
| MD272XP    | May work, unverified — use at your own risk |
| MD272QXP   | May work, unverified — use at your own risk |
| MP275QPDG  | May work, unverified — use at your own risk |
| MD272UPH   | May work, unverified — use at your own risk |

---

## Features

### Inputs

Switch between all four inputs: **HDMI 1**, **HDMI 2**, **Type-C**, **DisplayPort**.

### KVM

Switch the USB KVM hub between **USB-C** (the Type-C cable's built-in hub),
**Upstream** (the USB-B port used with DisplayPort cables), and **Auto** (let the
monitor decide). All three are hardware-confirmed on the MD342CQP.

### PBP / PIP modes

Switch between **Off**, **PIP** (picture-in-picture), and **PBP** (picture-by-picture,
side-by-side split screen). PBP sub-window and main-window source selection is
available in Settings (sub-window hardware-confirmed; main-window unverified).

### PBP Edge-Switch KVM *(v0.2.3, macOS)*

When PBP mode is active, the cursor crossing the centre divider automatically
switches the KVM to the source in the target window — Synergy-style, without a manual
hotkey. **Opt-in, off by default.**

- Maps **Type-C → USB-C KVM** and **DisplayPort → Upstream KVM** automatically.
- HDMI sources are not auto-switched (the KVM port pairing is ambiguous).
- Requires the macOS **Input Monitoring** permission (System Settings → Privacy &
  Security → Input Monitoring). The permission is only requested when you enable the
  toggle — never on launch.
- ⚠ Privacy: cursor position is read locally within the process, used only for
  divider detection, and never stored or transmitted.

### Configurable hotkeys + presets

All actions have rebindable global hotkeys. Three named presets:

| Preset | macOS | Windows |
|:-------|:------|:--------|
| Default (`cmdShiftCtrl`) | ⌃⇧⌘ | Ctrl+Alt+Shift |
| `ctrlShift` | ⌃⇧ | Ctrl+Shift |
| `legacy` | ⌃⌥⌘ | Ctrl+Alt |

Per-action chords can be added, removed, or changed from the Settings window without
restarting the app (live re-registration).

### Quick Launcher *(⌃⇧⌘ Space)*

A floating palette showing all actions in one place. Open with the default chord
`⌃⇧⌘ Space` (rebindable) or from the menu bar. Tab/Space/Enter to navigate;
Esc to dismiss.

### Live status

The last action sent per group (Input / KVM / Mode) is highlighted in the menu bar
and Settings. Best-effort: changes made via the monitor's OSD buttons are not
reflected (the monitor sends no state readback over HID).

### Launch at login

Toggle in Settings. Uses `SMAppService` on macOS and the HKCU Run key on Windows.

### Debug logging

A rolling log at `~/Library/Application Support/LogicalSapien/MSIMonitorControl/debug.log`
(macOS) / `%APPDATA%\LogicalSapien\MSIMonitorControl\debug.log` (Windows), size-capped
at ~1 MB. Covers hotkey fires, HID sends, device connect/disconnect, settings changes,
and crash/signal events. Reveal from the menu bar: **Reveal Debug Log…**

---

## macOS

**Requirements:** macOS 13 or later, Xcode command-line tools.

#### Run from source

```bash
cd macos
swift build
.build/debug/MSIControlApp
```

#### Build a double-clickable .app bundle

```bash
cd macos
./build-app.sh
open build/MSIMonitorControl.app
```

The app is a menu-bar-only utility (no Dock icon). It is **unsigned**, so on first
launch Gatekeeper may warn that it is from an unidentified developer.

**Recommended first-launch fix (strips the download quarantine):**

```bash
xattr -dr com.apple.quarantine /Applications/MSIMonitorControl.app
open /Applications/MSIMonitorControl.app
```

Alternatively, **right-click → Open → Open** usually works too.

### Default hotkeys (macOS — ⌃⇧⌘ preset)

| Action | Hotkey |
|:-------|:-------|
| Input → HDMI 1 | ⌃⇧⌘H |
| Input → HDMI 2 | ⌃⇧⌘J |
| Input → Type-C | ⌃⇧⌘C |
| Input → DisplayPort | ⌃⇧⌘D |
| KVM → USB-C | ⌃⇧⌘K |
| KVM → Upstream | ⌃⇧⌘U |
| KVM → Auto | ⌃⇧⌘A |
| PBP/PIP → Off | ⌃⇧⌘O |
| PBP/PIP → PIP | ⌃⇧⌘I |
| PBP/PIP → PBP | ⌃⇧⌘P |
| Quick Launcher | ⌃⇧⌘ Space |

All hotkeys are rebindable in Settings.

---

## Windows

**Requirements:** .NET 8 SDK.

```powershell
cd windows
dotnet build
dotnet run --project MsiMonitorControl
```

**First launch — SmartScreen:** the executable is **unsigned**. Windows may show
"Windows protected your PC". Click **More info → Run anyway**.

### Default hotkeys (Windows — Ctrl+Alt+Shift preset)

| Action | Hotkey |
|:-------|:-------|
| Input → HDMI 1 | Ctrl+Alt+Shift+H |
| Input → HDMI 2 | Ctrl+Alt+Shift+J |
| Input → Type-C | Ctrl+Alt+Shift+C |
| Input → DisplayPort | Ctrl+Alt+Shift+D |
| KVM → USB-C | Ctrl+Alt+Shift+K |
| KVM → Upstream | Ctrl+Alt+Shift+U |
| KVM → Auto | Ctrl+Alt+Shift+A |
| PBP/PIP → Off | Ctrl+Alt+Shift+O |
| PBP/PIP → PIP | Ctrl+Alt+Shift+I |
| PBP/PIP → PBP | Ctrl+Alt+Shift+P |
| Quick Launcher | Ctrl+Alt+Shift+Space |

---

## Releases / Installation

Pre-built binaries are published on the [GitHub Releases](../../releases) page for
every version tag. No build tools required — just download and run.

### macOS

1. Download `MSIMonitorControl-macOS.dmg` (or the `.zip`).
2. Open the `.dmg` and drag `MSIMonitorControl.app` to your Applications folder.
3. **Clear the download quarantine** (see first-launch notes above).

### Windows

1. Download `MsiMonitorControl-Windows-x64.zip` and extract it.
2. Run `MsiMonitorControl.exe` — self-contained (no .NET runtime needed).
3. **SmartScreen:** click **More info → Run anyway** on first launch.

> These apps are unsigned because obtaining code-signing certificates is a Phase 2
> goal. The source code is public and MIT-licensed — build from source if you prefer
> not to run unsigned binaries.

---

## Protocol

HID payloads are documented in [`docs/PROTOCOL.md`](docs/PROTOCOL.md). Both
platforms send byte-identical reports sourced from that file.

---

## Credits

Protocol reverse-engineered from
[Phaseowner/MSI-Display-Switch](https://github.com/Phaseowner/MSI-Display-Switch)
(MIT licence).

---

## Licence

MIT © LogicalSapien — see [LICENSE](LICENSE).

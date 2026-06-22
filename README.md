# MSI Monitor Control

A dual-platform (macOS + Windows) menu-bar/tray utility that controls MSI monitors
via raw USB HID — no DDC/CI, no proprietary driver. Supports PBP toggle, KVM switch,
and input switching with global hotkeys.

> **Safety note:** HID payloads were obtained by reverse engineering. Use at your
> own risk. Neither the authors nor logicalspine accept responsibility for any damage
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

The app is a menu-bar-only utility (no Dock icon). It is **unsigned** in Phase 1,
so on first launch Gatekeeper may warn that it is from an unidentified developer —
right-click the `.app` and choose **Open** to allow it (you only need to do this once).

### Default hotkeys

| Action           | Hotkey           |
|:-----------------|:-----------------|
| Input → Type-C   | ⌃⌥⌘C            |
| Input → DP       | ⌃⌥⌘D            |
| KVM → USB-C      | ⌃⌥⌘K            |
| KVM → Upstream   | ⌃⌥⌘U            |
| PBP On           | ⌃⌥⌘P            |
| PBP Off          | ⌃⌥⌘O            |

---

## Windows

**Requirements:** .NET 8 SDK.

```powershell
cd windows
dotnet build
dotnet run --project MsiMonitorControl
```

### Default hotkeys

| Action           | Hotkey           |
|:-----------------|:-----------------|
| Input → Type-C   | Ctrl+Alt+Win+C   |
| Input → DP       | Ctrl+Alt+Win+D   |
| KVM → USB-C      | Ctrl+Alt+Win+K   |
| KVM → Upstream   | Ctrl+Alt+Win+U   |
| PBP On           | Ctrl+Alt+Win+P   |
| PBP Off          | Ctrl+Alt+Win+O   |

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

MIT © logicalspine — see [LICENSE](LICENSE).

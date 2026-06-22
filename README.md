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

## Releases / Installation

Pre-built binaries are published on the [GitHub Releases](../../releases) page for
every version tag. No build tools required — just download and run.

### macOS

1. Download `MSIMonitorControl-macOS.dmg` (or the `.zip`).
2. Open the `.dmg` and drag `MSIMonitorControl.app` to your Applications folder
   (or anywhere you like).
3. **First launch — clear the download quarantine (recommended).** The app is
   **unsigned** (no Apple Developer certificate) and arrives with macOS's
   download-quarantine flag. macOS may show **"MSIMonitorControl is damaged and
   can't be opened"** or block it via Gatekeeper. The reliable fix is to strip the
   quarantine flag in Terminal, then open the app:
   ```
   xattr -dr com.apple.quarantine /Applications/MSIMonitorControl.app
   open /Applications/MSIMonitorControl.app
   ```
   (Adjust the path if you put the app elsewhere.) This is **safe**: the app is
   open-source and MIT-licensed — you can read every line in this repository. The
   "damaged" message does not mean the file is corrupt; it is macOS refusing to
   run a quarantined, unsigned app, and `xattr` simply removes that quarantine.
   (`-r` recurses into the bundle; it is technically redundant when the quarantine
   flag is only on the `.app` root, but it is harmless and a useful safety net.)

   The app *is* ad-hoc signed, so on many setups you can instead just
   **right-click** the `.app` → **Open** → **Open**. If that still reports
   "damaged", use the `xattr` command above — it always works.

### Windows

1. Download `MsiMonitorControl-Windows-x64.zip` and extract it.
2. Run `MsiMonitorControl.exe` — it is **self-contained** (no .NET runtime install
   required).
3. **First launch — SmartScreen:** the executable is **unsigned**. Windows may show
   "Windows protected your PC". Click **More info → Run anyway**.

> These apps are unsigned because obtaining code-signing certificates is a Phase 2
> goal. The source code is public and MIT-licensed — you can build from source
> (see the macOS / Windows sections above) if you prefer not to run unsigned binaries.

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

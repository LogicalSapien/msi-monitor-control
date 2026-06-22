# Contributing

Thank you for your interest in msi-monitor-control. This project is open-source
(MIT) and welcomes contributions for additional monitor models, bug fixes, and
new actions.

---

## Building

### macOS

```bash
cd macos
swift build       # build
swift test        # run tests
.build/debug/MSIControlApp   # run the menu-bar app
```

Requires: macOS 13+, Xcode command-line tools.

### Windows

```powershell
cd windows
dotnet build                             # build
dotnet test                              # run tests
dotnet run --project MsiMonitorControl   # run the tray app
```

Requires: .NET 8 SDK.

---

## HID protocol (`docs/PROTOCOL.md`)

`docs/PROTOCOL.md` is the **single source of truth** for all HID payloads. Both
the macOS and Windows apps send byte-identical reports sourced from this file.

- Never invent payload bytes. Only document bytes that have been confirmed via
  reverse engineering or hardware testing.
- If a payload is unknown, mark it `UNKNOWN — needs hardware reverse-engineering`
  in the table and open an issue.
- Both `Command.swift` (macOS) and `Command.cs` (Windows) must stay in sync with
  `PROTOCOL.md`.

---

## Adding support for a new monitor model

1. Obtain the USB Vendor ID and Product ID for the model (e.g. via `system_profiler
   SPUSBDataType` on macOS or Device Manager on Windows).
2. Capture HID traffic (Wireshark + USBPcap on Windows, or HID Explorer on macOS)
   while sending commands via the official MSI Productivity Intelligence software.
3. Document the VID/PID and payload bytes in `docs/PROTOCOL.md` under a new section
   for that model.
4. Update the `Command` implementations to handle the new device's payloads if
   they differ from the MD342CQP.
5. Update the **Supported monitors** table in `README.md` with the model and
   tested/unverified status.

---

## Style

- **British English** everywhere: docs, UI copy, code identifiers, commit messages
  (e.g. "colour", "behaviour", "initialise").
- Minimal diffs — prefer targeted changes over large rewrites.
- Commit messages: imperative voice, concise subject line.
- MIT licence applies to all contributions.

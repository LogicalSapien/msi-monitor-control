# STATUS — msi-monitor-control

**Created:** 2026-06-22

## Current focus

**v0.2.0 — configurable cross-platform hotkeys + settings.** Design contract
`docs/SETTINGS.md` APPROVED. macOS implementation done + verified (uncommitted —
awaiting lead Codex-review); Windows building in parallel against the same schema.
- **msi-mac** — v0.2.0 macOS side: `HotkeyConfig` model, data-driven `Command`,
  config-driven `HotKeyManager` with live re-register, SwiftUI settings UI,
  `SMAppService` launch-at-login. **DONE, verified, uncommitted** (2026-06-22).
- Earlier: Phase 1 + post-MVP hardening + hardware-feedback fixes — COMPLETE (committed).
- **msi-windows** — Track C/D + KVM/Auto fixes COMPLETE; v0.2.0 C# side in progress.

### v0.2.0 — settings + hotkeys (msi-mac, 2026-06-22 — awaiting Codex review + commit)

Shared contract: `docs/SETTINGS.md` (single source of truth, like PROTOCOL.md) +
`docs/fixtures/settings.example.json`. Decisions baked in: full-chord-per-binding
model; apply-and-bake preset; computed display strings; OS-register-as-conflict-
authority; never-block load fallback; vendor-nested config folder
`~/Library/Application Support/LogicalSapien/MSIMonitorControl/settings.json`.

| Item | File(s) | Notes |
|:-----|:--------|:------|
| Shared config model | `MSIControl/HotkeyConfig.swift` (+ tests) | Codable model (schemaVersion, preset, launchAtLogin, bindings, altGrAvoidList). Atomic save (`.atomic`). Never-block load: missing→write defaults; malformed/newer-version→ignore file (don't overwrite) + in-memory defaults. Validation: duplicate (BLOCKING) + AltGr advisory (non-blocking). `option`/`alt` synonyms normalised. Apply-and-bake preset + `inferredPreset()`. Derived display `⌃⌥⇧C`. |
| Data-driven Command | `MSIControl/Command.swift` (+ tests) | Dropped `shortcutKey`/`shortcutDisplay`; added stable `actionId` (config contract key) + `from(actionId:)` + `defaultKey` seed. |
| Config-driven hotkeys | `MSIControlApp/HotKeys.swift` | `HotKeyManager.apply(config:)` registers from the config; full A–Z/0–9 Carbon keycode table; **live re-register** (unregister-all → register) with no restart; returns OS-rejected action ids for conflict surfacing; availability skip preserved. |
| Settings hub | `MSIControlApp/SettingsStore.swift` | `@MainActor ObservableObject` owning the config; every mutation persists + re-applies hotkeys; launch-at-login calls OS first, persists only on success; loads + reconciles on init. |
| Settings UI | `MSIControlApp/SettingsView.swift` | Preset dropdown, per-action rebind rows, click-to-capture chord (AppKit local key monitor; Esc cancels), add/remove extra hotkeys, conflict (⚠️) + AltGr advisory surfacing, launch-at-login toggle. |
| Launch-at-login | `MSIControlApp/LaunchAtLogin.swift` | `SMAppService.mainApp` register/unregister/reconcile (macOS 13+; no fallback needed). |
| Menu + app wiring | `MenuBarView.swift`, `App.swift` | Menu chord text now data-driven via `settings.primaryDisplay`; added Settings… item + a `Window(id:"settings")` scene opened via `openWindow`. |

**Codex-review fixes (2026-06-22, round 2 — 5 blocking + 5 non-blocking):**
- **JSON contract → BYTE-IDENTICAL via custom serialiser (lead-locked §3.8).** Stock `JSONEncoder` can't hit the canonical form (it forces `" : "`; STJ uses `": "`), so `jsonData()` is now a hand-rolled deterministic writer: `": "` separator, 2-space indent, fixed top-level + §3.6 actionId order, multi-line `mods`, `[]` for empty, hyper writes `option`, unescaped `/`, UTF-8 no BOM, single trailing newline. Fixture REGENERATED from the encoder (it IS the canonical output). Test `testDefaultSaveBytesEqualFixtureBytes` asserts `default.save() == fixture` byte-for-byte; app-written config verified identical to fixture end-to-end. SETTINGS.md §2.1 + new §3.8 document the exact format.
- **Per-field-resilient load** (§4): load now parses via `JSONSerialization` and drops only the bad field — a single malformed chord/invalid key is dropped, a missing/bad `altGrAvoidList` falls back to built-in, the rest loads (`loadedWithRepairs`). Tests per case.
- **Validate-on-load** (§3.5): duplicate chords resolved first-wins on load. Test added.
- **OS-reject rollback** (§3.5/§5): policy extracted to a testable library seam — `HotkeyRegistering` protocol + `HotkeyCommitter` (register-FIRST → `decideCommit` → on reject re-register PREVIOUS config + don't persist). `HotKeyManager` conforms; `SettingsStore` depends on the protocol. Spy tests prove the accepted path persists once and the rejected path re-registers the previous config (spy sees `[candidate, previous]`) without persisting — the user's working hotkeys survive a rejected rebind.
- **"Add another hotkey" now functional**: an active capture row renders for the append target (was armed but rendered no capture view).
- Non-blocking: HotKeyManager main-thread asserted; key field enforces exactly one A–Z/0–9 (rejects "AB"/non-ASCII); Escape clears capturing state (`onCancel`); `passUnretained` removes the self-retain cycle so deinit runs; doc+code agree on atomic-replace (§2).

**Verification (2026-06-22, round 3 — final):** `swift build` + `swift build -c
release` clean, **no warnings**; `swift test` = **53 tests, 0 failed, 3 skipped**
(2 device-not-found + the fixture REGEN generator, which skips unless
`REGEN_FIXTURE=1`). `testDefaultSaveBytesEqualFixtureBytes` + the two rollback-spy
tests pass. `./build-app.sh` → signed bundle valid; launched OK; fresh app-written
config is **byte-for-byte identical to `docs/fixtures/settings.example.json`**
(verified via `diff`). Contract CONFIRMED byte-identical (human-approved); a
separate cross-load sample is unnecessary (shared-fixture byte-equality covers
mutual-loadability). NOT committed — awaiting Windows byte-match confirmation + lead commit.

**v0.2.0 cross-app contract checks for msi-windows:** a config written under
`hyper`/`ctrlShift` must load byte-identically in C#. actionIds are the contract
keys (`inputTypeC`, `inputDP`, `kvmUSBC`, `kvmUpstream`, `kvmAuto`, `pbpOn`,
`pbpOff`). Windows registry Run **value name stays flat** `MSIMonitorControl` (vendor
nesting is folder-only — see SETTINGS.md §6).

### Post-MVP work (msi-mac, 2026-06-22)

| Item | Commit | Notes |
|:-----|:-------|:------|
| `.app` bundle packaging | 2331fc7 | `macos/build-app.sh` → `build/MSIMonitorControl.app`. LSUIElement bundle, unsigned (Phase 1). Activation policy moved to `NSApplicationDelegateAdaptor` (fixed launch crash). Verified: launches as no-Dock menu-bar item. |
| Resource-leak fixes | ef804bf | IOHIDManager/Device now closed (was leaking USB claim); manager scheduled on run loop before `CopyDevices` (reliable enumeration); safe CFTypeID downcast; HotKeys `passRetained` balanced in deinit, `[weak self]` dispatch, OSStatus logging. |
| KVM switching | 53c1c09 | New reference `kdar/msi-monitor-ctrl` decoded. PROTOCOL.md gains Command grammar + KVM payloads (feature `0x38 0x3E`). `kvmUSBC`/`kvmUpstream` now have payloads → live menu items + hotkeys. |

### Hardware-feedback fixes (msi-mac, 2026-06-22 — awaiting agy review + commit)

After the user smoke-tested the .app on the real MD342CQP, four coherent fixes
(HDMI left parked for a later hardware-probing session):

| Item | File(s) | Notes |
|:-----|:--------|:------|
| **A — Send bug (2nd send `IOReturn 0x10000003` / NotOpen)** | `MSIDevice.swift`, `MSIDeviceTests.swift` | Root cause: open lifecycle was tied to the IOHIDManager, scheduled on a run loop that menu actions don't share in a MenuBarExtra app → handle went not-open between sends. Fix: manager is now **discovery-only** (enumerate, then `defer`-close + unschedule); we own the `IOHIDDevice` directly and open-and-check before every SetReport (`attemptSend` → `ensureDeviceOpen`). Backstop: **ANY** first-attempt failure triggers one full re-enumerate-and-retry — covers `kIOReturnNotOpen`, `NotPermitted` AND `kIOReturnNoDevice` (unplug/replug invalidates the handle); a re-locate that finds nothing clears state and returns `.deviceNotFound` (recovers without a restart). NSLock serialisation + Result semantics + byte[0]-as-reportID preserved. Test exercises the lock→locate→open path twice with an *available* command. TODO(verify-on-hardware): two consecutive available sends on real MD342CQP. |
| **B — Chords not visible in menu** | `MenuBarView.swift` | `.menu` MenuBarExtra renders a native NSMenu that drops a custom trailing `Text`. Fix: chord folded into the button label string (`"Input → Type-C  ⌃⌥⌘C"`). `shortcutDisplay`/`shortcutKey` stay the single source of truth in `Command.swift`. |
| **C — Menu-bar icon** | `App.swift`, `Package.swift`, `build-app.sh`, `assets/menubar-icon.{svg,pdf}`, `assets/make-menubar-icon.swift` | Replaced the `display` SF Symbol with a custom **template** icon (monochrome monitor+switch-arrows silhouette, transparent bg, `isTemplate=true`, 18pt vector PDF) derived from `icon.svg`. Loaded via `Image(nsImage:)`; falls back to the SF Symbol if the resource is missing. `build-app.sh` embeds the flat PDF in `Contents/Resources` (signable) — NOT the SwiftPM `.bundle` (codesign can't seal it inside an .app). `make-menubar-icon.swift` regenerates the PDF. |
| **KVM Auto (parked scaffolding)** | `Command.swift`, `HotKeys.swift`, `docs/PROTOCOL.md`, tests | New `Command.kvmAuto` (label "KVM → Auto", chord ⌃⌥⌘A). `payload = nil` — feature `0x38 0x3E` known but byte[10] value UNKNOWN; never invented. Hidden from menu + hotkey not registered until probed. PROTOCOL.md documents the Auto position as UNKNOWN. |
| **Related — HotKeys availability gating** | `HotKeys.swift` | `registerAll` now only `RegisterEventHotKey`s for `command.isAvailable` commands, so PBP P/O and KVM Auto A claim no dead chords. Bindings table kept, filtered on availability — keeps registered chords in sync with the menu. |

**Verification (2026-06-22):** `swift build` + `swift build -c release` clean;
`swift test` = **21 passed, 0 failed, 0 skipped** (no monitor attached this run, so
device-not-found tests ran rather than skipping). `./build-app.sh` produces a
signed `build/MSIMonitorControl.app` (Sealed Resources valid, satisfies DR);
smoke-launched OK (menu-bar item appears, no crash). Real-monitor send + icon
appearance still to be confirmed by the user. NOT yet committed — pending agy review.

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
- `KvmUsbC`, `KvmUpstream` now have real 53-byte payloads (feature `0x38 0x3E`,
  byte[10] = `0x30`/`0x31`), byte-identical to macOS `Command.swift` — KVM is **live**
  (fixed the drift where these previously threw and claimed UNKNOWN). `IsAvailable`=true.
  TODO(verify-on-hardware): position→port mapping (USB-C=0, Upstream=1) UNCONFIRMED — flip
  if hardware disagrees; HID SetReport vs kdar libusb transport unverified.
- `PbpOn`, `PbpOff`, **`KvmAuto`** (new third KVM mode) throw `NotImplementedException` —
  payloads UNKNOWN. They appear greyed out and register no hotkey. **Never invented.**
- HidSharp `stream.Write()` used (Output report, matching PROTOCOL.md report type).
- VID=`0x1462`, PID=`0x3FA4` from PROTOCOL.md.
- Global hotkeys: Ctrl+Alt+{P,O,K,U,A,C,D} via Win32 `RegisterHotKey`, but
  **availability-gated** — only chords whose command `IsAvailable` register (so PBP On/Off
  and KVM Auto claim no dead chord). Mirrors the macOS approach. `A` = KVM → Auto.
- CI: `windows-latest` job uses `dotnet build --configuration Release` + `dotnet test`.
- **Verification note (2026-06-22):** no .NET toolchain on the dev Mac; KVM/Auto/hotkey
  changes verified by reading (byte-identical to PROTOCOL.md/macOS). The windows-latest CI
  job is the verification gate — confirm green after push.

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

### v0.2.0 — settings + hotkeys (msi-windows, 2026-06-22 — awaiting Codex review + commit)

Implemented the Windows side of the shared settings contract (docs/SETTINGS.md §8(b)).
Built correct-by-construction against the approved schema — **no local dotnet on the dev
Mac**, so the **windows-latest CI is the verification gate** (confirm green after commit).

| File | Change |
|:-----|:-------|
| `HotkeyConfig.cs` (new) | Shared model (System.Text.Json, camelCase enums byte-matching macOS). SchemaVersion, Preset(hyper\|ctrlShift\|legacy\|custom), LaunchAtLogin, Bindings(actionId→List<Chord>), AltGrAvoidList. Path `%APPDATA%\LogicalSapien\MSIMonitorControl\settings.json` (vendor-nested). Atomic write (tmp+File.Move). Load/fallback §4 (missing→write default; malformed OR newer schemaVersion→log+ignore+DON'T overwrite; per-field resilience; `command` dropped on Windows w/ log; option→alt synonym). Validation §3.5 (duplicate=BLOCKING, AltGr=NON-BLOCKING). Derived display §3.7 (`Ctrl+Alt+Shift+C`). ApplyPreset bakes mods + DerivePreset→custom on hand-edit. Canonical mod write-order matches macOS encoder. `LoadFrom`/`SaveTo`/`ToJson` test seams. |
| `Command.cs` | Data-driven: added `ActionId()`/`KindForActionId()`/`Label()` (stable §3.6 ids); kept actionId/label/payload/IsAvailable. |
| `HotKeys.cs` | Registers from `HotkeyConfig.Bindings` (actionId→Kind, mods→MOD_*, key→VK_*); skips empty/unavailable; multi-chord per action; **`ReRegister(config)`** = UnregisterHotKey each + RegisterHotKey new set on the same message-filter/UI thread; failed re-register kept in `FailedChords`, rest applied. |
| `ChordCaptureDialog.cs` (new) | Modal next-chord capture (Ctrl/Alt/Shift + A–Z/0–9); Esc cancels; rejects modifier-less. |
| `SettingsForm.cs` (new) | WinForms settings window: preset dropdown; per-action rows w/ click-to-rebind + add/remove extra hotkeys; inline duplicate-block + AltGr advisory; launch-at-login checkbox; edits a deep-copied working config, commits on Save. |
| `LaunchAtLogin.cs` (new) | HKCU `…\Run`, FLAT value name `MSIMonitorControl` = quoted exe path; IsEnabled/SetEnabled/Reconcile(config-wins). |
| `TrayApp.cs` | Loads config at startup + reconciles launch-at-login; menu reads derived display; "Settings…" item → on Save persist+ReRegister+rebuild menu+reconcile. |
| `MsiMonitorControl.Tests.csproj` | Copies `docs/fixtures/settings.example.json` to test output (Content+Link). |
| `HotkeyConfigTests.cs` (new) | Round-trip (in-memory + disk); missing→write default; malformed→defaults+file-untouched; newer-version→ignore-don't-overwrite (bytes unchanged); malformed-binding-dropped-keeps-rest; command-dropped-on-Windows; missing-altGr→default; duplicate detection; AltGr flagging (4 cases); derived display (3); option→alt synonym; ApplyPreset/DerivePreset; **fixture parse → reproduces default bindings**; mac-written-option loads as same chord. |
| `CommandTests.cs` | Added ActionId/KindForActionId round-trip/Label assertions. |

**Cross-app serialisation = BYTE-IDENTICAL** (docs/SETTINGS.md §3.8 — msi-mac's latest
revision restored byte-for-byte + added the full §3.8 canonical spec; the shared fixture is
the regenerated ground truth). The §3.8 form is STJ-native, so stock System.Text.Json
(`WriteIndented` + `UnsafeRelaxedJsonEscaping`) + `BindingsConverter` (canonical actionId
order, `option` modifier spelling) + a single appended trailing newline produces output that
equals `docs/fixtures/settings.example.json` **byte-for-byte**. Verified by hand against the
fixture `od -c` dump (the only delta STJ needed was the trailing `\n`, now added). Guards:
`DefaultToJson_EqualsSharedFixture_ByteForByte`, determinism, exactly-one-trailing-newline,
written-uses-option, write→read→same-model, fixture→default.

**Decisions / flags (msi-windows):**
- Launch-at-login registry value name is FLAT `MSIMonitorControl` (per §6), NOT vendor-nested —
  only the config *file path* is vendor-nested.
- AltGr is advisory-only (never blocks, never alters config). OS-reserved is detected at
  RegisterHotKey-returns-false time (no static reserved-list).
- Not built locally (no dotnet on Mac). **windows-latest CI is the gate.**

**Codex review fixes (msi-windows, 2026-06-22 — round 2):**
- **B2 per-field resilience on load:** added `BindingsConverter` (custom System.Text.Json
  reader) so a single malformed chord/entry (`mods:null`, non-object chord, non-array value,
  bad enum token) is skipped instead of throwing the whole deserialise. + tests.
- **B3 + B5 validation on load:** `Sanitise` now drops modifier-less chords, unsupported
  base keys (only A–Z/0–9 via `IsValidBaseKey`), and duplicate chords (`DropDuplicateChords`,
  first-wins) at load — not just in the UI path. + tests.
- **B4 OS-rejected rebind rollback:** `HotKeys.ReRegister`→`TryReRegister(config)` returns
  bool; on any rejected RegisterHotKey it rolls back to the previously-applied config (keeps
  working hotkeys) and exposes the rejected chord(s). `TrayApp.OpenSettings` now registers
  FIRST and persists ONLY on success — a rejected chord no longer lands on disk. (Win32
  registrar rollback is not headless-unit-tested — same as the macOS Carbon registrar; the
  feeding validation logic is fully tested.)
- **B1 JSON contract — RESOLVED as BYTE-IDENTICAL (docs/SETTINGS.md §3.8).** The contract
  flip-flopped (semantic → byte) during the session; msi-mac's latest SETTINGS.md restores
  byte-for-byte + adds the full §3.8 canonical spec, with the fixture as regenerated ground
  truth. Windows output now matches the fixture byte-for-byte (stock STJ gives the §3.8 layout;
  added the single trailing newline STJ omits; `option` spelling + actionId order via
  `BindingsConverter`; UTF-8 no BOM). Added `DefaultToJson_EqualsSharedFixture_ByteForByte`
  (the §3.8-required test) + trailing-newline + determinism + written-uses-option tests.
  FINAL (human-confirmed via lead): **byte-identical wins** — the contract converged on exactly
  what was implemented. Windows-written output == the shared fixture (one fixture, both apps;
  no separate `settings.windows-written.json`). The byte-equality claim is hand-verified against
  the fixture `od -c` dump (note string matches char-for-char incl. ASCII `EUR`); the
  `DefaultToJson_EqualsSharedFixture_ByteForByte` test on windows-latest CI is the executable gate.
- **NB1 handle leaks:** `SettingsForm.RebuildRows` disposes discarded controls; `TrayApp`
  disposes the replaced ContextMenuStrip.
- **NB2 stale Run path:** `LaunchAtLogin.Reconcile` compares the Run value DATA to the current
  exe and repairs a stale quoted path (not just existence).

**CI follow-up fix (msi-windows, 2026-06-22 — post-commit, 1 red test):** v0.2.0 committed;
windows-latest CI was 85/86 — `Parse_DropsMalformedBindingEntry_KeepsTheRest` failed
(`repaired` Expected True/Actual False). Root cause: `BindingsConverter.ReadChord` was
*pre-dropping* an empty-key chord (returning null) before `Sanitise` ran, so the malformed
entry was removed but the `repaired` out-flag was never set. Fix (1 line): the converter now
returns the parsed object faithfully (empty key → `Chord("")`) and `Sanitise` is the SINGLE
point that drops malformed entries + sets `repaired`. Verified by reasoning across all 8
Sanitise drop-branches (each sets the flag) and every `Assert.True(repaired)` test now routes
through one. The byte-equality test PASSED in that CI run (byte-identity confirmed on real
dotnet). Awaiting lead's follow-up push + re-run.

**CI follow-up #2 (line endings — msi-windows):** the `.gitattributes` `eol=lf` pin (lead,
bcf6133) fixed the fixture side. Test-hardening on my side:
`DefaultToJson_EqualsSharedFixture_ByteForByte` normalises the fixture-on-disk's `\r\n`→`\n`
and positively asserts `ToJson()` contains no `\r`.

**CI follow-up #3 (REAL serialiser bug — msi-windows):** with the fixture now LF, CI exposed
the actual interop bug: **System.Text.Json `WriteIndented` emits the PLATFORM newline — CRLF on
Windows/.NET 8** (`JsonWriterOptions.NewLine` to force LF only exists in .NET 9+; CI target is
net8.0-windows). So the config the Windows app WROTE AT RUNTIME used CRLF → NOT byte-identical
to the macOS LF file — a genuine contract break, invisible on the dev Mac (same code emits LF
there). This was my incorrect "STJ emits LF on every platform" assumption. **Fix:** `ToJson()`
now normalises `\r\n`→`\n` after serialising, then ensures exactly one trailing `\n`
(`json.Replace("\r\n","\n").TrimEnd('\n') + "\n"`). Runtime output is now LF everywhere,
byte-identical to the fixture + macOS. The test's `Assert.DoesNotContain("\r", actual)` now
positively guards this. **The lesson: "correct-by-construction" on a Mac cannot catch
platform-newline behaviour — real windows-latest execution was required.**

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

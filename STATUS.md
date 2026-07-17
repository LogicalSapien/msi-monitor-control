# STATUS — msi-monitor-control

**Created:** 2026-06-22

## Current focus

**v0.2.6 — Windows report-ID framing fix (AWAITING HARDWARE VERIFICATION).**
Field debugging on 2026-07-17 (user's Windows work laptop + real MD342CQP)
showed every send logging `OK` while the monitor ignored the command. Root
cause: Windows' HID stack consumes `buffer[0]` as the report ID and delivers
only the REMAINING bytes as report data, so the 53-byte PROTOCOL.md frame
arrived shifted one byte left (`35 62 …` instead of `01 35 …`). macOS
(`IOHIDDeviceSetReport`) delivers the buffer verbatim — which is why the same
payload works there. Fix: `MsiDevice.ToWireReport` prepends the report-ID byte
(`0x01`) so the full frame survives as data ([MSI-6]). PROTOCOL.md's old
"report-ID double-count" open question is now RESOLVED (it had the direction
backwards). Also stamped `<Version>` in the csproj so debug.log identifies the
build (was logging the .NET default `1.0.0.0`). **User must re-test input
switching from Windows with the v0.2.6 build** — the PnP enumeration during
debugging confirmed a single HID collection, so device selection was ruled out.

Before this: **all of v0.2.0 → v0.2.5 is committed, tagged, and released**
(v0.2.5 = MSI-5 CmdShiftCtrl re-bake fixes, released 2026-06-29), each with
green `release.yml` runs and all three assets published
(`MSIMonitorControl-macOS.dmg`, `MSIMonitorControl-macOS.zip`,
`MsiMonitorControl-Windows-x64.zip`).

### Pending — hardware-dependent (cannot be closed without the real MD342CQP)

These are the only open items. None block a release; all need the physical monitor:

1. **KVM smoke-test + position→port mapping confirmation.** The KVM byte→port
   mapping was probed and corrected in v0.2.1 (Auto `0x30`, Upstream `0x31`,
   USB-C `0x32` — see `docs/PROTOCOL.md`), but a full smoke-test of `kvmUpstream`
   (`U`) / `kvmUSBC` (`K`) on real hardware should confirm the mapping end-to-end
   and that HID SetReport switches reliably from the app (not just the probe tool).
2. **Guided PBP main-window source probe — feature `0x36 0x32`.** Still ASSUMED,
   not hardware-verified (flagged unverified in both apps' UI + PROTOCOL.md). The
   user couldn't probe it safely because the KVM/USB-C control connection sits on
   the main window. Verify when safe and update `docs/PROTOCOL.md`.
3. **v0.1.2 hardening polish.** Remaining low-priority robustness clean-ups
   carried forward (e.g. the report-ID double-count question in PROTOCOL.md
   "Open question", confirmable only via a USB HID capture on hardware).

### Shipped history

**v0.2.4 — hotfix: stale re-detect + silent-fail send (Windows).** SHIPPED
(commit `d07a1c7`, tag `v0.2.4`, release CI green):
- `MsiDevice.cs`: `ConnectionChanged` event fires when state changes; `Refresh()` now
  fires it; `Send`/`SetPbpSource` re-enumerate if `_device is null` before giving up;
  `WriteReport` split into `TryWrite` + retry-on-failure (reopen-and-retry, mirrors macOS
  reopen-on-stale-handle). `TryWrite` logs exception on EVERY failure (no silent swallow).
- `TrayApp.cs`: 5-second `System.Windows.Forms.Timer` calls `_device.Refresh()` on the UI
  thread; `ConnectionChanged` handler rebuilds the menu live (items un-grey on reconnect);
  `MakeItem` gates monitor commands on `_device.IsConnected` (disconnected → grey).
- All existing `MsiDeviceTests` still pass (no-monitor CI path unchanged: re-enumerate also
  finds nothing → `DeviceNotFound`).

**v0.2.4 — hotfix: stale isConnected after KVM switch (macOS).** SHIPPED
(commit `d07a1c7`).

**v0.2.3 — PBP edge-switch KVM + README refresh + in-app Help (macOS).** SHIPPED
(commit `36eba83`, tag `v0.2.3`, release CI green).

**v0.2.3 — PBP edge-switch KVM + in-app Help (Windows side).** SHIPPED (commit
`36eba83`; EdgeSwitchTests fix `87391cc`; verified green on windows-latest CI):
- `EdgeSwitchTracker.cs` (new) + `EdgeSwitchLogic.cs` (pure state machine, separately
  testable): WH_MOUSE_LL hook on the WinForms UI thread; 48-px dead zone + 800-ms dwell
  hysteresis; 3440×1440 display match via Screen.AllScreens; input→KVM mapping
  (TypeC→KvmUsbC, DP→KvmUpstream, HDMI→no switch); state machine (Idle/Standby/Active);
  `SystemEvents.DisplaySettingsChanged` re-scan.
- `HotkeyConfig.cs`: added `EdgeSwitchEnabled` (bool, default false) after `altGrAvoidList`
  — correct §3.8 serialisation order for fixture append.
- `TrayApp.cs`: promoted `_pbpMainSource`/`_pbpSubSource` fields; `HiddenInvokeTarget`
  for BeginInvoke; tracker wired in constructor + `SetEnabled` on settings Save;
  `NotifyPbpMode` in `RecordLastSent`; "Help…" tray menu item.
- `SettingsForm.cs`: added "Edge-Switch KVM" GroupBox (toggle + explainer + privacy
  note); "Help…" button; `currentEdgeSwitchEnabled` parameter (default=false, backward-
  compat); layout expanded to 8 rows.
- `HelpForm.cs` (new): tabbed help (Hotkey Cheat-Sheet / Quick Start / Troubleshooting /
  About) — live config for chord display; links to GitHub via Process.Start.
- `EdgeSwitchTests.cs` (new): 17 unit tests via `EdgeSwitchLogic` directly (no hook/
  display needed); covers mapping, dead-zone, dwell, HDMI no-switch, Reset.
- `MsiMonitorControl.csproj`: added InternalsVisibleTo(MsiMonitorControl.Tests).
- Fixture relay COMPLETE: msi-mac appended `"edgeSwitchEnabled": false` to all 3 fixtures;
  both byte-equality tests re-enabled (`DefaultToJson_EqualsWindowsFixture_ByteForByte` +
  `CtrlShiftPreset_IsByteIdenticalToSharedFixture`). All 17 edge-switch tests + all fixture
  tests expected GREEN in CI.

**v0.2.2 — HDMI inputs + PBP/PIP + source-select + live status (macOS).** SHIPPED
(commit `13cea06`, tag `v0.2.2`, release CI green). PROTOCOL.md + design spec
updated with the fully hardware-confirmed mapping; probe tools committed to main
by lead (973bc94).
- **New commands:** `inputHDMI1`(H), `inputHDMI2`(J) [un-parked]; PBP/PIP modes
  `pbpOff`(O)/`pbpPIP`(I)/`pbpOn`(P) (feature 0x36 0x30; real payloads replacing the
  old nil stubs) — ship WITH default chords (user reconsidered; rebindable as ever).
- **PBP source-select:** `MSIDevice.setPBPSource(window:input:)` (sub `0x36 0x31`
  confirmed; main `0x36 0x32` ASSUMED/unverified, flagged in UI + code).
- **Live status:** in-memory last-sent tracker (3 groups: input/KVM/PBP mode),
  ✓ highlight in menu + Settings, NOT persisted, OSD-staleness caveat.
- **Settings:** new Picture-by-Picture section (mode segmented picker + 2 source
  dropdowns, main "unverified"); hotkey-row **alignment fixed** (label / right-
  aligned chord / +/− in aligned columns).
- All 3 fixtures regenerated (HDMI1/2 H/J; pbp* O/I/P; **showLauncher Space**);
  SETTINGS.md §3.4/§3.6 + canonical order extended. `swift test` 61 tests 0-fail.
- **Quick-launcher palette** (⌃⇧⌘Space default): new `showLauncher` UI action —
  rebindable hotkey that opens a centered floating window (grouped grid of all
  actions, Tab/Space/Enter/Esc nav, shows label+chord, click→run+close). NOT a HID
  command — special-cased in dispatch (`isMonitorCommand`). Required extending the
  key model to allow the named key **`Space`** (contract change — see below).
- **Key model extended:** `HotkeyChord` now accepts named keys (`Space`) beyond
  A–Z/0–9 — `normaliseKey`, validation, Carbon keycode 49, capture-by-keyCode,
  `⌃⇧⌘ Space` display, resilient-loader normalisation. SETTINGS.md §3.4 documents it.

### v0.2.3 — PBP edge-switch KVM + README + Help (msi-mac, 2026-06-22 — SHIPPED, commit 36eba83)

Three tasks: (1) PBP edge-switch KVM, (2) README refresh, (3) in-app Help screen.

| Item | File(s) | Notes |
|:-----|:--------|:------|
| **`edgeSwitchEnabled` config field** | `MSIControl/HotkeyConfig.swift` | New `Bool` field (default false) in `HotkeyConfig`. Custom `Codable` init with `decodeIfPresent` so old configs load cleanly. `jsonData()` appends `"edgeSwitchEnabled": false/true` after `altGrAvoidList`. |
| **Fixtures regenerated × 3** | `docs/fixtures/settings.example.{macos,windows,ctrlshift}.json` | All three now have `"edgeSwitchEnabled": false` as last field. Byte-identity preserved across all presets. |
| **PBP source fields promoted** | `MSIControlApp/DeviceState.swift`, `SettingsView.swift` | `pbpMainSource`/`pbpSubSource: InputEnum` moved from `SettingsView @State` to `DeviceState @Published` so `EdgeSwitchTracker` can read them (design §4.3). `DeviceState` also gains `onPBPModeChanged: (() -> Void)?` callback. |
| **`EdgeSwitchTracker.swift` (NEW)** | `MSIControlApp/EdgeSwitchTracker.swift` | CGEventTap, dedicated runloop thread, NSLock for cross-thread value sharing (msiFrame/dividerX/isEnabled), ±48 px dead zone + 800 ms dwell, input→KVM mapping. Permission helpers: `InputMonitoringStatus`, `probeInputMonitoringPermission()`. |
| **Settings UI — Edge-Switch section** | `MSIControlApp/SettingsView.swift` | New "Edge-Switch KVM" section below PBP: toggle, explainer, privacy note, Input Monitoring status row with deep-link "Open System Settings…" button (shown when denied). |
| **SettingsStore wired** | `MSIControlApp/SettingsStore.swift` | `setEdgeSwitchEnabled(_:)`: probes permission on enable, persists, notifies tracker. `inputMonitoringStatus: InputMonitoringStatus` published. `edgeSwitchTracker: EdgeSwitchTracker?` retained. |
| **App.swift wired** | `MSIControlApp/App.swift` | Creates `EdgeSwitchTracker` alongside `SettingsStore` in `init`. Wires `onPBPModeChanged` callback → tracker. Applies initial `edgeSwitchEnabled` if config was saved with it true. |
| **SETTINGS.md updated** | `docs/SETTINGS.md` | §3.1 + §3.8: `edgeSwitchEnabled` documented. |
| **EdgeSwitchTests.swift (NEW)** | `Tests/MSIControlTests/EdgeSwitchTests.swift` | 8 tests: config round-trip, missing-on-load defaults false, fixture byte check, KVM mapping contract assertions. |
| **README.md refreshed** | `README.md` | Full current feature set: all inputs (HDMI1/2/Type-C/DP), KVM (USB-C/Upstream/Auto), PBP/PIP modes + source select, configurable hotkeys + presets + rebinding, quick-launcher, edge-switch KVM, live status, debug log. Updated default hotkey tables (both platforms). Updated first-launch notes (Gatekeeper/SmartScreen). |
| **HelpView.swift (NEW)** | `MSIControlApp/HelpView.swift` | In-app Help window: (a) live hotkey cheat-sheet, (b) feature quick-start, (c) troubleshooting, (d) About/links. Opened from menu bar "Help…" and Settings "Help…" button. |
| **MenuBarView + App.swift wired** | `MSIControlApp/MenuBarView.swift`, `App.swift` | "Help…" menu item; `Window("help")` scene; `openHelp` closure passed to Settings. |

**Fixture `edgeSwitchEnabled` bytes for Windows teammate:**
```
  "edgeSwitchEnabled": false
```
Appears as the last field after `altGrAvoidList` in all 3 fixtures (identical in all three — platform-independent boolean).

**Verification (v0.2.3):** `swift build` + `swift build -c release` + `swift test` = **69 tests, 0 failed, 1 skipped** (fixture REGEN gate). `./build-app.sh` — adhoc-signed bundle, Sealed Resources valid. SHIPPED (commit `36eba83`).

**v0.2.1 — default hotkey scheme fix (macOS).** Default chord changed from ⌃⌥⇧ to
**⌃⇧⌘ (Control+Shift+Command, NO Option)** per user testing; preset renamed
`hyper`→`cmdShiftCtrl` with a platform-aware label. The new default is **per-OS**
(Mac `command`, Windows `alt`), so the shared fixture is now **split** into
`settings.example.{macos,windows}.json`; byte-identity across apps now holds only
for the platform-independent `ctrlShift` preset, with mutual-loadability proven for
the per-OS default. SHIPPED (commit `e8387a8`, tag `v0.2.1`).
See the v0.2.1 section below.

**v0.2.0 — configurable cross-platform hotkeys + settings.** Design contract
`docs/SETTINGS.md` APPROVED. SHIPPED (tag `v0.2.0`); Windows built in parallel
against the same schema.
- **msi-mac** — v0.2.0 macOS side: `HotkeyConfig` model, data-driven `Command`,
  config-driven `HotKeyManager` with live re-register, SwiftUI settings UI,
  `SMAppService` launch-at-login. **SHIPPED** (2026-06-22).
- Earlier: Phase 1 + post-MVP hardening + hardware-feedback fixes — COMPLETE (committed).
- **msi-windows** — Track C/D + KVM/Auto fixes COMPLETE; v0.2.0 C# side in progress.

### v0.2.1 — default scheme fix (msi-mac, 2026-06-22 — SHIPPED, commit e8387a8)

| Item | File(s) | Notes |
|:-----|:--------|:------|
| Default mods ⌃⌥⇧ → **⌃⇧⌘** | `HotkeyConfig.swift` | `HotkeyPreset.cmdShiftCtrl.macModifiers` = `[control, shift, command]` (drop option). `makeDefault()` seeds it. |
| Preset rename `hyper` → `cmdShiftCtrl` | `HotkeyConfig.swift`, tests | Raw token is contract-shared with Windows. Added `isPerPlatform` + `macDisplayName` (label derived from mods, e.g. "Default (⌃⇧⌘)"). `inferredPreset` updated. |
| Platform-aware preset label | `SettingsView.swift` | Dropdown labels now come from `preset.macDisplayName` (no hardcoded glyphs). |
| **Fixture split** (per-OS default) | `docs/fixtures/settings.example.{macos,windows}.json` | Old single `settings.example.json` removed. macOS mods `[control,shift,command]`; Windows mods `[control,alt,shift]` (canonical order: control, alt/option, shift, command → alt before shift). Both regenerated to the §3.8 canonical layout. |
| Contract wording | `docs/SETTINGS.md` §2.1, §3.2, §3.8, §7, §8 | Byte-identity across apps holds ONLY for platform-independent presets (`ctrlShift`); per-OS presets (`cmdShiftCtrl`, `legacy`) are byte-identical only within a platform; mutual-loadability holds for all presets via option↔alt synonym + command-drop-on-Windows. |
| Tests | `HotkeyConfigTests.swift` | Default mods/preset/byte-equality updated to macOS fixture; `testWindowsFixtureLoadsViaSynonym` (mutual-loadability) + `testMacFixtureParsesToDefaults`. Duplicate/AltGr tests updated for new default. |
| **Shared ctrlShift byte fixture** | `docs/fixtures/settings.example.ctrlshift.json` (new) | Platform-INDEPENDENT default config under `ctrlShift` (mods `["control","shift"]`). `testCtrlShiftPresetIsByteIdenticalToSharedFixture` now asserts `default→ctrlShift save() == this fixture` BYTE-FOR-BYTE (was a shape-only no-command/no-alt check). Windows points its test at the SAME file → proves true cross-app byte-identity. |
| **KVM byte→port mapping FIX (hardware-confirmed)** | `Command.swift`, `docs/PROTOCOL.md`, tests, all 3 fixtures, `tools/README.md` | Probed on the MD342CQP via `tools/kvm-probe`: **0x30=Auto, 0x31=Upstream, 0x32=USB-C** (0x33 no-op). Corrected `kvmUSBC` 0x30→**0x32**; `kvmUpstream` 0x31 unchanged; **`kvmAuto` now LIVE** — byte[10]=**0x30** (was nil/UNKNOWN), a normal available command with menu item + ⌃⇧⌘A hotkey **and a seeded default `A` chord in all 3 fixtures** (lead decision A). Tests flipped; all 3 fixtures regenerated (kvmAuto bound). PROTOCOL.md KVM + "What is NOT known" updated (only PBP remains unknown). Probe tools `kvm-probe`/`kvm-send` kept + documented. |
| **Debug log + crash/signal capture** | `MSIControl/DebugLog.swift` (new, + tests), `App.swift`, `MSIDevice.swift`, `HotKeys.swift`, `SettingsStore.swift`, `MenuBarView.swift` | For the "app silently quits" bug. File log at `…/LogicalSapien/MSIMonitorControl/debug.log` (size-capped ~1MB, session-start marker, ISO8601 lines, os_log mirror). Logs launch/quit, hotkey fires, HID send + IOReturn, device locate/connect, reopen-retry, settings commit/rollback + save errors. **Crash capture (async-signal-safe — Codex blocker fixed):** signal handler is a file-scope C function pointer touching ONLY pre-built globals (pre-opened fd + per-signal markers pre-encoded as `[UInt8]` at startup); in-handler it calls ONLY `write` + `backtrace_symbols_fd` (alloc-free backtrace) + `signal`/`raise` — NO String/malloc/Foundation/os_log (those can deadlock mid-crash). `NSSetUncaughtExceptionHandler` keeps full String+backtrace (normal context). Signals SIGSEGV/ABRT/ILL/BUS/TRAP/**SIGTERM**. "Reveal Debug Log…" menu item. Verified: SIGTERM writes `FATAL TERMINATING: signal SIGTERM` + a full backtrace end-to-end. |

**Coordination for msi-windows-2:** preset raw token is **`cmdShiftCtrl`** (must match exactly); Windows default config = `settings.example.windows.json` with default mods `["control","alt","shift"]` in canonical order (alt BEFORE shift). `ctrlShift` is the only byte-identical-across-platforms preset.

**Verification (v0.2.1):** `swift build` + `-c release` clean, **no warnings**; `swift test` = **55 tests, 0 failed, 3 skipped** (2 device + REGEN generator). `testDefaultSaveBytesEqualFixtureBytes` (vs macOS fixture) + the new cross-app tests pass. `./build-app.sh` valid; fresh first-run config is **byte-for-byte identical to `settings.example.macos.json`** (verified via `diff`). SHIPPED.

### v0.2.0 — settings + hotkeys (msi-mac, 2026-06-22 — SHIPPED, tag v0.2.0)

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
mutual-loadability). SHIPPED (tag `v0.2.0`); Windows byte-match confirmed in CI.

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

### Hardware-feedback fixes (msi-mac, 2026-06-22 — SHIPPED)

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

### v0.2.0 — settings + hotkeys (msi-windows, 2026-06-22 — SHIPPED, tag v0.2.0)

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

### v0.2.1 — default scheme fix (msi-windows, 2026-06-22 — SHIPPED, tag v0.2.1)

User testing changed the default scheme: macOS ⌃⌥⇧→⌃⇧⌘; **Windows default UNCHANGED at
Ctrl+Alt+Shift** (intentional per-OS: Mac Command sits where the user's Alt is → same physical
keys). Windows changes:
- **Preset rename** `hyper`→`cmdShiftCtrl` (JSON token + enum case `HotkeyPreset.CmdShiftCtrl`;
  the auto camelCase converter maps the enum name → exactly `cmdShiftCtrl`). Windows dropdown
  label "Default (Ctrl+Alt+Shift)". Clean rename, **no `hyper` read-alias** (new app, no
  v0.2.0 configs in the wild — lead+human confirmed).
- **Native `alt` on write:** removed the v0.2.0 `alt`→`option` write-mapping; Windows now writes
  its native `alt` (the option→alt READ synonym stays so a macOS file still loads).
- **Fixture split:** old `settings.example.json` deleted; `settings.example.windows.json` (mine:
  `cmdShiftCtrl`, mods `["control","alt","shift"]`) + `settings.example.macos.json` (mac:
  `["control","shift","command"]`). My output matches the windows fixture byte-for-byte
  (hand-verified vs `od -c`: ends `}\n}\n`, no BOM, native `alt`).
- **Byte-identity now scoped (§2.1/§3.8):** the per-OS DEFAULT is byte-identical only WITHIN a
  platform; the platform-independent `ctrlShift` preset is the genuine cross-app byte check;
  mutual-loadability holds everywhere (a macOS default loads here with `command` dropped→Ctrl+Shift).
- **Tests:** `DefaultToJson_EqualsWindowsFixture_ByteForByte` (was EqualsSharedFixture);
  `WindowsFixture_ParsesAndReproducesDefaultBindings`; **`CtrlShiftPreset_IsByteIdenticalToSharedFixture`**
  — now asserts `ApplyPreset(ctrlShift).ToJson() == docs/fixtures/settings.example.ctrlshift.json`
  BYTE-FOR-BYTE (msi-mac's committed shared reference; the macOS side asserts the SAME file →
  true cross-app byte-identity, not shape-only); **`MacosFixture_CrossLoads_CommandDroppedRestSurvives`**
  (mutual-loadability); flipped `Default_WrittenJson_UsesNativeAltSpelling_NotOption`; all
  `Hyper`→`CmdShiftCtrl`/`WinDefault` renames; test csproj copies all THREE fixtures
  (windows + macos + ctrlshift).
- Contract-comment wording aligned to the scoped-byte-identity model (matches msi-mac's
  §2.1/§3.2/§3.8: cross-app byte-identity for ctrlShift only; per-OS presets within-platform;
  mutual-loadability everywhere).
- Runtime stays LF (v0.2.0 fix kept). No local dotnet → windows-latest CI was the gate (green). SHIPPED.
- **KVM byte[10] mapping — DONE (hardware-confirmed v0.2.1):** `Command.cs` updated to the
  probed mapping — **USB-C=0x32 (was wrongly 0x30), Upstream=0x31, Auto=0x30**. `KvmUsbC` byte[10]
  fixed; new `PayloadKvmAuto` (0x30); `PayloadFor(KvmAuto)` returns it (no longer throws);
  `IsAvailable(KvmAuto)=true` → KVM Auto is now a LIVE command (menu item + eligible for a hotkey).
  `CommandTests` updated: `ExpectedKvmUsbC` byte[10]→0x32, new `ExpectedKvmAuto`/`KvmAutoPayloadMatchesProtocol`,
  `KvmPayloadsDifferOnlyAtByte10_WithConfirmedMapping` (all three), KvmAuto removed from the
  throws-theory, `IsAvailable(KvmAuto)` false→true. Byte-identical to macOS Command.swift.
  **KvmAuto default binding — RESOLVED (option A):** msi-mac regenerated all 3 fixtures with
  kvmAuto now BOUND (windows `["control","alt","shift"]` key `A`; macos `["control","shift","command"]`
  key `A`). So `Default()` now seeds `kvmAuto = [{cmdShiftCtrl, A}]` (matches the regenerated
  windows fixture → byte test green). Updated the 4 tests that asserted kvmAuto empty (now assert
  the `A` chord; use pbpOn for the still-empty cases); cross-load test loops kvmAuto too
  (macOS command-drop → Ctrl+Shift+A).

**Debug logging + crash capture (msi-windows, v0.2.1 — matches macOS):**
- New `DebugLog.cs` — static best-effort file logger → `%APPDATA%\LogicalSapien\MSIMonitorControl\debug.log`
  (vendor dir, beside settings.json). Truncate-on-launch + session-start marker; ~1 MB size
  backstop. Structured British-English lines `yyyy-MM-dd HH:mm:ss.fff [LEVEL] message`. Never
  throws into the app (all writes wrapped).
- **Crash capture:** `Init()` hooks `AppDomain.UnhandledException` + `Application.ThreadException`
  → writes a `FATAL TERMINATING: <type>: <msg>\n<stack>` line before death. `Program.Main` sets
  `SetUnhandledExceptionMode(CatchException)` + logs launch/exit; normal quit logs `Session ended`
  → distinguishes user-quit from crash.
- **Logged events:** app launch/quit, tray ready, every command invoked (which command), every HID
  send + result (OK/DeviceNotFound/UNKNOWN-payload/exception), device connect/disconnect/refresh,
  settings saves + re-register rejections.
- **Discoverable:** tray "Reveal debug log" item → opens the folder (selects the file) via Explorer.
- Wired into Program.cs, TrayApp.cs, MsiDevice.cs (16 call sites).

### v0.2.2 — HDMI inputs + PBP/PIP + source-select + live status (msi-windows, code-complete)

- **Command.cs:** `CommandKind` += `InputHdmi1`(0x30)/`InputHdmi2`(0x31) on Input feature 0x35 0x30;
  `PbpOff`(0x30)/`PbpPip`(0x31)/`PbpOn`(0x32) on new PBP/PIP-mode feature 0x36 0x30 — all real
  payloads now (PBP no longer throws); all 10 `IsAvailable`. Enum + ActionId + CanonicalActionOrder
  in the §3.6 contract order (inputHDMI1, inputHDMI2, inputTypeC, inputDP, kvmUSBC, kvmUpstream,
  kvmAuto, pbpOff, pbpPIP, pbpOn). Byte-identical to macOS.
- **PBP source-select:** parameterised `Command.PbpSourcePayload(window,input)` + `MsiDevice.SetPbpSource`
  — sub-window feature 0x36 0x31, main-window 0x36 0x32 (**main flagged unverified** in code+UI);
  value byte = input enum (HDMI1=0x30…Type-C=0x33).
- **Defaults:** all 10 actions seeded — inputs H/J/C/D, KVM K/U/A, **PBP/PIP O/I/P** (v0.2.2 user
  reconsider — they DO get default chords). Windows mods control/alt/shift; ctrlShift re-bakes.
- **Settings UI:** new "Picture-by-Picture" section (mode picker + sub/main source dropdowns, main
  "(unverified)"); hotkey rows auto-gain HDMI/PBP (data-driven). **Row-alignment tidy:** fixed
  200px label column + AutoEllipsis, single-line `[label][chord][×]…[+Add]` (no float-below bug).
- **Live status:** last-sent input/KVM/PBP-mode tracked in-memory (NOT persisted; OSD/button
  changes not reflected — documented); active item ticked via `ToolStripMenuItem.Checked` in tray.
- **Fixtures:** all 3 regenerated by mac (10 bound, O/I/P); my `Default()`/`ApplyPreset(ctrlShift)`
  reproduce the windows + ctrlshift fixtures byte-for-byte (verified vs the committed files).
- **Tests:** HDMI/PBP payloads + differ-only-at-byte10, PbpSourcePayload (sub/main feature + value),
  all-available, never-throws, ActionId/Label, fixture byte tests + cross-load.

**Quick-launcher + "Space" key (v0.2.2 final piece — msi-windows):**
- **11th action `showLauncher`** (key=Space, mods=preset) added — appended to `CanonicalActionOrder`
  + `Default()` (Ctrl+Alt+Shift+Space). NON-HID: `Command.IsMonitorCommand(ShowLauncher)=false`;
  `PayloadFor` throws `InvalidOperationException` (never sent); `TrayApp.OnCommand` routes it to
  `HandleAppCommand`→`ShowLauncher()` before any device call. Not a tray monitor-menu item; IS a
  rebindable hotkey.
- **Key model extended for "Space"** (4 spots): `HotkeyConfig.NamedKeys=["Space"]` + `NormaliseKey`
  (case-insensitive→canonical "Space", else upper-case A–Z/0–9); `IsValidBaseKey` accepts it;
  `HotKeys.TryVk` maps Space→`VK_SPACE` 0x20; `ChordCaptureDialog` captures `Keys.Space`→"Space";
  `DisplayString` renders "Space" (not upper-cased) → "Ctrl+Alt+Shift+Space". No migration/alias.
- **`LauncherForm.cs` (new):** centred TopMost FixedToolWindow; grid of the 10 monitor commands
  grouped Inputs/KVM/Modes; each button shows label+chord; Tab cycles (TabStop/TabIndex), Space/
  Enter activates, Esc closes; click→run+close (dispatches back through `OnCommand`). Single
  instance (re-activates if open); disposed on tray shutdown.
- **Fixtures:** all 3 regenerated by mac with showLauncher (Space). My `Default()`/`ApplyPreset`
  reproduce windows + ctrlshift byte-for-byte (verified vs committed; both end `}\n}\n`, no BOM).
- **Tests:** ShowLauncher actionId/label, IsMonitorCommand + PayloadFor-throws, Space validity +
  NormaliseKey casing + Parse-normalises-"space"→"Space", DisplayString Space, fixture byte tests
  + cross-load now include the 11th binding; monitor-only payload/never-throw tests gate on
  `IsMonitorCommand`.
- Not built locally (no dotnet) → windows-latest CI was the gate (green). SHIPPED (commit `13cea06`).

**Codex review fix (v0.2.2, msi-windows — 1 blocking + non-blockers):**
- 🔴 **HID-boundary guard:** `MsiDevice.Send` now returns the new `MsiResult.NotAMonitorCommand`
  (never throws) for an app-only command (ShowLauncher) — checked FIRST, before connectivity or
  `PayloadFor`. Defence-in-depth: a direct/future `Send(ShowLauncher)` is safe even though the
  dispatcher already routes it to the launcher. The `PayloadFor` catch widened to
  NotImplemented+InvalidOperation as a backstop for any future payload-less command.
- 🟡 Tests: `Send(ShowLauncher)`→NotAMonitorCommand (no throw, no monitor); `SetPbpSource`→
  DeviceNotFound (no monitor); `Send_ReturnsDeviceNotFound` theory extended to all 10 monitor
  commands (HDMI1/2 + PBP modes incl.).
- 🟡 Stale comments cleaned: removed "UNKNOWN payload / reverse-engineer" wording from HotKeys.cs,
  TrayApp.cs, MsiDevice.cs (all monitor payloads are hardware-confirmed in v0.2.2).

## Blockers

None blocking a release. The remaining open items are all hardware-dependent and
do not gate shipping (KVM, PBP/PIP modes + sub-source, and all four inputs are
hardware-confirmed and shipped):

- **PBP main-window source — feature `0x36 0x32`** — ASSUMED, not hardware-verified
  (the KVM/USB-C control connection sits on the main window, so probing it risks
  losing control). Flagged unverified in both apps' UI and in `docs/PROTOCOL.md`.
  Verify when safe and update PROTOCOL.md.
- **KVM smoke-test** — the byte→port mapping was probed and corrected in v0.2.1
  (Auto `0x30`, Upstream `0x31`, USB-C `0x32`). A full end-to-end smoke-test of
  `kvmUpstream`/`kvmUSBC` from the app on real hardware should still confirm it.

## Next steps

1. Human: smoke-test KVM (`kvmUpstream` / `kvmUSBC`) on the real MD342CQP and
   confirm the v0.2.1 position→port mapping end-to-end via the app.
2. Human: guided probe of the PBP main-window source (`0x36 0x32`) when safe;
   update `docs/PROTOCOL.md` if it differs from the assumed input enum.
3. v0.1.2 hardening polish — remaining low-priority robustness clean-ups
   (e.g. the report-ID double-count question in PROTOCOL.md, confirmable only via
   a USB HID capture on hardware).

Releases are cut and live: **v0.2.0 → v0.2.4** are all tagged, with green
`release.yml` runs and published assets on GitHub Releases.

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

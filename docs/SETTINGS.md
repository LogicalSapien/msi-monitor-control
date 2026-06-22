# SETTINGS — shared configuration contract (v0.2.0)

**Status:** Design — awaiting human approval. No app code until approved.
**Owner of this contract:** `msi-mac` (same single-source-of-truth role as
`docs/PROTOCOL.md`). Both the macOS (Swift) and Windows (C#) apps read and write a
**byte-for-byte identical** JSON config against the schema below.

> This document is the contract. If the Swift and C# implementations ever disagree
> about the config, **this file wins** and the divergent app is wrong. Treat any
> schema change as a change to a public interface: bump `schemaVersion`, update
> this doc first, then both apps.

---

## 1. Scope (v0.2.0)

User feedback drove a single coherent settings feature, shipping in full on **both
platforms** in v0.2.0:

- **Configurable global hotkeys** with a **preset scheme** selector.
- **Per-action rebinding UI** — click a row, press a chord to rebind; add/remove
  extra hotkeys per action; conflict + AltGr advisory detection; **live
  re-registration** without an app restart.
- **Persisted JSON config** — shared schema, identical across both apps, in the
  per-OS application-support directory.
- **Launch-at-login** toggle — macOS `SMAppService`, Windows HKCU `…\Run`.

Out of scope: cloud sync, profiles/per-monitor configs, importing other apps'
keymaps. (YAGNI — add later only if asked.)

---

## 2. Config file location (per OS)

| OS | Path |
|:---|:-----|
| macOS | `~/Library/Application Support/LogicalSapien/MSIMonitorControl/settings.json` |
| Windows | `%APPDATA%\LogicalSapien\MSIMonitorControl\settings.json` (i.e. `C:\Users\<user>\AppData\Roaming\LogicalSapien\MSIMonitorControl\settings.json`) |

- The config nests under a **vendor folder `LogicalSapien`** then the app folder
  **`MSIMonitorControl`** on both platforms, so the vendor dir can be reused by
  future LogicalSapien apps.
- File name is exactly **`settings.json`**.
- macOS resolves the base via `FileManager.default.url(for: .applicationSupportDirectory, …)`
  then appends `LogicalSapien/MSIMonitorControl`; Windows via
  `Environment.GetFolderPath(SpecialFolder.ApplicationData)` then
  `LogicalSapien\MSIMonitorControl`.
- This vendor nesting applies to the **config folder only**. It does NOT apply to
  the Windows registry Run value name, which stays flat — see §6.
- The app creates the directory (and a default file) on first run if absent.
- Writes are **atomic**: the file is replaced in one step (temp-file write followed
  by an atomic rename over `settings.json`) so a crash mid-write cannot corrupt the
  live config. Either platform's native atomic-replace satisfies this — macOS uses
  `Data.write(options: .atomic)`, Windows uses a literal `settings.json.tmp` +
  `File.Move(overwrite:)`. Both are atomic-replace; the exact temp mechanism is an
  implementation detail.

### 2.1 Cross-app JSON compatibility level

Both apps use a **custom serialiser** to one canonical layout (stock encoders can't
agree — Swift `JSONEncoder` forces `" : "` and can't fix key order; C#
`System.Text.Json` emits `": "` with no leading-space option). The exact format is
in **§3.8**. Two levels of guarantee:

1. **Byte-identical across apps — for platform-INDEPENDENT presets only.** Under
   `ctrlShift` (same mods on both platforms), a config written by either app is
   byte-for-byte identical. This is the genuine cross-app byte guarantee.
2. **Byte-identical within a platform — for per-OS presets.** The default
   `cmdShiftCtrl` (and `legacy`) bake platform-specific mods (mac `command`, win
   `alt`), so their files CANNOT be byte-identical across platforms. Each app is
   byte-identical to ITS OWN platform fixture, and the two fixtures differ only in
   the `mods` tokens.

**Mutual-loadability holds for ALL presets:** a config written by either app loads
in the other to an equivalent in-memory model, via the option↔alt synonym (§3.4)
and the command-drop on Windows.

Fixtures (the cross-app ground truth, regenerated from each encoder):
- `docs/fixtures/settings.example.macos.json` — default config, mac mods
  (`["control","shift","command"]`).
- `docs/fixtures/settings.example.windows.json` — default config, win mods
  (`["control","alt","shift"]`).
- `docs/fixtures/settings.example.ctrlshift.json` — **shared** default config under
  the platform-INDEPENDENT `ctrlShift` preset (mods `["control","shift"]`). BOTH
  apps emit this byte-for-byte; each has a `save()==this fixture` test, which is the
  one genuine cross-app byte-identity guarantee.

Contract tests (each app): *parse own fixture → model == built-in default*;
*default.save() bytes == own platform fixture*; a `ctrlShift` config is
platform-independent (the true cross-app byte case); and *load the OTHER platform's
fixture → equivalent model* (proves mutual-loadability for the per-OS default).

---

## 3. The shared JSON schema

### 3.1 Top-level object

```jsonc
{
  "schemaVersion": 1,            // integer; bump on any breaking schema change
  "preset": "cmdShiftCtrl",      // "cmdShiftCtrl" | "ctrlShift" | "legacy" | "custom"
  "launchAtLogin": false,        // boolean
  "bindings": { … },             // map: actionId -> array of chords (see 3.3)
  "altGrAvoidList": { … }        // advisory data for the EU-layout warning (see 3.5)
}
```

Unknown top-level keys are **ignored** (forward-compatibility). Missing optional
keys fall back to built-in defaults (see §4).

### 3.2 `preset` — the scheme selector

`preset` is a **label**, not a runtime authority. At runtime both apps read the
explicit per-binding modifiers only (§3.3). The preset value records which named
scheme the bindings currently match, for the UI dropdown:

| Value | Modifiers applied when selected | macOS chord | Windows chord | Per-OS? |
|:------|:--------------------------------|:------------|:--------------|:--------|
| `cmdShiftCtrl` (default) | per-platform: mac Control+Shift+Command, win Control+Alt+Shift | ⌃⇧⌘ | Ctrl+Alt+Shift | **yes** |
| `ctrlShift` | Control + Shift | ⌃⇧ | Ctrl+Shift | no |
| `legacy` | per-platform: mac Control+Option+Command, win Control+Alt | ⌃⌥⌘ | Ctrl+Alt | **yes** |
| `custom` | — (set automatically; never selectable directly) | — | — | — |

The default preset is **`cmdShiftCtrl`**. Its modifiers differ per platform — macOS
uses Command (no Option/Alt); Windows uses Alt (no Command) — because macOS reserves
many `⌃⌥` (Control+Option) letter chords and Command-based chords are the macOS
convention, while Windows has no Command key. The preset KEY (`cmdShiftCtrl`) is
shared; the displayed chord and the written `mods` are platform-specific. The
dropdown label is derived from the platform's own mods (mac shows "Default (⌃⇧⌘)",
Windows shows "Default (Ctrl+Alt+Shift)").

**Apply-and-bake semantics.** Selecting a preset in the UI is an **action**: the
app rewrites every binding's `mods` to that scheme's modifiers and persists the
explicit chords. The moment the user hand-edits any binding so it no longer matches
the selected preset, the app sets `preset` to `"custom"`. This keeps a single
source of truth (the explicit `mods` on each binding) and removes any
preset-vs-binding merge ambiguity between the two apps.

> Note on per-OS presets (`cmdShiftCtrl`, `legacy`): their modifiers differ per
> platform (mac includes Command/⌘; Windows substitutes Alt and has no ⌘). When
> such a preset is applied, each app bakes ITS platform's mods. The default
> `cmdShiftCtrl` therefore stores `["control","shift","command"]` on macOS and
> `["control","alt","shift"]` on Windows; `legacy` stores
> `["control","option","command"]` on macOS and `["control","alt"]` on Windows.
> (Note the canonical element order — control, option/alt, shift, command, §3.8 —
> so Windows writes `alt` BEFORE `shift`.) Both apps still read explicit mods via
> the option↔alt synonym, so a config written by one loads correctly in the other
> (§2.1, §3.4). Consequently a per-OS preset's saved file is byte-identical only
> WITHIN a platform, not across — see §2.1/§3.8.

### 3.3 `bindings` — per-action chords (full-chord model)

```jsonc
// macOS default (cmdShiftCtrl preset); see §3.8 for the on-disk multi-line layout.
"bindings": {
  "inputTypeC": [ { "mods": ["control", "shift", "command"], "key": "C" } ],
  "inputDP":    [ { "mods": ["control", "shift", "command"], "key": "D" } ],
  "kvmUSBC":    [ { "mods": ["control", "shift", "command"], "key": "K" } ],
  "kvmUpstream":[ { "mods": ["control", "shift", "command"], "key": "U" } ],
  "kvmAuto":    [ { "mods": ["control", "shift", "command"], "key": "A" } ],
  "pbpOn":      [],                                  // empty: no payload yet → no chord
  "pbpOff":     []                                   // empty: no payload yet → no chord
}
```

- **Key = `actionId`** (stable string id; see §3.6). Maps 1:1 to a `Command`
  case (Swift) / `CommandKind` (C#).
- **Value = an array of chord objects.** An array (not a single object) supports
  **multiple hotkeys per action** (the add/remove-extra-hotkey feature). An empty
  array means "no hotkey for this action" — used for actions whose HID payload is
  still UNKNOWN (`pbpOn`, `pbpOff`), which must not occupy a chord until
  reverse-engineered. (`kvmAuto` is now hardware-confirmed and bound.)
- **Chord object:** `{ "mods": [ <modifier>… ], "key": "<base key>" }`.
  - `mods`: array of canonical modifier tokens (§3.4). Order is **not** significant;
    apps compare as a set. May be empty only if a future preset allows it (none do
    today — a modifier-less global hotkey is rejected by conflict rules, §3.5).
  - `key`: the **base key** as a single upper-case character `A`–`Z` or digit
    `0`–`9`, OR a named key token for the small set we allow (§3.4). The displayed
    chord is derived (§3.7), never stored.

### 3.4 Canonical modifier + key vocabulary

Modifiers use **one shared token set**; each app maps tokens to its native API.
`option` and `alt` are accepted as **synonyms** (same physical key) so a config is
portable; apps **write** the platform-native spelling but **read** either.

| Token | macOS (Carbon) | Windows (Win32 `MOD_*`) | Notes |
|:------|:---------------|:------------------------|:------|
| `control` | `controlKey` | `MOD_CONTROL` | |
| `option` / `alt` | `optionKey` | `MOD_ALT` | synonyms; same physical key |
| `shift` | `shiftKey` | `MOD_SHIFT` | |
| `command` | `cmdKey` | *(unsupported)* | macOS only; on Windows a `command` token is **ignored with a warning** |

Base `key` values: a single `A`–`Z` / `0`–`9` character, OR a **named key** from a
small explicit allow-list. **Named keys (v0.2.2): `Space`** (added for the
quick-launcher palette). Named keys are written verbatim (e.g. `"key": "Space"`) and
are case-insensitively normalised on read (`space`→`Space`); single characters are
upper-cased. Both apps share the SAME named-key set — adding one is a contract change
needing a keycode-table entry in every app (Carbon code 49 for Space on macOS;
`VK_SPACE` on Windows). Other function/arrow keys remain out of scope. Each app keeps
a private key→native-keycode table; these tables are an **implementation detail**,
NOT part of the config. The derived display renders a named key as a word, e.g.
`⌃⇧⌘ Space` (with a separating space, vs `⌃⇧⌘C` for a character).

### 3.5 Conflict + AltGr rules

Validation runs in the rebinding UI **before** committing a chord, and again on
load. Three checks:

1. **Duplicate (BLOCKING).** The same chord (same mods-set + key) must not be bound
   to two actions. The UI rejects the rebind and names the conflicting action.
2. **OS-reserved (BLOCKING where detectable).**
   - macOS: a `RegisterEventHotKey` that returns a non-`noErr` status (commonly the
     chord is already taken system-wide) → treat as reserved; reject and keep the
     previous binding.
   - Windows: `RegisterHotKey` returning false with `ERROR_HOTKEY_ALREADY_REGISTERED`
     → reserved; reject. We do not maintain a static reserved-list; we rely on the
     OS register call as the authority (it is the ground truth and avoids drift).
3. **AltGr / EU-layout (NON-BLOCKING warning).** If the chosen `key` is in
   `altGrAvoidList.keys` AND the chord's mods include `alt`/`option`, show an
   advisory (the chord may collide with an AltGr-composed character on some EU
   layouts). The user may proceed. This never blocks and never alters the config.

`altGrAvoidList` is shipped **in the config** so it can be tuned without an app
rebuild:

```jsonc
"altGrAvoidList": {
  "keys": ["Q", "E", "B", "7", "2", "3", "4", "5", "8", "9", "0"],
  "note": "Letters/digits that commonly carry an AltGr-composed char on EU layouts (e.g. @, EUR, {, }, [, ], accented vowels). Advisory only."
}
```

- Accented vowels are not ASCII `key` values (we only allow `A`–`Z`/`0`–`9`), so
  they cannot be bound directly; they are covered by the note for documentation.
- If `altGrAvoidList` is missing/malformed, apps fall back to the **built-in default
  list above** (so the warning still works) and do not error.

### 3.6 `actionId` registry (stable ids)

These string ids are the contract between the config and both apps' command enums.
**Never rename an id** (it would orphan a user's binding); add new ones only.

Listed in the canonical serialisation order (§3.8). All commands are available
(hardware-confirmed) as of v0.2.2.

| `actionId` | Swift `Command` | C# `CommandKind` | Default key | Notes |
|:-----------|:----------------|:-----------------|:------------|:------|
| `inputHDMI1` | `.inputHDMI1` | `InputHdmi1` | `H` | input enum 0x30 |
| `inputHDMI2` | `.inputHDMI2` | `InputHdmi2` | `J` | input enum 0x31 |
| `inputTypeC` | `.inputTypeC` | `InputTypeC` | `C` | input enum 0x33 |
| `inputDP` | `.inputDP` | `InputDp` | `D` | input enum 0x32 |
| `kvmUSBC` | `.kvmUSBC` | `KvmUsbC` | `K` | KVM 0x32 |
| `kvmUpstream` | `.kvmUpstream` | `KvmUpstream` | `U` | KVM 0x31 |
| `kvmAuto` | `.kvmAuto` | `KvmAuto` | `A` | KVM 0x30 |
| `pbpOff` | `.pbpOff` | `PbpOff` | `O` | PBP mode 0x30 |
| `pbpPIP` | `.pbpPIP` | `PbpPip` | `I` | PBP mode 0x31 |
| `pbpOn` | `.pbpOn` | `PbpOn` | `P` | PBP mode 0x32 (PBP) |
| `showLauncher` | `.showLauncher` | `ShowLauncher` | `Space` | **UI action** — opens the quick-launcher palette; NOT a HID command |

`showLauncher` is special: it is a real, rebindable hotkey action (registered like
the others, in the config + all 3 fixtures with default `Space`), but it sends NO
HID report — the dispatch opens the launcher window instead. It has no monitor-state
group. The PBP per-window source-select (`0x36 0x31` sub / `0x36 0x32` main) is NOT a
`Command`/hotkey — it's the parameterised `setPBPSource` device
API driven from the Settings dropdowns (main flagged unverified).

### 3.7 Derived display strings (not stored)

`shortcutDisplay` (the human chord text) is **computed**, never stored — this kills
the drift `shortcutKey`/`shortcutDisplay` could have. Each app builds it from a
chord object:

- macOS: glyphs in canonical order ⌃ ⌥ ⇧ ⌘ then the key, e.g. the default `⌃⇧⌘C`.
- Windows: words joined by `+`, e.g. the default `Ctrl+Alt+Shift+C`.

This **replaces** the hardcoded `shortcutKey`/`shortcutDisplay` on `Command`
(Swift) and the `(key, …)` columns in the static bindings tables — those become
**data-driven** from the loaded config (§5).

### 3.8 Canonical serialisation

Both apps write to ONE canonical layout via a **custom serialiser** (Swift's
`JSONEncoder` forces `" : "` and can't fix key order; C#'s `System.Text.Json`
emits `": "` with no leading-space option — neither stock encoder can hit the
canonical form, so each app hand-rolls it). The per-platform fixtures
`docs/fixtures/settings.example.{macos,windows}.json` ARE this canonical output for
the default config — the cross-app ground truth, regenerated from each encoder (not
hand-formatted). Each app asserts `default.save() == its own platform fixture`
byte-for-byte. Cross-app byte-identity holds for platform-independent presets only
(§2.1); per-OS presets are byte-identical within a platform, with mutual-loadability
proven by each app loading the other's fixture to an equivalent model.

Canonical rules (schemaVersion 1):

- **UTF-8, no BOM.**
- **2-space indent**, standard pretty-print, **one key per line, no column
  alignment.**
- **Separator `": "`** (colon + single space, **no leading space** before the
  colon). This is the STJ-native form; Swift must NOT use stock `JSONEncoder`, which
  forces `" : "`.
- **Exactly one trailing newline** at end of file.
- Top-level key order: `schemaVersion`, `preset`, `launchAtLogin`, `bindings`,
  `altGrAvoidList`.
- `bindings` in the §3.6 actionId order: `inputTypeC`, `inputDP`, `kvmUSBC`,
  `kvmUpstream`, `kvmAuto`, `pbpOn`, `pbpOff`. (NB: this is the contract order, NOT
  any language's enum-declaration order.)
- Each chord object: `mods` then `key`.
- **`mods` array is multi-line** — one element per line (both `JSONEncoder` and STJ
  do this natively; inline is avoided because STJ can't emit it without full
  hand-rolling). Modifier order is canonical: `control`, `option`, `shift`,
  `command`.
- **Empty bindings** serialise as `[]` on the same line as the key.
- **Hyper default writes `option`** (not `alt`) in `mods`. (Both apps READ
  `option`/`alt` as synonyms, but the WRITTEN canonical token is `option`.)
- `altGrAvoidList.keys` in the listed order; `note` verbatim. Forward slash `/` is
  emitted **unescaped**.

Each app has a test asserting `default.save()` bytes **==** the fixture bytes.

---

## 4. Load / fallback behaviour (never block)

The app must always start with working hotkeys. On load:

1. **File missing** → create the directory if needed and write the **built-in
   default config** (preset `cmdShiftCtrl`, the default keys from §3.6, `launchAtLogin:
   false`). Run with it.
2. **File present, parses, `schemaVersion` == current** → use it.
3. **File present but malformed JSON, or `schemaVersion` > current (newer than this
   app)** → **log a diagnostic, ignore the file, run on built-in defaults in
   memory, and do NOT overwrite the user's file.** (Preserves a file written by a
   newer app version, and a hand-edit the user can fix.)
4. **`schemaVersion` < current (older)** → **NO migration code** (project rule: no
   backward compatibility — there are no released users). An older file is simply
   read by the resilient parser, which fills any missing fields from built-in
   defaults; on the next save it is rewritten at the current version. We do NOT
   write migration/upgrade paths, read-aliases for renamed tokens, or legacy
   fallbacks — the canonical schema is changed cleanly and fixtures regenerated.

Per-field resilience: a single malformed binding entry is dropped (with a log), the
rest load. A `command` modifier in a Windows config is dropped with a log. Empty
`bindings` for an action = no chord (valid).

---

## 5. How `Command` becomes data-driven

Today both apps hardcode the key + mods. v0.2.0 splits responsibilities:

- **`Command` / `CommandKind`** keep ONLY intrinsic facts: `actionId`, `label`,
  `payload`, `isAvailable`. They **lose** `shortcutKey` / `shortcutDisplay`.
- A new **`HotkeyConfig`** type (per app) owns: load/save, the in-memory model
  (preset, `launchAtLogin`, `bindings` keyed by `actionId`, `altGrAvoidList`),
  validation (§3.5), and emitting the derived display string (§3.7).
- The hotkey registrars (`HotKeyManager` Carbon / `HotKeys` Win32) register from
  `HotkeyConfig.bindings` instead of a static table, still skipping
  unavailable actions (empty arrays make this automatic).
- The menu/tray reads the display string from `HotkeyConfig`, not `Command`.

### Live re-registration (no restart)

On any config change (preset switch, rebind, add/remove, conflict-free commit):

- **macOS (Carbon):** unregister all current `EventHotKeyRef`s
  (`UnregisterEventHotKey`), then `RegisterEventHotKey` the new set. The single
  `InstallEventHandler` stays installed; only the registrations churn. Serialise on
  the main thread.
- **Windows (Win32):** `UnregisterHotKey` each live id, then `RegisterHotKey` the
  new set on the **same thread** that owns them (the message-filter thread — see
  the existing thread-level note in `HotKeys.cs`). The `IMessageFilter` stays
  attached.

Both: if a new registration fails (OS-reserved), keep the old binding for that
action, surface the conflict in the UI, and leave the rest applied.

---

## 6. Launch-at-login

| | macOS | Windows |
|:--|:------|:--------|
| API | `SMAppService.mainApp` (`register()` / `unregister()`), **macOS 13+** (already our min target) | HKCU `Software\Microsoft\Windows\CurrentVersion\Run`, value `MSIMonitorControl` = quoted exe path |

> **Windows registry value name stays FLAT.** The `Run` value name is exactly
> `MSIMonitorControl` — **not** `LogicalSapien\MSIMonitorControl`. The vendor
> nesting from §2 applies only to the config FOLDER on disk; a registry value name
> is a key under the fixed `Run` path, not a folder path, so it must not be nested.
> (`msi-windows`: do not prefix the Run value with the vendor name.)
| State source of truth | `launchAtLogin` in the config | `launchAtLogin` in the config |
| On toggle | call register/unregister; on success persist the bool; on failure revert the toggle + log | write/delete the registry value; persist the bool; on failure revert + log |
| On launch | optionally reconcile: if the OS state and config disagree, the **config wins** (re-apply) | same |

`SMAppService` is the modern replacement for the deprecated
`SMLoginItemSetEnabled`; macOS 13 is already our floor, so no fallback path needed.

---

## 7. Worked example (default config, macOS-written)

This is the default `settings.json` written to
`~/Library/Application Support/LogicalSapien/MSIMonitorControl/` on first run. It is
the canonical macOS fixture `docs/fixtures/settings.example.macos.json` (shown here
with the §3.8 layout collapsed for readability; the on-disk file has multi-line
`mods` per §3.8):

```json
{
  "schemaVersion": 1,
  "preset": "cmdShiftCtrl",
  "launchAtLogin": false,
  "bindings": {
    "inputTypeC":  [ { "mods": ["control", "shift", "command"], "key": "C" } ],
    "inputDP":     [ { "mods": ["control", "shift", "command"], "key": "D" } ],
    "kvmUSBC":     [ { "mods": ["control", "shift", "command"], "key": "K" } ],
    "kvmUpstream": [ { "mods": ["control", "shift", "command"], "key": "U" } ],
    "kvmAuto":     [ { "mods": ["control", "shift", "command"], "key": "A" } ],
    "pbpOn":       [],
    "pbpOff":      []
  },
  "altGrAvoidList": {
    "keys": ["Q", "E", "B", "7", "2", "3", "4", "5", "8", "9", "0"],
    "note": "Letters/digits that commonly carry an AltGr-composed char on EU layouts. Advisory only."
  }
}
```

The **Windows** default config (`docs/fixtures/settings.example.windows.json`) is
identical except every default `mods` is `["control", "alt", "shift"]` (the default
`cmdShiftCtrl` preset is per-OS — no `command` on Windows). So the default config is
NOT byte-identical across platforms; under the platform-independent `ctrlShift`
preset the two ARE byte-identical (see §2.1).

---

## 8. Build plan (split for parallel work against this contract)

**Phase 0 — contract (this doc).** Approve §3 schema before any code. ← we are here

### (a) macOS tasks — `msi-mac`
1. `HotkeyConfig.swift` in `MSIControl`: model + Codable load/save (atomic write),
   fallback rules (§4), validation (§3.5), derived display (§3.7). Unit tests:
   round-trip, malformed→defaults, newer-version→ignore-don't-overwrite, duplicate
   detection, AltGr warning flagging.
2. Refactor `Command.swift`: drop `shortcutKey`/`shortcutDisplay`; keep
   `actionId`/`label`/`payload`/`isAvailable`. Update `CommandTests`.
3. `HotKeyManager` (Carbon): register from `HotkeyConfig`; implement live
   re-register; keep availability skip.
4. Settings UI (SwiftUI): preset dropdown, per-action rows with click-to-rebind +
   add/remove, conflict + AltGr surfacing, launch-at-login toggle.
5. Launch-at-login via `SMAppService`.
6. Menu reads derived display from `HotkeyConfig`.

### (b) Windows tasks — `msi-windows`
1. `HotkeyConfig.cs`: same model + `System.Text.Json` load/save (atomic), same
   fallback + validation + derived display. Same test matrix.
2. Refactor `Command.cs`/`CommandKind`: drop hardcoded key columns; data-driven.
3. `HotKeys.cs` (Win32): register from `HotkeyConfig`; live re-register on the
   message-filter thread; keep availability skip.
4. Settings UI (WinForms): same surface as macOS (preset, rebind rows, conflict +
   AltGr, launch-at-login).
5. Launch-at-login via HKCU `…\Run`.
6. Tray reads derived display from `HotkeyConfig`.

**Cross-cutting (both, verify against this doc):** per-platform fixtures
`docs/fixtures/settings.example.{macos,windows}.json` (§2.1) are the ground truth.
Each app: (a) `default.save()` == its own platform fixture byte-for-byte;
(b) parse its own fixture → default bindings; (c) load the OTHER platform's fixture
→ equivalent model (mutual-loadability via the option↔alt synonym); (d) a
`ctrlShift` config is byte-identical across platforms (the one true cross-app byte
case, §2.1).

---

## 9. Sign-off (APPROVED by the human, 2026-06-22)

- ✅ **Full v0.2.0 scope** — rebinding UI + multi-bindings + live re-register +
  launch-at-login, both platforms (not phased).
- ✅ **AltGr avoid-list** — `Q/E/B/7` + digits `2–5`/`8–0` + accented-vowel note
  (§3.5), matching the research task's findings.
- ✅ **Full-chord binding model** with **apply-and-bake preset** (§3.2–3.3),
  **computed display strings** (§3.7), **OS-register-as-conflict-authority** (§3.5).
- ✅ **Vendor-nested config folder** `LogicalSapien/MSIMonitorControl` (§2);
  Windows registry Run value name stays flat `MSIMonitorControl` (§6).

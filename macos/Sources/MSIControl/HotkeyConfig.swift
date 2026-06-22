import Foundation

// MARK: - Shared hotkey/settings configuration model
//
// This is the Swift side of the cross-platform settings contract defined in
// `docs/SETTINGS.md`. The JSON it reads/writes is BYTE-FOR-BYTE IDENTICAL to the
// Windows app's for the same model — both apps use a custom serialiser to the one
// canonical layout (SETTINGS.md §2.1 / §3.8). This file must not diverge from it.

/// The current config schema version. Bump on any breaking schema change
/// (see `docs/SETTINGS.md` §4 for the load/fallback rules).
public let kHotkeyConfigSchemaVersion = 1

// MARK: Preset

/// The named modifier scheme a config's bindings currently match. This is a
/// *label* only — at runtime the explicit per-binding modifiers are authoritative
/// (see SETTINGS.md §3.2, "apply-and-bake"). `custom` is set automatically when a
/// binding no longer matches any named preset; it is never chosen directly.
public enum HotkeyPreset: String, Codable, CaseIterable, Sendable {
    case cmdShiftCtrl  // DEFAULT — mac ⌃⇧⌘ / win Ctrl+Alt+Shift (per-OS mods)
    case ctrlShift     // ⌃⇧ / Ctrl+Shift (platform-independent)
    case legacy        // mac ⌃⌥⌘ / win Ctrl+Alt (per-OS mods)
    case custom        // bindings diverge from every named preset

    /// The modifier set this preset applies on macOS. `cmdShiftCtrl` (the default)
    /// and `legacy` are per-platform: they include Command on macOS (and the
    /// Windows app substitutes Alt where macOS uses Command/Option — see
    /// SETTINGS.md §3.2). `custom` has no canonical modifiers (callers keep the
    /// existing per-binding mods), so it returns `nil`.
    public var macModifiers: Set<HotkeyModifier>? {
        switch self {
        case .cmdShiftCtrl: return [.control, .shift, .command]
        case .ctrlShift:    return [.control, .shift]
        case .legacy:       return [.control, .option, .command]
        case .custom:       return nil
        }
    }

    /// Whether this preset's modifiers differ per platform (Mac vs Windows). For
    /// these, byte-identity of the saved config across platforms does NOT hold —
    /// only within a platform (SETTINGS.md §2.1/§3.8). `ctrlShift` is the only
    /// platform-independent named preset.
    public var isPerPlatform: Bool {
        switch self {
        case .cmdShiftCtrl, .legacy: return true
        case .ctrlShift, .custom:    return false
        }
    }

    /// The macOS dropdown label, with the chord glyphs DERIVED from this platform's
    /// actual modifiers (so it stays honest if the mapping changes). Windows builds
    /// its own label the same way from its mods — the preset KEY is shared, the
    /// displayed chord is platform-specific (SETTINGS.md §3.2).
    public var macDisplayName: String {
        let base: String
        switch self {
        case .cmdShiftCtrl: base = "Default"
        case .ctrlShift:    base = "Control + Shift"
        case .legacy:       base = "Legacy"
        case .custom:       return "Custom"
        }
        guard let mods = macModifiers else { return base }
        // Reuse the canonical glyph order via a throwaway chord display.
        let glyphs = HotkeyChord(mods: mods, key: "").display   // e.g. "⌃⇧⌘"
        return "\(base) (\(glyphs))"
    }
}

// MARK: Modifier

/// Canonical modifier token shared across platforms (SETTINGS.md §3.4).
/// `option` and `alt` are synonyms for the same physical key: we decode either and
/// normalise to `.option` (the macOS-native spelling we write).
public enum HotkeyModifier: String, Codable, CaseIterable, Sendable {
    case control
    case option
    case shift
    case command   // macOS only; ignored (with a log) on Windows

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "control":          self = .control
        case "option", "alt":    self = .option   // synonyms → normalise to option
        case "shift":            self = .shift
        case "command":          self = .command
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown modifier token '\(raw)'"))
        }
    }
}

// MARK: Chord

/// A single hotkey chord: a set of modifiers plus a base key.
///
/// `mods` is decoded into a `Set` so order is irrelevant (SETTINGS.md §3.3) and
/// duplicate-comparison is set-based. `key` is a single upper-cased `A`–`Z` / `0`–`9`.
public struct HotkeyChord: Codable, Equatable, Hashable, Sendable {
    public var mods: Set<HotkeyModifier>
    public var key: String

    public init(mods: Set<HotkeyModifier>, key: String) {
        self.mods = mods
        self.key = key.uppercased()
    }

    enum CodingKeys: String, CodingKey { case mods, key }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode mods as an array then fold to a Set (synonyms normalised in
        // HotkeyModifier.init). Unknown tokens throw, which the loader treats as a
        // malformed entry to drop (see HotkeyConfig.load).
        let modArray = try c.decode([HotkeyModifier].self, forKey: .mods)
        let key = try c.decode(String.self, forKey: .key).uppercased()
        // Enforce exactly one A–Z / 0–9 base key (SETTINGS.md §3.3). A hand-edited
        // "AB" or a non-ASCII char must NOT be accepted — Carbon would silently use
        // only the first char, desyncing the display from the registered chord.
        guard HotkeyChord.isValidKey(key) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "Invalid hotkey key '\(key)' — must be a single A–Z or 0–9 character"))
        }
        self.mods = Set(modArray)
        self.key = key
    }

    /// True iff `key` is exactly one character in `A`–`Z` or `0`–`9` (SETTINGS.md §3.3).
    public static func isValidKey(_ key: String) -> Bool {
        guard key.count == 1, let ch = key.first else { return false }
        return (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Encode in canonical order for stable, diff-friendly output.
        let order: [HotkeyModifier] = [.control, .option, .shift, .command]
        try c.encode(order.filter { mods.contains($0) }, forKey: .mods)
        try c.encode(key, forKey: .key)
    }

    /// The human-readable chord, e.g. the default `⌃⇧⌘C` (SETTINGS.md §3.7 —
    /// derived, never stored). Glyphs are emitted in the canonical order ⌃ ⌥ ⇧ ⌘.
    public var display: String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option)  { s += "⌥" }
        if mods.contains(.shift)   { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s + key
    }
}

// MARK: AltGr advisory list

/// Advisory data for the EU-layout AltGr warning (SETTINGS.md §3.5). Shipped in the
/// config so it can be tuned without a rebuild; falls back to a built-in default
/// if missing/malformed.
public struct AltGrAvoidList: Codable, Equatable, Sendable {
    public var keys: [String]
    public var note: String

    public init(keys: [String], note: String) {
        self.keys = keys
        self.note = note
    }

    /// Built-in default (SETTINGS.md §3.5). Used when the config omits the list.
    public static let builtIn = AltGrAvoidList(
        keys: ["Q", "E", "B", "7", "2", "3", "4", "5", "8", "9", "0"],
        note: "Letters/digits that commonly carry an AltGr-composed char on EU layouts (e.g. @, EUR, {, }, [, ], accented vowels). Advisory only."
    )
}

// MARK: - HotkeyConfig

/// The full settings model: schema version, preset label, launch-at-login flag,
/// per-action bindings (keyed by `Command.actionId`), and the AltGr advisory list.
///
/// Load/save go through `HotkeyConfig.load(...)` / `save(to:)`, which implement the
/// atomic-write and never-block fallback rules from SETTINGS.md §4.
public struct HotkeyConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var preset: HotkeyPreset
    public var launchAtLogin: Bool
    /// actionId → ordered list of chords. An empty array means "no hotkey"
    /// (used for actions whose HID payload is still UNKNOWN).
    public var bindings: [String: [HotkeyChord]]
    public var altGrAvoidList: AltGrAvoidList

    public init(schemaVersion: Int = kHotkeyConfigSchemaVersion,
                preset: HotkeyPreset = .cmdShiftCtrl,
                launchAtLogin: Bool = false,
                bindings: [String: [HotkeyChord]],
                altGrAvoidList: AltGrAvoidList = .builtIn) {
        self.schemaVersion = schemaVersion
        self.preset = preset
        self.launchAtLogin = launchAtLogin
        self.bindings = bindings
        self.altGrAvoidList = altGrAvoidList
    }

    // MARK: Defaults

    /// The built-in default config: `cmdShiftCtrl` preset (Mac ⌃⇧⌘), default keys
    /// from each available command, UNKNOWN-payload commands left unbound (empty
    /// array). This is what ships on first run and what we fall back to (§4).
    public static func makeDefault() -> HotkeyConfig {
        let mods: Set<HotkeyModifier> = HotkeyPreset.cmdShiftCtrl.macModifiers ?? [.control, .shift, .command]
        var bindings: [String: [HotkeyChord]] = [:]
        for command in Command.allCases {
            if command.isAvailable {
                bindings[command.actionId] = [HotkeyChord(mods: mods, key: String(command.defaultKey))]
            } else {
                // UNKNOWN payload → no chord until reverse-engineered.
                bindings[command.actionId] = []
            }
        }
        return HotkeyConfig(bindings: bindings)
    }

    /// The canonical actionId order for serialisation (SETTINGS.md §3.6). Fixed by
    /// contract; both apps emit `bindings` in exactly this sequence.
    public static let canonicalActionOrder: [String] = [
        "inputTypeC", "inputDP", "kvmUSBC", "kvmUpstream", "kvmAuto", "pbpOn", "pbpOff",
    ]

    // MARK: File location

    /// The config file URL: vendor-nested under Application Support
    /// (`…/LogicalSapien/MSIMonitorControl/settings.json`, SETTINGS.md §2).
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: false)
        return base
            .appendingPathComponent("LogicalSapien", isDirectory: true)
            .appendingPathComponent("MSIMonitorControl", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    // MARK: Load (never-block fallback, SETTINGS.md §4)

    /// The outcome of a load, so callers can log/diagnose without the loader ever
    /// throwing in the normal case. `loadedWithRepairs` means the file parsed but we
    /// dropped malformed bindings / duplicates / a bad AltGr list (SETTINGS.md §4).
    public enum LoadOutcome: Equatable {
        case loadedFromFile
        case loadedWithRepairs([String])  // human-readable notes on what was repaired
        case wroteDefault                 // file was missing → defaults written
        case usedDefaultsInMemory         // file malformed or newer-version → kept file, ran on defaults
    }

    /// Loads the config, applying the never-block rules (SETTINGS.md §4):
    /// 1. missing → write defaults, return them;
    /// 2. valid & current version → use it (per-field-resilient: a single malformed
    ///    binding/chord is dropped, a missing/bad altGrAvoidList falls back to the
    ///    built-in default, the rest loads);
    /// 3. malformed JSON (not a single bad field — the whole document) or a newer
    ///    schemaVersion → ignore the file (do NOT overwrite it), return defaults.
    /// On load, duplicate chords are also resolved (§3.5): the FIRST binding of a
    /// chord wins; later duplicates are dropped (and noted).
    @discardableResult
    public static func load(from url: URL? = nil,
                            fileManager: FileManager = .default) -> (config: HotkeyConfig, outcome: LoadOutcome) {
        let fileURL: URL
        do {
            fileURL = try url ?? defaultURL(fileManager: fileManager)
        } catch {
            return (makeDefault(), .usedDefaultsInMemory)
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            let def = makeDefault()
            try? def.save(to: fileURL, fileManager: fileManager)
            return (def, .wroteDefault)
        }

        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not even a JSON object → defaults, keep the file untouched.
            return (makeDefault(), .usedDefaultsInMemory)
        }

        // Newer schemaVersion → preserve the file, run on defaults.
        if let v = object["schemaVersion"] as? Int, v > kHotkeyConfigSchemaVersion {
            return (makeDefault(), .usedDefaultsInMemory)
        }

        // Per-field-resilient parse from the loosely-typed object.
        var repairs: [String] = []
        var config = decodeResilient(from: object, repairs: &repairs)

        // Validate-on-load: drop duplicate chords, first-wins (§3.5).
        let dupNotes = config.resolveDuplicatesOnLoad()
        repairs.append(contentsOf: dupNotes)

        return (config, repairs.isEmpty ? .loadedFromFile : .loadedWithRepairs(repairs))
    }

    /// Builds a config from a loosely-typed JSON object, dropping individual bad
    /// fields rather than failing the whole load. Anything missing/invalid falls
    /// back to the built-in default for that field.
    private static func decodeResilient(from object: [String: Any],
                                        repairs: inout [String]) -> HotkeyConfig {
        let def = makeDefault()

        let schemaVersion = object["schemaVersion"] as? Int ?? kHotkeyConfigSchemaVersion
        let preset = (object["preset"] as? String).flatMap(HotkeyPreset.init(rawValue:)) ?? def.preset
        let launchAtLogin = object["launchAtLogin"] as? Bool ?? def.launchAtLogin

        // Bindings: decode each chord independently; drop the malformed ones.
        var bindings: [String: [HotkeyChord]] = [:]
        if let rawBindings = object["bindings"] as? [String: Any] {
            for (actionId, value) in rawBindings {
                guard let chordArray = value as? [Any] else {
                    repairs.append("Dropped malformed bindings for '\(actionId)'.")
                    bindings[actionId] = []
                    continue
                }
                var chords: [HotkeyChord] = []
                for entry in chordArray {
                    if let chord = chordFromAny(entry) {
                        chords.append(chord)
                    } else {
                        repairs.append("Dropped an invalid chord in '\(actionId)'.")
                    }
                }
                bindings[actionId] = chords
            }
        } else {
            repairs.append("Missing or malformed 'bindings' — using defaults.")
            bindings = def.bindings
        }
        // Ensure every known command has an entry (so the UI/registrar are complete).
        for command in Command.allCases where bindings[command.actionId] == nil {
            bindings[command.actionId] = []
        }

        // AltGr list: fall back to the built-in default if missing/malformed/empty.
        var altGr = AltGrAvoidList.builtIn
        if let rawAltGr = object["altGrAvoidList"] as? [String: Any] {
            let keys = (rawAltGr["keys"] as? [String])?.filter { HotkeyChord.isValidKey($0.uppercased()) }
                .map { $0.uppercased() } ?? []
            if keys.isEmpty {
                repairs.append("Empty/invalid altGrAvoidList — using built-in default.")
            } else {
                let note = rawAltGr["note"] as? String ?? AltGrAvoidList.builtIn.note
                altGr = AltGrAvoidList(keys: keys, note: note)
            }
        } else if object["altGrAvoidList"] != nil {
            repairs.append("Malformed altGrAvoidList — using built-in default.")
        }

        return HotkeyConfig(schemaVersion: schemaVersion, preset: preset,
                            launchAtLogin: launchAtLogin, bindings: bindings,
                            altGrAvoidList: altGr)
    }

    /// Parses one chord from a loosely-typed JSON value, returning nil if invalid.
    private static func chordFromAny(_ value: Any) -> HotkeyChord? {
        guard let dict = value as? [String: Any],
              let rawMods = dict["mods"] as? [String],
              let rawKey = (dict["key"] as? String)?.uppercased(),
              HotkeyChord.isValidKey(rawKey) else { return nil }
        var mods: Set<HotkeyModifier> = []
        for token in rawMods {
            switch token {
            case "control":       mods.insert(.control)
            case "option", "alt": mods.insert(.option)
            case "shift":         mods.insert(.shift)
            case "command":       mods.insert(.command)
            default:              return nil   // unknown token → invalid chord
            }
        }
        guard !mods.isEmpty else { return nil }  // a modifier-less global chord is invalid
        return HotkeyChord(mods: mods, key: rawKey)
    }

    /// Removes duplicate chords across actions, keeping the first occurrence
    /// (deterministic by sorted actionId then array order). Returns repair notes.
    @discardableResult
    public mutating func resolveDuplicatesOnLoad() -> [String] {
        var seen: Set<HotkeyChord> = []
        var notes: [String] = []
        for actionId in bindings.keys.sorted() {
            guard var chords = bindings[actionId] else { continue }
            var kept: [HotkeyChord] = []
            for chord in chords {
                if seen.contains(chord) {
                    notes.append("Dropped duplicate chord \(chord.display) from '\(actionId)'.")
                } else {
                    seen.insert(chord)
                    kept.append(chord)
                }
            }
            chords = kept
            bindings[actionId] = chords
        }
        return notes
    }

    // MARK: Save (atomic + canonical, SETTINGS.md §3.8)

    /// Writes the config atomically (`Data.write(.atomic)` = temp-write + rename),
    /// creating the vendor/app directory if needed. Output is the CANONICAL byte
    /// layout (SETTINGS.md §3.8) so the macOS and Windows apps emit byte-identical
    /// files for the same model (both target the one shared fixture).
    public func save(to url: URL? = nil, fileManager: FileManager = .default) throws {
        let fileURL = try url ?? Self.defaultURL(fileManager: fileManager)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try jsonData().write(to: fileURL, options: .atomic)
    }

    /// The CANONICAL JSON encoding (SETTINGS.md §3.8). Hand-rolled — NOT stock
    /// `JSONEncoder` — because the canonical separator is `": "` (no leading space),
    /// which `JSONEncoder.prettyPrinted` cannot emit (it forces `" : "`), and the key
    /// order is fixed (non-alphabetical). The Windows app emits the exact same bytes
    /// via a custom `Utf8JsonWriter`. Format:
    /// - UTF-8, no BOM; 2-space indent; one key per line; separator `": "`.
    /// - Top-level order: schemaVersion, preset, launchAtLogin, bindings, altGrAvoidList.
    /// - bindings in §3.6 actionId order; each chord = `mods` then `key`.
    /// - `mods` is MULTI-LINE (one element per line); empty bindings are `[]`.
    /// - Exactly one trailing newline.
    public func jsonData() throws -> Data {
        var out = ""
        out += "{\n"
        let i1 = "  ", i2 = "    ", i3 = "      ", i4 = "        ", i5 = "          "

        // schemaVersion, preset, launchAtLogin
        out += "\(i1)\"schemaVersion\": \(schemaVersion),\n"
        out += "\(i1)\"preset\": \(Self.jsonString(preset.rawValue)),\n"
        out += "\(i1)\"launchAtLogin\": \(launchAtLogin ? "true" : "false"),\n"

        // bindings — fixed actionId order (SETTINGS.md §3.6). This is the CONTRACT
        // order, deliberately NOT `Command.allCases` (whose enum-declaration order
        // differs). Both apps must emit this exact sequence.
        out += "\(i1)\"bindings\": {\n"
        let orderedActions = Self.canonicalActionOrder
        // Guard: include any action ids present in the model but not in the canonical
        // list (none today) so nothing is silently dropped.
        let extra = bindings.keys.filter { !orderedActions.contains($0) }.sorted()
        let actionOrder = orderedActions + extra
        for (ai, actionId) in actionOrder.enumerated() {
            let chords = bindings[actionId] ?? []
            let actionComma = ai == actionOrder.count - 1 ? "" : ","
            if chords.isEmpty {
                out += "\(i2)\(Self.jsonString(actionId)): []\(actionComma)\n"
                continue
            }
            out += "\(i2)\(Self.jsonString(actionId)): [\n"
            for (ci, chord) in chords.enumerated() {
                let chordComma = ci == chords.count - 1 ? "" : ","
                out += "\(i3){\n"
                // mods — multi-line, canonical order ⌃ ⌥ ⇧ ⌘.
                out += "\(i4)\"mods\": [\n"
                let order: [HotkeyModifier] = [.control, .option, .shift, .command]
                let mods = order.filter { chord.mods.contains($0) }
                for (mi, mod) in mods.enumerated() {
                    let modComma = mi == mods.count - 1 ? "" : ","
                    out += "\(i5)\(Self.jsonString(mod.rawValue))\(modComma)\n"
                }
                out += "\(i4)],\n"
                out += "\(i4)\"key\": \(Self.jsonString(chord.key))\n"
                out += "\(i3)}\(chordComma)\n"
            }
            out += "\(i2)]\(actionComma)\n"
        }
        out += "\(i1)},\n"

        // altGrAvoidList — keys (multi-line) then note.
        out += "\(i1)\"altGrAvoidList\": {\n"
        out += "\(i2)\"keys\": [\n"
        for (ki, key) in altGrAvoidList.keys.enumerated() {
            let keyComma = ki == altGrAvoidList.keys.count - 1 ? "" : ","
            out += "\(i3)\(Self.jsonString(key))\(keyComma)\n"
        }
        out += "\(i2)],\n"
        out += "\(i2)\"note\": \(Self.jsonString(altGrAvoidList.note))\n"
        out += "\(i1)}\n"

        out += "}\n"   // closing brace + single trailing newline
        return Data(out.utf8)
    }

    /// Minimal JSON string escaper for the canonical writer. Escapes the characters
    /// JSON requires (`"`, `\`, control chars); does NOT escape `/` (forward slash
    /// is legal unescaped and both apps emit it raw). Our data is ASCII, so no
    /// non-ASCII handling is needed.
    private static func jsonString(_ s: String) -> String {
        var r = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            default:
                if ch.value < 0x20 {
                    r += String(format: "\\u%04x", ch.value)
                } else {
                    r.unicodeScalars.append(ch)
                }
            }
        }
        r += "\""
        return r
    }

    // MARK: Validation (SETTINGS.md §3.5)

    public enum ValidationIssue: Equatable {
        /// The chord is already bound to `existingActionId` (BLOCKING).
        case duplicate(existingActionId: String)
        /// Advisory: the key may carry an AltGr-composed char on EU layouts when
        /// combined with option/alt (NON-BLOCKING).
        case altGrWarning(key: String)
    }

    /// Checks a proposed chord for a given action against the current bindings.
    /// Returns all issues; callers BLOCK on `.duplicate` and merely warn on
    /// `.altGrWarning`. OS-reserved conflicts are NOT checked here — they are the
    /// registrar's responsibility (the OS register call is the authority, §3.5).
    public func validate(chord: HotkeyChord, forAction actionId: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Duplicate: same mods-set + key bound to a DIFFERENT action.
        for (otherAction, chords) in bindings where otherAction != actionId {
            if chords.contains(chord) {
                issues.append(.duplicate(existingActionId: otherAction))
                break
            }
        }

        // AltGr advisory: key in the avoid-list AND chord uses option/alt.
        if chord.mods.contains(.option),
           altGrAvoidList.keys.contains(where: { $0.uppercased() == chord.key }) {
            issues.append(.altGrWarning(key: chord.key))
        }
        return issues
    }

    // MARK: Commit decision (try-first / rollback, SETTINGS.md §3.5/§5)

    /// The decision a settings store should make after attempting to register a
    /// candidate config with the OS. Pure + testable: it does NOT touch the OS — the
    /// caller performs the registration and feeds the rejected action ids in.
    public enum CommitDecision: Equatable {
        /// OS accepted every chord: persist `candidate` and make it live.
        case commit(HotkeyConfig)
        /// OS rejected some chords: keep `previous` live (re-register it), do NOT
        /// persist, and surface `rejectedActions` as conflicts.
        case rollback(previous: HotkeyConfig, rejectedActions: [String])
    }

    /// Decides commit-vs-rollback from the OS registration result. A non-empty
    /// `rejectedActions` means the candidate must be rolled back so the user is never
    /// left with no working hotkeys (the previously-good config stays live).
    public static func decideCommit(previous: HotkeyConfig,
                                    candidate: HotkeyConfig,
                                    rejectedActions: [String]) -> CommitDecision {
        if rejectedActions.isEmpty {
            return .commit(candidate)
        } else {
            return .rollback(previous: previous, rejectedActions: rejectedActions)
        }
    }

    // MARK: Preset application (apply-and-bake, SETTINGS.md §3.2)

    /// Rewrites every binding's modifiers to the given preset's mods and records the
    /// preset label. `custom` is a no-op (it has no canonical mods). Keys are kept.
    public mutating func applyPreset(_ newPreset: HotkeyPreset) {
        guard let mods = newPreset.macModifiers else { return }
        for (action, chords) in bindings {
            bindings[action] = chords.map { HotkeyChord(mods: mods, key: $0.key) }
        }
        preset = newPreset
    }

    /// Returns the named preset whose mods every non-empty binding matches, or
    /// `.custom` if they diverge. Used to keep the `preset` label honest after a
    /// hand-edit.
    public func inferredPreset() -> HotkeyPreset {
        let allMods = bindings.values.flatMap { $0 }.map { $0.mods }
        guard !allMods.isEmpty else { return preset }   // nothing bound → keep label
        for candidate in [HotkeyPreset.cmdShiftCtrl, .ctrlShift, .legacy] {
            if let m = candidate.macModifiers, allMods.allSatisfy({ $0 == m }) {
                return candidate
            }
        }
        return .custom
    }
}

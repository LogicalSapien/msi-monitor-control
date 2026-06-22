using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MsiMonitorControl;

/// <summary>
/// The named preset schemes for the global-hotkey modifiers (see docs/SETTINGS.md §3.2).
/// A preset is a <b>label</b>, not a runtime authority: at runtime the app reads the
/// explicit per-binding modifiers only. Selecting a preset bakes its modifiers into every
/// binding; any hand-edit that diverges flips the preset to <see cref="Custom"/>.
/// </summary>
public enum HotkeyPreset
{
    Hyper,
    CtrlShift,
    Legacy,
    Custom,
}

/// <summary>
/// One key chord: a set of canonical modifier tokens plus a single base key. Mirrors the
/// shared JSON schema (docs/SETTINGS.md §3.3). Modifier order is not significant — chords
/// are compared as a set. An empty <see cref="Mods"/> is never produced by a preset and is
/// rejected by the conflict rules (a modifier-less global hotkey is too collision-prone).
/// </summary>
public sealed class Chord
{
    [JsonPropertyName("mods")]
    public List<string> Mods { get; set; } = new();

    [JsonPropertyName("key")]
    public string Key { get; set; } = "";

    public Chord() { }

    public Chord(IEnumerable<string> mods, string key)
    {
        Mods = mods.ToList();
        Key  = key;
    }

    /// <summary>The mods as a case-insensitive set, with <c>option</c>→<c>alt</c> folded.</summary>
    [JsonIgnore]
    public HashSet<string> ModSet =>
        Mods.Select(HotkeyConfig.NormaliseModifier)
            .Where(m => m.Length > 0)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    /// <summary>True when two chords address the same physical combination (set-equal mods + same key).</summary>
    public bool Matches(Chord other) =>
        string.Equals(Key, other.Key, StringComparison.OrdinalIgnoreCase)
        && ModSet.SetEquals(other.ModSet);
}

/// <summary>
/// Advisory data for the EU-layout / AltGr warning (docs/SETTINGS.md §3.5). Shipped in the
/// config so it can be tuned without an app rebuild; falls back to the built-in default
/// list when missing or malformed.
/// </summary>
public sealed class AltGrAvoidList
{
    [JsonPropertyName("keys")]
    public List<string> Keys { get; set; } = new();

    [JsonPropertyName("note")]
    public string Note { get; set; } = "";

    public static AltGrAvoidList Default() => new()
    {
        Keys = new List<string> { "Q", "E", "B", "7", "2", "3", "4", "5", "8", "9", "0" },
        Note = "Letters/digits that commonly carry an AltGr-composed char on EU layouts "
             + "(e.g. @, EUR, {, }, [, ], accented vowels). Advisory only.",
    };
}

/// <summary>
/// The outcome of validating a candidate chord against the live config (docs/SETTINGS.md §3.5).
/// OS-reserved detection happens at registration time (RegisterHotKey returns false) and is
/// surfaced by <see cref="HotKeys"/>, not here.
/// </summary>
public sealed class ChordValidation
{
    /// <summary>BLOCKING: the chord is already bound to this action (its <c>actionId</c>). Null = no clash.</summary>
    public string? DuplicateActionId { get; init; }

    /// <summary>NON-BLOCKING: the chord may collide with an AltGr-composed character on some EU layouts.</summary>
    public bool AltGrWarning { get; init; }

    /// <summary>True when the chord may be committed (no blocking problem).</summary>
    public bool IsValid => DuplicateActionId is null;
}

/// <summary>
/// The shared, persisted hotkey configuration — the Windows half of the cross-platform
/// contract in <c>docs/SETTINGS.md</c>. Owns load/save (atomic), the in-memory model,
/// the fallback rules (§4), validation (§3.5), and the derived display string (§3.7).
///
/// A config written by the macOS app loads byte-identically here under the
/// <c>hyper</c>/<c>ctrlShift</c> presets; only <c>legacy</c> differs per platform (macOS
/// stores a <c>command</c> modifier that does not exist on Windows — it is dropped on load
/// with a log, never an error).
/// </summary>
public sealed class HotkeyConfig
{
    /// <summary>The schema version this build understands. Bumped on any breaking change.</summary>
    public const int CurrentSchemaVersion = 1;

    // -- Canonical modifier tokens (docs/SETTINGS.md §3.4) --------------------
    public const string ModControl = "control";
    public const string ModAlt     = "alt";      // Windows-native spelling; "option" is a read synonym
    public const string ModOption  = "option";   // macOS spelling — accepted on read, normalised to "alt"
    public const string ModShift   = "shift";
    public const string ModCommand = "command";  // macOS only — dropped on Windows with a log

    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = CurrentSchemaVersion;

    // Serialised as a lower-camelCase string ("hyper"/"ctrlShift"/"legacy"/"custom") via the
    // options-level JsonStringEnumConverter(CamelCase); no per-property attribute needed.
    [JsonPropertyName("preset")]
    public HotkeyPreset Preset { get; set; } = HotkeyPreset.Hyper;

    [JsonPropertyName("launchAtLogin")]
    public bool LaunchAtLogin { get; set; }

    /// <summary>Map of <c>actionId</c> → list of chords. An empty list means "no hotkey".</summary>
    [JsonPropertyName("bindings")]
    public Dictionary<string, List<Chord>> Bindings { get; set; } = new();

    [JsonPropertyName("altGrAvoidList")]
    public AltGrAvoidList AltGrAvoidList { get; set; } = MsiMonitorControl.AltGrAvoidList.Default();

    // ------------------------------------------------------------------------
    // Paths (docs/SETTINGS.md §2) — vendor-nested under LogicalSapien.
    // ------------------------------------------------------------------------

    /// <summary>Vendor folder name (the parent of the app folder). Matches macOS.</summary>
    public const string VendorFolder = "LogicalSapien";

    /// <summary>App folder name (under the vendor folder). Matches macOS.</summary>
    public const string AppFolder = "MSIMonitorControl";

    /// <summary>
    /// The config directory: <c>%APPDATA%\LogicalSapien\MSIMonitorControl</c>.
    /// </summary>
    public static string ConfigDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            VendorFolder,
            AppFolder);

    /// <summary>The config file: <c>…\settings.json</c>.</summary>
    public static string ConfigPath => Path.Combine(ConfigDirectory, "settings.json");

    private static readonly JsonSerializerOptions SerialiserOptions = new()
    {
        WriteIndented = true,
        // Match the §3.8 canonical escaping (unescaped `/ @ { } [ ]`) — required for the
        // byte-identical fixture. STJ writes LF + `": "` + 2-space indent deterministically.
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        // We emit lower-camelCase enum values ("hyper", "ctrlShift", "legacy", "custom")
        // to match the shared schema and the macOS Codable output.
        Converters =
        {
            new JsonStringEnumConverter(JsonNamingPolicy.CamelCase),
            // Defensive bindings reader (per-field resilience, §4) + deterministic ordered writer
            // emitting the cross-platform `option` modifier spelling.
            new BindingsConverter(),
        },
    };

    /// <summary>
    /// Canonical modifier write-order, matching the macOS encoder
    /// (<c>control, option/alt, shift, command</c>) so both apps emit diff-friendly,
    /// consistently-ordered <c>mods</c> arrays. Used to sort a chord's mods on write.
    /// </summary>
    internal static readonly string[] CanonicalModOrder = { ModControl, ModAlt, ModShift, ModCommand };

    /// <summary>Returns a chord's mods in canonical order (for stable serialisation).</summary>
    internal static List<string> SortMods(IEnumerable<string> mods)
    {
        var set = mods.Select(NormaliseModifier).Where(m => m.Length > 0)
                      .ToHashSet(StringComparer.OrdinalIgnoreCase);
        return CanonicalModOrder.Where(set.Contains).ToList();
    }

    // ------------------------------------------------------------------------
    // Modifier normalisation (docs/SETTINGS.md §3.4)
    // ------------------------------------------------------------------------

    /// <summary>
    /// Folds a modifier token to its canonical Windows spelling: <c>option</c> → <c>alt</c>
    /// (synonyms), trims and lower-cases. Returns an empty string for an unknown token (the
    /// caller drops it). <c>command</c> is returned as-is so the loader can detect-and-drop it
    /// with a specific log message.
    /// </summary>
    public static string NormaliseModifier(string token)
    {
        var t = (token ?? "").Trim().ToLowerInvariant();
        return t switch
        {
            ModControl => ModControl,
            ModAlt     => ModAlt,
            ModOption  => ModAlt,   // synonym
            ModShift   => ModShift,
            ModCommand => ModCommand, // surfaced to the loader, which drops it with a log
            _          => "",        // unknown → dropped
        };
    }

    // ------------------------------------------------------------------------
    // Presets (docs/SETTINGS.md §3.2)
    // ------------------------------------------------------------------------

    /// <summary>
    /// The Windows modifier set baked when a preset is applied. <c>legacy</c> on Windows is
    /// Ctrl+Alt (no <c>command</c> — that exists only on macOS). <c>custom</c> is never applied
    /// directly (it is set automatically when bindings diverge), so it has no canonical mods.
    /// </summary>
    public static IReadOnlyList<string> ModifiersForPreset(HotkeyPreset preset) => preset switch
    {
        HotkeyPreset.Hyper     => new[] { ModControl, ModAlt, ModShift },
        HotkeyPreset.CtrlShift => new[] { ModControl, ModShift },
        HotkeyPreset.Legacy    => new[] { ModControl, ModAlt },
        _                      => Array.Empty<string>(),
    };

    /// <summary>
    /// Apply-and-bake (docs/SETTINGS.md §3.2): rewrite every non-empty binding's mods to the
    /// preset's scheme and record the preset label. Empty bindings (no chord) stay empty.
    /// </summary>
    public void ApplyPreset(HotkeyPreset preset)
    {
        if (preset == HotkeyPreset.Custom) return; // not applied directly

        var mods = SortMods(ModifiersForPreset(preset));
        foreach (var chords in Bindings.Values)
            foreach (var chord in chords)
                chord.Mods = new List<string>(mods);

        Preset = preset;
    }

    /// <summary>
    /// Returns the preset whose Windows modifiers every non-empty binding currently matches,
    /// or <see cref="HotkeyPreset.Custom"/> if they diverge (or differ from each other). Used
    /// to re-derive the dropdown label after a hand-edit.
    /// </summary>
    public HotkeyPreset DerivePreset()
    {
        var nonEmpty = Bindings.Values.SelectMany(c => c).ToList();
        if (nonEmpty.Count == 0) return Preset; // nothing bound — keep the recorded label

        foreach (var preset in new[] { HotkeyPreset.Hyper, HotkeyPreset.CtrlShift, HotkeyPreset.Legacy })
        {
            var wanted = ModifiersForPreset(preset).ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (nonEmpty.All(c => c.ModSet.SetEquals(wanted)))
                return preset;
        }
        return HotkeyPreset.Custom;
    }

    // ------------------------------------------------------------------------
    // Defaults (docs/SETTINGS.md §3.6, §7)
    // ------------------------------------------------------------------------

    /// <summary>
    /// The built-in default config: preset <c>hyper</c>, the four available actions bound to
    /// their default keys, the three UNKNOWN-payload actions left with an empty array (no
    /// chord until reverse-engineered), <c>launchAtLogin</c> false, the built-in AltGr list.
    /// </summary>
    public static HotkeyConfig Default()
    {
        var hyper = ModifiersForPreset(HotkeyPreset.Hyper).ToList();
        Chord Bound(string key) => new(hyper, key);

        return new HotkeyConfig
        {
            SchemaVersion  = CurrentSchemaVersion,
            Preset         = HotkeyPreset.Hyper,
            LaunchAtLogin  = false,
            Bindings = new Dictionary<string, List<Chord>>
            {
                ["inputTypeC"]  = new() { Bound("C") },
                ["inputDP"]     = new() { Bound("D") },
                ["kvmUSBC"]     = new() { Bound("K") },
                ["kvmUpstream"] = new() { Bound("U") },
                ["kvmAuto"]     = new(),   // empty: payload UNKNOWN → no chord
                ["pbpOn"]       = new(),   // empty: payload UNKNOWN → no chord
                ["pbpOff"]      = new(),   // empty: payload UNKNOWN → no chord
            },
            AltGrAvoidList = MsiMonitorControl.AltGrAvoidList.Default(),
        };
    }

    // ------------------------------------------------------------------------
    // Load / fallback (docs/SETTINGS.md §4)
    // ------------------------------------------------------------------------

    /// <summary>
    /// Loads the config from <see cref="ConfigPath"/>, applying the fallback rules (§4):
    /// <list type="number">
    /// <item>File missing → create the directory, write the built-in default, run with it.</item>
    /// <item>Present, parses, same schemaVersion → use it (after per-field sanitisation).</item>
    /// <item>Malformed JSON, or schemaVersion &gt; current → log, ignore the file, run on
    ///   in-memory defaults, and DO NOT overwrite the user's file.</item>
    /// </list>
    /// Never throws for a bad config — the app must always start with working hotkeys.
    /// </summary>
    public static HotkeyConfig Load()
    {
        string path = ConfigPath;

        if (!File.Exists(path))
        {
            var fresh = Default();
            try
            {
                fresh.Save();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[HotkeyConfig] Could not write default config to {path}: {ex.Message}. Running on in-memory defaults.");
            }
            return fresh;
        }

        string raw;
        try
        {
            raw = File.ReadAllText(path);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[HotkeyConfig] Could not read {path}: {ex.Message}. Running on in-memory defaults (file left untouched).");
            return Default();
        }

        return Parse(raw, overwriteOnRepair: false, repaired: out _);
    }

    /// <summary>
    /// File-based load against an explicit path, applying the same fallback rules as
    /// <see cref="Load"/>. Exposed so tests (and any future alternate location) can exercise
    /// the missing/malformed/newer-version branches on a temp file without touching
    /// <c>%APPDATA%</c>. On a missing file it writes the default to <paramref name="path"/>;
    /// on malformed JSON or a newer schemaVersion it returns in-memory defaults and leaves the
    /// file untouched.
    /// </summary>
    public static HotkeyConfig LoadFrom(string path)
    {
        if (!File.Exists(path))
        {
            var fresh = Default();
            try
            {
                fresh.SaveTo(path);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[HotkeyConfig] Could not write default config to {path}: {ex.Message}. Running on in-memory defaults.");
            }
            return fresh;
        }

        string raw;
        try
        {
            raw = File.ReadAllText(path);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[HotkeyConfig] Could not read {path}: {ex.Message}. Running on in-memory defaults (file left untouched).");
            return Default();
        }

        return Parse(raw, overwriteOnRepair: false, repaired: out _);
    }

    /// <summary>
    /// Parses raw JSON applying the fallback rules. Exposed for tests. On malformed JSON or a
    /// newer schemaVersion, returns in-memory defaults and never signals a repair-write
    /// (the caller must not overwrite the file). On a parse that succeeds but needed per-field
    /// sanitisation (a dropped chord, a dropped <c>command</c> modifier), <paramref name="repaired"/>
    /// is set true so a caller MAY choose to persist the cleaned form.
    /// </summary>
    public static HotkeyConfig Parse(string raw, bool overwriteOnRepair, out bool repaired)
    {
        repaired = false;

        HotkeyConfig? parsed;
        try
        {
            parsed = JsonSerializer.Deserialize<HotkeyConfig>(raw, SerialiserOptions);
        }
        catch (JsonException ex)
        {
            Debug.WriteLine($"[HotkeyConfig] Malformed config JSON: {ex.Message}. Ignoring file, running on in-memory defaults (file left untouched).");
            return Default();
        }

        if (parsed is null)
        {
            Debug.WriteLine("[HotkeyConfig] Config parsed to null. Ignoring file, running on in-memory defaults (file left untouched).");
            return Default();
        }

        if (parsed.SchemaVersion > CurrentSchemaVersion)
        {
            Debug.WriteLine($"[HotkeyConfig] Config schemaVersion {parsed.SchemaVersion} is newer than this app ({CurrentSchemaVersion}). " +
                            "Ignoring file, running on in-memory defaults (file left untouched).");
            return Default();
        }

        // schemaVersion < current cannot happen yet (only version 1 exists). When a v2 lands,
        // the migration rule (§4.4) is read-old → fill-new-from-defaults → rewrite-at-current.

        parsed.Sanitise(ref repaired);
        return parsed;
    }

    /// <summary>
    /// Per-field resilience (docs/SETTINGS.md §4): fill missing fields from defaults, drop
    /// malformed binding entries (with a log), and drop a <c>command</c> modifier on Windows
    /// (with a log) — never error. Sets <paramref name="repaired"/> true if anything was dropped.
    /// </summary>
    private void Sanitise(ref bool repaired)
    {
        // Bindings: ensure every known actionId exists; sanitise each chord.
        Bindings ??= new();

        foreach (var actionId in Bindings.Keys.ToList())
        {
            var chords = Bindings[actionId];
            if (chords is null)
            {
                Bindings[actionId] = new();
                repaired = true;
                Debug.WriteLine($"[HotkeyConfig] Null chord list for '{actionId}' — treated as no chord.");
                continue;
            }

            var cleaned = new List<Chord>();
            foreach (var chord in chords)
            {
                if (chord is null || string.IsNullOrWhiteSpace(chord.Key))
                {
                    repaired = true;
                    Debug.WriteLine($"[HotkeyConfig] Dropped a malformed chord for '{actionId}' (missing key).");
                    continue;
                }

                var hadCommand = chord.Mods.Any(m =>
                    string.Equals(NormaliseModifier(m), ModCommand, StringComparison.OrdinalIgnoreCase));

                // Normalise mods to canonical Windows spellings, dropping command + unknowns.
                var mods = new List<string>();
                foreach (var token in chord.Mods)
                {
                    var norm = NormaliseModifier(token);
                    if (norm.Length == 0)
                    {
                        repaired = true;
                        Debug.WriteLine($"[HotkeyConfig] Dropped unknown modifier '{token}' for '{actionId}'.");
                        continue;
                    }
                    if (norm == ModCommand)
                    {
                        repaired = true;
                        Debug.WriteLine($"[HotkeyConfig] Dropped 'command' modifier for '{actionId}' — not supported on Windows.");
                        continue;
                    }
                    if (!mods.Contains(norm))
                        mods.Add(norm);
                }

                // A modifier-less global hotkey is rejected (too collision-prone — §3.3/§3.5).
                // This also covers a mac legacy chord that was *only* command.
                if (mods.Count == 0)
                {
                    repaired = true;
                    Debug.WriteLine($"[HotkeyConfig] Dropped a modifier-less chord for '{actionId}' (not a valid global hotkey).");
                    continue;
                }

                // The base key must be one of the v0.2.0 allowed values (A–Z, 0–9). Anything
                // else (function key, symbol, multi-char) is rejected on load rather than left
                // in app state to be silently skipped by the registrar (§3.4/§5).
                var key = chord.Key.Trim().ToUpperInvariant();
                if (!IsValidBaseKey(key))
                {
                    repaired = true;
                    Debug.WriteLine($"[HotkeyConfig] Dropped a chord for '{actionId}' with unsupported base key '{chord.Key}'.");
                    continue;
                }

                // Store mods in canonical order (matches the macOS encoder) for stable output.
                cleaned.Add(new Chord(SortMods(mods), key));
            }

            Bindings[actionId] = cleaned;
        }

        // Duplicate detection on load (§3.5 check 1 — BLOCKING). A hand-edited file can bind the
        // same chord to two actions; the OS would let only the first RegisterHotKey win and the
        // second would silently fail. Drop the later duplicate(s) here so app state is clean and
        // the conflict is logged rather than discovered as a mystery non-firing hotkey.
        DropDuplicateChords(ref repaired);

        // AltGr list: fall back to the built-in default if missing/empty/malformed.
        if (AltGrAvoidList is null || AltGrAvoidList.Keys is null || AltGrAvoidList.Keys.Count == 0)
        {
            AltGrAvoidList = MsiMonitorControl.AltGrAvoidList.Default();
            repaired = true;
            Debug.WriteLine("[HotkeyConfig] Missing/empty altGrAvoidList — using built-in default list.");
        }
    }

    /// <summary>True when <paramref name="key"/> is a v0.2.0-allowed base key (single A–Z or 0–9).</summary>
    public static bool IsValidBaseKey(string key)
    {
        if (string.IsNullOrEmpty(key) || key.Length != 1) return false;
        char c = char.ToUpperInvariant(key[0]);
        return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
    }

    /// <summary>
    /// Removes any chord that duplicates an already-seen chord (same mods-set + key), keeping the
    /// first occurrence. Iterates actions/chords in a stable order so the "winner" is deterministic.
    /// </summary>
    private void DropDuplicateChords(ref bool repaired)
    {
        var seen = new List<(string ActionId, Chord Chord)>();

        foreach (var actionId in Bindings.Keys.ToList())
        {
            var kept = new List<Chord>();
            foreach (var chord in Bindings[actionId])
            {
                var clash = seen.FirstOrDefault(s => s.Chord.Matches(chord));
                if (clash.Chord is not null)
                {
                    repaired = true;
                    Debug.WriteLine($"[HotkeyConfig] Dropped duplicate chord '{DisplayString(chord)}' on '{actionId}' " +
                                    $"(already bound to '{clash.ActionId}').");
                    continue;
                }
                seen.Add((actionId, chord));
                kept.Add(chord);
            }
            Bindings[actionId] = kept;
        }
    }

    // ------------------------------------------------------------------------
    // Save (atomic — docs/SETTINGS.md §2)
    // ------------------------------------------------------------------------

    /// <summary>
    /// Writes the config atomically: serialise to <c>settings.json.tmp</c> in the same
    /// directory, then rename over <c>settings.json</c>. A crash mid-write cannot corrupt the
    /// live config. Creates the directory if absent.
    /// </summary>
    public void Save() => SaveTo(ConfigPath);

    /// <summary>
    /// Atomic write to an explicit path (used by <see cref="Save"/> and by tests). Serialises
    /// to <c>&lt;path&gt;.tmp</c> in the same directory, then renames over the target.
    /// </summary>
    public void SaveTo(string path)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        string tmp = path + ".tmp";
        // UTF-8 WITHOUT BOM (matches the macOS encoder; STJ never emits a BOM here anyway).
        File.WriteAllText(tmp, ToJson(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        File.Move(tmp, path, overwrite: true);
    }

    // ------------------------------------------------------------------------
    // Canonical serialisation — BYTE-IDENTICAL across apps (docs/SETTINGS.md §3.8).
    // The shared fixture docs/fixtures/settings.example.json IS the canonical output for the
    // default config (regenerated from the encoders), and `Default().ToJson()` must equal it
    // byte-for-byte. The §3.8 canonical form happens to be STJ-native (`": "` separator,
    // 2-space indent, multi-line scalar arrays, `[]` for empty, LF), so stock System.Text.Json
    // with WriteIndented produces it — we only add the controls STJ lacks:
    //   • UnsafeRelaxedJsonEscaping → unescaped `/ @ { } [ ]` (matches §3.8);
    //   • BindingsConverter → canonical actionId order + `option` modifier spelling + mods/key order;
    //   • a single trailing newline appended here (STJ omits it; §3.8 requires exactly one);
    //   • UTF-8 no BOM (SaveTo).
    // STJ's Utf8 indented writer emits LF on every platform, so output is identical on win/CI.
    // ------------------------------------------------------------------------

    /// <summary>actionId write-order for the bindings map (docs/SETTINGS.md §3.6, §3.8).</summary>
    internal static readonly string[] CanonicalActionOrder =
        { "inputTypeC", "inputDP", "kvmUSBC", "kvmUpstream", "kvmAuto", "pbpOn", "pbpOff" };

    /// <summary>
    /// Serialises this config to its canonical on-disk JSON (docs/SETTINGS.md §3.8) — including
    /// the single trailing newline — so <c>Default().ToJson()</c> equals the shared fixture
    /// byte-for-byte. Stock System.Text.Json gives the §3.8 layout; <see cref="BindingsConverter"/>
    /// drives actionId order + the `option` spelling; the trailing newline is added here.
    /// </summary>
    public string ToJson() => JsonSerializer.Serialize(this, SerialiserOptions) + "\n";

    // ------------------------------------------------------------------------
    // Validation (docs/SETTINGS.md §3.5)
    // ------------------------------------------------------------------------

    /// <summary>
    /// Validates a candidate <paramref name="chord"/> for <paramref name="actionId"/> against
    /// the live config. Checks duplicate (BLOCKING — same chord bound to a different action)
    /// and AltGr (NON-BLOCKING — key in the avoid-list AND mods include alt/option). The third
    /// check, OS-reserved, is enforced at registration time by <see cref="HotKeys"/>.
    /// </summary>
    /// <param name="excludeChordIndex">
    /// When re-validating an existing chord that is being edited in place, pass its index so it
    /// is not treated as a duplicate of itself. Use -1 for a brand-new chord.
    /// </param>
    public ChordValidation ValidateChord(string actionId, Chord chord, int excludeChordIndex = -1)
    {
        string? duplicateOf = null;

        foreach (var (otherAction, chords) in Bindings)
        {
            for (int i = 0; i < chords.Count; i++)
            {
                if (otherAction == actionId && i == excludeChordIndex)
                    continue; // the chord being edited — not a self-clash

                if (chords[i].Matches(chord))
                {
                    duplicateOf = otherAction;
                    break;
                }
            }
            if (duplicateOf is not null) break;
        }

        return new ChordValidation
        {
            DuplicateActionId = duplicateOf,
            AltGrWarning      = IsAltGrRisk(chord),
        };
    }

    /// <summary>
    /// True when the chord could collide with an AltGr-composed character on some EU layouts:
    /// the key is in <see cref="AltGrAvoidList"/> AND the mods include alt/option (§3.5). Never
    /// blocks — advisory only.
    /// </summary>
    public bool IsAltGrRisk(Chord chord)
    {
        var keys = (AltGrAvoidList?.Keys is { Count: > 0 })
            ? AltGrAvoidList.Keys
            : MsiMonitorControl.AltGrAvoidList.Default().Keys;

        bool keyInList = keys.Any(k => string.Equals(k, chord.Key, StringComparison.OrdinalIgnoreCase));
        bool hasAlt    = chord.ModSet.Contains(ModAlt);
        return keyInList && hasAlt;
    }

    // ------------------------------------------------------------------------
    // Derived display string (docs/SETTINGS.md §3.7) — never stored
    // ------------------------------------------------------------------------

    /// <summary>
    /// The human-readable Windows chord text: modifier words joined by <c>+</c> in canonical
    /// order (Ctrl, Alt, Shift), then the key — e.g. <c>Ctrl+Alt+Shift+C</c>. Computed from the
    /// chord, never persisted, so it cannot drift.
    /// </summary>
    public static string DisplayString(Chord chord)
    {
        var parts = new List<string>();
        var set = chord.ModSet;
        if (set.Contains(ModControl)) parts.Add("Ctrl");
        if (set.Contains(ModAlt))     parts.Add("Alt");
        if (set.Contains(ModShift))   parts.Add("Shift");
        // "command" never reaches here on Windows (dropped on load).
        parts.Add(chord.Key.ToUpperInvariant());
        return string.Join("+", parts);
    }

    /// <summary>
    /// The display string for an action's first chord, or an empty string when it has none.
    /// Used by the tray menu (which shows one chord per item).
    /// </summary>
    public string PrimaryDisplay(string actionId) =>
        Bindings.TryGetValue(actionId, out var chords) && chords.Count > 0
            ? DisplayString(chords[0])
            : "";
}

/// <summary>
/// A defensive reader for the <c>bindings</c> map (docs/SETTINGS.md §4 per-field resilience).
/// Each value should be an array of chord objects; a malformed value (not an array), a
/// malformed chord (not an object, missing/non-string key, <c>mods</c> not an array), or a bad
/// modifier token is skipped rather than throwing and sinking the entire config deserialise.
/// Normalisation, ordering, command-dropping, key/duplicate validation all run afterwards in
/// <see cref="HotkeyConfig"/>'s Sanitise step — this converter only guarantees the parse
/// survives a single bad entry. Writing delegates to the default object serialisation.
/// </summary>
internal sealed class BindingsConverter : JsonConverter<Dictionary<string, List<Chord>>>
{
    public override Dictionary<string, List<Chord>> Read(
        ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var result = new Dictionary<string, List<Chord>>();

        if (reader.TokenType == JsonTokenType.Null) return result;
        if (reader.TokenType != JsonTokenType.StartObject)
        {
            reader.Skip();
            return result;
        }

        while (reader.Read())
        {
            if (reader.TokenType == JsonTokenType.EndObject) break;
            if (reader.TokenType != JsonTokenType.PropertyName) { reader.Skip(); continue; }

            string actionId = reader.GetString() ?? "";
            reader.Read();

            var chords = new List<Chord>();
            if (reader.TokenType == JsonTokenType.StartArray)
            {
                while (reader.Read())
                {
                    if (reader.TokenType == JsonTokenType.EndArray) break;
                    var chord = ReadChord(ref reader);
                    if (chord is not null) chords.Add(chord);
                }
            }
            else
            {
                // Not an array (e.g. null or a stray object) — treat as no chord and move on.
                reader.Skip();
            }

            result[actionId] = chords;
        }

        return result;
    }

    /// <summary>Reads one chord object defensively. Returns null (and consumes the value) on any malformity.</summary>
    private static Chord? ReadChord(ref Utf8JsonReader reader)
    {
        if (reader.TokenType != JsonTokenType.StartObject) { reader.Skip(); return null; }

        var mods = new List<string>();
        string? key = null;

        while (reader.Read())
        {
            if (reader.TokenType == JsonTokenType.EndObject) break;
            if (reader.TokenType != JsonTokenType.PropertyName) { reader.Skip(); continue; }

            string prop = reader.GetString() ?? "";
            reader.Read();

            if (prop == "mods")
            {
                if (reader.TokenType == JsonTokenType.StartArray)
                {
                    while (reader.Read())
                    {
                        if (reader.TokenType == JsonTokenType.EndArray) break;
                        if (reader.TokenType == JsonTokenType.String)
                            mods.Add(reader.GetString() ?? "");
                        else
                            reader.Skip(); // non-string modifier token — ignored
                    }
                }
                else
                {
                    reader.Skip(); // mods not an array (e.g. null) — leave empty
                }
            }
            else if (prop == "key")
            {
                key = reader.TokenType == JsonTokenType.String ? reader.GetString() : null;
                if (reader.TokenType != JsonTokenType.String) reader.Skip();
            }
            else
            {
                reader.Skip(); // unknown chord field — ignored (forward-compat)
            }
        }

        // A chord with no key is malformed; Sanitise also drops empty-mods/invalid-key, but we
        // can short-circuit the obviously-broken case here.
        if (string.IsNullOrWhiteSpace(key)) return null;
        return new Chord(mods, key);
    }

    // mods write-order using the cross-platform `option` spelling (we store `alt`; map on write).
    private static readonly (string Stored, string Written)[] ModWriteOrder =
    {
        (HotkeyConfig.ModControl, "control"),
        (HotkeyConfig.ModAlt,     "option"),  // stored "alt" → written "option" (matches macOS/fixture)
        (HotkeyConfig.ModShift,   "shift"),
    };

    public override void Write(
        Utf8JsonWriter writer, Dictionary<string, List<Chord>> value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();

        // Deterministic order: canonical actionIds first (§3.6), then any unknown ids in their
        // stored order so a forward-compat entry is preserved rather than dropped.
        foreach (var actionId in HotkeyConfig.CanonicalActionOrder)
            if (value.TryGetValue(actionId, out var chords))
                WriteEntry(writer, actionId, chords);
        foreach (var (actionId, chords) in value)
            if (!HotkeyConfig.CanonicalActionOrder.Contains(actionId))
                WriteEntry(writer, actionId, chords);

        writer.WriteEndObject();
    }

    private static void WriteEntry(Utf8JsonWriter writer, string actionId, List<Chord> chords)
    {
        writer.WritePropertyName(actionId);
        writer.WriteStartArray();
        foreach (var chord in chords)
        {
            writer.WriteStartObject();
            writer.WritePropertyName("mods");
            writer.WriteStartArray();
            var set = chord.ModSet;
            foreach (var (stored, written) in ModWriteOrder)
                if (set.Contains(stored))
                    writer.WriteStringValue(written);
            writer.WriteEndArray();
            writer.WriteString("key", chord.Key);
            writer.WriteEndObject();
        }
        writer.WriteEndArray();
    }
}

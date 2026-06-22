using System.Text.Json;
using MsiMonitorControl;
using Xunit;

namespace MsiMonitorControl.Tests;

/// <summary>
/// Tests for <see cref="HotkeyConfig"/> — the Windows half of the shared cross-platform
/// settings contract (docs/SETTINGS.md). Covers the §4 fallback rules, §3.5 validation,
/// §3.7 derived display, preset apply/derive, modifier normalisation, and a round-trip
/// against the shared fixture <c>docs/fixtures/settings.example.json</c>.
/// </summary>
public class HotkeyConfigTests
{
    private static Chord Hyper(string key) =>
        new(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModAlt, HotkeyConfig.ModShift }, key);

    // -------------------------------------------------------------------------
    // Round-trip
    // -------------------------------------------------------------------------

    [Fact]
    public void RoundTrip_PreservesDefaultConfig()
    {
        var original = HotkeyConfig.Default();
        var json = original.ToJson();
        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, repaired: out _);

        Assert.Equal(original.SchemaVersion, parsed.SchemaVersion);
        Assert.Equal(original.Preset, parsed.Preset);
        Assert.Equal(original.LaunchAtLogin, parsed.LaunchAtLogin);
        Assert.Equal(original.Bindings.Count, parsed.Bindings.Count);

        foreach (var (actionId, chords) in original.Bindings)
        {
            Assert.True(parsed.Bindings.ContainsKey(actionId));
            var got = parsed.Bindings[actionId];
            Assert.Equal(chords.Count, got.Count);
            for (int i = 0; i < chords.Count; i++)
                Assert.True(chords[i].Matches(got[i]), $"{actionId}[{i}] differs after round-trip");
        }
    }

    // -- Canonical serialisation: BYTE-IDENTICAL across apps (docs/SETTINGS.md §3.8) --
    // The shared fixture IS the canonical default-config output; Default().ToJson() must equal
    // it byte-for-byte. Plus determinism, the `option` spelling, and write→read→same-model.

    [Fact]
    public void DefaultToJson_EqualsSharedFixture_ByteForByte()
    {
        // §3.8: each app asserts default.save() bytes == the fixture bytes. This is the cross-app
        // canonical-format proof on the Windows side.
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures", "settings.example.json");
        Assert.True(File.Exists(path), $"Fixture not copied to output: {path}");

        var expected = File.ReadAllText(path);
        var actual = HotkeyConfig.Default().ToJson();

        Assert.Equal(expected, actual);
    }

    [Fact]
    public void ToJson_IsDeterministic()
    {
        // §3.8: same model → same bytes every time (stable diffs).
        var a = HotkeyConfig.Default().ToJson();
        var b = HotkeyConfig.Default().ToJson();
        Assert.Equal(a, b);
    }

    [Fact]
    public void ToJson_EndsWithExactlyOneTrailingNewline()
    {
        var json = HotkeyConfig.Default().ToJson();
        Assert.EndsWith("}\n", json);
        Assert.False(json.EndsWith("}\n\n"), "must be exactly one trailing newline");
    }

    [Fact]
    public void Default_WrittenJson_UsesOptionSpelling_NotAlt()
    {
        // The hyper default must WRITE "option" (the §3.8 canonical token), even though we
        // store/compare it as "alt" internally (read as a synonym).
        var json = HotkeyConfig.Default().ToJson();
        Assert.Contains("\"option\"", json);
        Assert.DoesNotContain("\"alt\"", json);
    }

    [Fact]
    public void WrittenJson_LoadsBackToSameModel()
    {
        // write → read → identical in-memory model.
        var original = HotkeyConfig.Default();
        var reloaded = HotkeyConfig.Parse(original.ToJson(), overwriteOnRepair: false, out _);

        Assert.Equal(original.Preset, reloaded.Preset);
        foreach (var (actionId, chords) in original.Bindings)
        {
            var got = reloaded.Bindings[actionId];
            Assert.Equal(chords.Count, got.Count);
            for (int i = 0; i < chords.Count; i++)
                Assert.True(chords[i].Matches(got[i]));
        }
    }

    [Fact]
    public void SaveTo_ThenLoadFrom_RoundTripsViaDisk()
    {
        var path = Path.Combine(Path.GetTempPath(), $"msi-cfg-{Guid.NewGuid():N}.json");
        try
        {
            var original = HotkeyConfig.Default();
            original.SaveTo(path);
            Assert.True(File.Exists(path));

            var loaded = HotkeyConfig.LoadFrom(path);
            Assert.Equal(HotkeyPreset.Hyper, loaded.Preset);
            Assert.Single(loaded.Bindings["inputTypeC"]);
            Assert.True(Hyper("C").Matches(loaded.Bindings["inputTypeC"][0]));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void LoadFrom_MissingFile_WritesDefaultAndUsesIt()
    {
        var path = Path.Combine(Path.GetTempPath(), $"msi-cfg-{Guid.NewGuid():N}.json");
        try
        {
            Assert.False(File.Exists(path));
            var loaded = HotkeyConfig.LoadFrom(path);

            Assert.True(File.Exists(path)); // §4.1: default written
            Assert.Equal(HotkeyPreset.Hyper, loaded.Preset);
            Assert.Empty(loaded.Bindings["kvmAuto"]); // UNKNOWN payload → no chord
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    // -------------------------------------------------------------------------
    // Fallback rules (docs/SETTINGS.md §4)
    // -------------------------------------------------------------------------

    [Fact]
    public void Parse_MalformedJson_FallsBackToDefaults()
    {
        var parsed = HotkeyConfig.Parse("{ this is not valid json ", overwriteOnRepair: false, repaired: out _);

        // §4.3: ignore the file, run on in-memory defaults.
        Assert.Equal(HotkeyConfig.CurrentSchemaVersion, parsed.SchemaVersion);
        Assert.Equal(HotkeyPreset.Hyper, parsed.Preset);
        Assert.True(Hyper("C").Matches(parsed.Bindings["inputTypeC"][0]));
    }

    [Fact]
    public void LoadFrom_MalformedJson_DoesNotOverwriteFile()
    {
        var path = Path.Combine(Path.GetTempPath(), $"msi-cfg-{Guid.NewGuid():N}.json");
        const string garbage = "{ not valid json at all ";
        try
        {
            File.WriteAllText(path, garbage);
            var loaded = HotkeyConfig.LoadFrom(path);

            // Runs on defaults …
            Assert.Equal(HotkeyPreset.Hyper, loaded.Preset);
            // … but the user's (broken) file is left untouched for them to fix (§4.3).
            Assert.Equal(garbage, File.ReadAllText(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void LoadFrom_NewerSchemaVersion_IgnoredAndNotOverwritten()
    {
        var path = Path.Combine(Path.GetTempPath(), $"msi-cfg-{Guid.NewGuid():N}.json");

        // A config written by a hypothetical future app version.
        var future = HotkeyConfig.Default();
        future.SchemaVersion = HotkeyConfig.CurrentSchemaVersion + 1;
        // Give it a tell-tale custom binding so we can prove defaults are used, not this file.
        future.Bindings["inputTypeC"] = new List<Chord> { new(new[] { HotkeyConfig.ModControl }, "Z") };
        var futureJson = future.ToJson();

        try
        {
            File.WriteAllText(path, futureJson);
            var loaded = HotkeyConfig.LoadFrom(path);

            // §4.3: newer version is ignored → in-memory defaults, NOT the file's binding.
            Assert.True(Hyper("C").Matches(loaded.Bindings["inputTypeC"][0]));
            // And the newer file is preserved verbatim (don't clobber a newer app's config).
            Assert.Equal(futureJson, File.ReadAllText(path));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Parse_DropsMalformedBindingEntry_KeepsTheRest()
    {
        // inputDP has a chord with no key — it must be dropped; inputTypeC survives intact.
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "hyper",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","alt","shift"], "key": "C" } ],
            "inputDP":    [ { "mods": ["control","alt","shift"], "key": "" } ]
          },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired);
        Assert.Single(parsed.Bindings["inputTypeC"]);
        Assert.Empty(parsed.Bindings["inputDP"]); // malformed chord dropped, rest load
    }

    [Fact]
    public void Parse_DropsCommandModifierOnWindows_WithSurvivingChord()
    {
        // A mac "legacy" config: control+option+command. On Windows the command modifier is
        // dropped (§3.4/§4); option folds to alt; the chord survives as Ctrl+Alt+<key>.
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "legacy",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","option","command"], "key": "C" } ]
          },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired); // command was dropped
        var chord = parsed.Bindings["inputTypeC"][0];
        Assert.Equal("C", chord.Key);
        Assert.Contains(HotkeyConfig.ModControl, chord.ModSet);
        Assert.Contains(HotkeyConfig.ModAlt, chord.ModSet);
        Assert.DoesNotContain(HotkeyConfig.ModCommand, chord.ModSet);
    }

    // -- Per-field resilience for badly-SHAPED entries (Codex blocker 2) ------

    [Fact]
    public void Parse_ChordWithNullMods_SurvivesAsModifierlessThenDropped()
    {
        // mods:null must not throw the whole deserialise. The defensive converter yields an
        // empty mods list; Sanitise then drops the modifier-less chord (§3.3/§3.5).
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "custom",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","alt","shift"], "key": "C" } ],
            "inputDP":    [ { "mods": null, "key": "D" } ]
          }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired);
        Assert.Single(parsed.Bindings["inputTypeC"]); // good chord survives
        Assert.Empty(parsed.Bindings["inputDP"]);     // null-mods chord dropped, not a throw
    }

    [Fact]
    public void Parse_NonObjectChordAndNonArrayValue_AreSkipped_RestSurvives()
    {
        // A stray non-object chord, and a binding value that isn't an array at all, must not
        // sink the deserialise; the well-formed binding still loads.
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "custom",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ "garbage", { "mods": ["control","alt","shift"], "key": "C" } ],
            "inputDP":    "not-an-array",
            "kvmUSBC":    [ { "mods": ["control","alt","shift"], "key": "K" } ]
          }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out _);

        Assert.Single(parsed.Bindings["inputTypeC"]); // string entry skipped, object kept
        Assert.True(Hyper("C").Matches(parsed.Bindings["inputTypeC"][0]));
        Assert.Empty(parsed.Bindings["inputDP"]);      // non-array → no chord
        Assert.Single(parsed.Bindings["kvmUSBC"]);     // untouched well-formed binding loads
    }

    [Fact]
    public void Parse_UnknownEnumModifierToken_DroppedNotThrown()
    {
        // A bad modifier token ("hyper") is not a valid enum value; it must be dropped, not
        // throw. The remaining real modifiers keep the chord valid.
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "custom",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","hyper","shift"], "key": "C" } ]
          }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired);
        var chord = parsed.Bindings["inputTypeC"][0];
        Assert.True(chord.ModSet.SetEquals(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModShift }));
    }

    // -- Validation on load: invalid keys + modifier-less (Codex blockers 3,5) --

    [Fact]
    public void Parse_DropsUnsupportedBaseKey_OnLoad()
    {
        // F5 / multi-char / symbol keys are outside the v0.2.0 set — rejected on load, not left
        // in app state to be silently skipped by the registrar (§3.4/§5).
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "custom",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","alt","shift"], "key": "F5" } ],
            "inputDP":    [ { "mods": ["control","alt","shift"], "key": "@" } ],
            "kvmUSBC":    [ { "mods": ["control","alt","shift"], "key": "K" } ]
          }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired);
        Assert.Empty(parsed.Bindings["inputTypeC"]); // "F5" dropped
        Assert.Empty(parsed.Bindings["inputDP"]);    // "@" dropped
        Assert.Single(parsed.Bindings["kvmUSBC"]);   // valid "K" kept
    }

    [Fact]
    public void Parse_DropsModifierlessChord_OnLoad()
    {
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "custom",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": [], "key": "C" } ]
          }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired);
        Assert.Empty(parsed.Bindings["inputTypeC"]); // no-modifier global hotkey rejected
    }

    [Fact]
    public void Parse_DropsDuplicateChord_OnLoad_KeepingFirst()
    {
        // A hand-edited config binds the same chord to two actions. Load-time validation (§3.5
        // check 1, BLOCKING) keeps the first occurrence and drops the later duplicate, so the
        // OS register call never silently loses the second one.
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "custom",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","alt","shift"], "key": "X" } ],
            "inputDP":    [ { "mods": ["control","alt","shift"], "key": "X" } ]
          }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out var repaired);

        Assert.True(repaired);
        Assert.Single(parsed.Bindings["inputTypeC"]); // first kept
        Assert.Empty(parsed.Bindings["inputDP"]);     // duplicate dropped

        // And the surviving config is now self-consistent — no duplicate remains.
        var survivor = parsed.Bindings["inputTypeC"][0];
        var check = parsed.ValidateChord("kvmUSBC", survivor);
        Assert.Equal("inputTypeC", check.DuplicateActionId);
    }

    [Fact]
    public void IsValidBaseKey_AcceptsLettersAndDigitsOnly()
    {
        Assert.True(HotkeyConfig.IsValidBaseKey("C"));
        Assert.True(HotkeyConfig.IsValidBaseKey("7"));
        Assert.False(HotkeyConfig.IsValidBaseKey("F5"));
        Assert.False(HotkeyConfig.IsValidBaseKey("@"));
        Assert.False(HotkeyConfig.IsValidBaseKey(""));
    }

    [Fact]
    public void Parse_MissingAltGrList_FallsBackToBuiltInDefault()
    {
        const string json = """
        {
          "schemaVersion": 1,
          "preset": "hyper",
          "launchAtLogin": false,
          "bindings": { "inputTypeC": [ { "mods": ["control","alt","shift"], "key": "C" } ] }
        }
        """;

        var parsed = HotkeyConfig.Parse(json, overwriteOnRepair: false, out _);
        Assert.NotEmpty(parsed.AltGrAvoidList.Keys);
        Assert.Contains("Q", parsed.AltGrAvoidList.Keys);
    }

    // -------------------------------------------------------------------------
    // Validation (docs/SETTINGS.md §3.5)
    // -------------------------------------------------------------------------

    [Fact]
    public void ValidateChord_DetectsDuplicate_Blocking()
    {
        var config = HotkeyConfig.Default();
        // inputDP already owns Ctrl+Alt+Shift+D. Try to bind the same chord to kvmUSBC.
        var candidate = Hyper("D");

        var result = config.ValidateChord("kvmUSBC", candidate);

        Assert.False(result.IsValid);
        Assert.Equal("inputDP", result.DuplicateActionId);
    }

    [Fact]
    public void ValidateChord_SameActionSameSlot_NotASelfClash()
    {
        var config = HotkeyConfig.Default();
        // Re-validating inputTypeC's existing chord (slot 0) against itself must be allowed.
        var result = config.ValidateChord("inputTypeC", Hyper("C"), excludeChordIndex: 0);
        Assert.True(result.IsValid);
    }

    [Fact]
    public void ValidateChord_FlagsAltGr_WhenKeyInListAndAltPresent()
    {
        var config = HotkeyConfig.Default(); // avoid-list includes "Q"
        var candidate = new Chord(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModAlt }, "Q");

        var result = config.ValidateChord("inputTypeC", candidate, excludeChordIndex: 0);

        Assert.True(result.AltGrWarning); // non-blocking advisory
        Assert.True(result.IsValid);      // still committable
    }

    [Fact]
    public void ValidateChord_NoAltGr_WhenAltAbsent()
    {
        var config = HotkeyConfig.Default();
        // Q is in the list, but no alt modifier → no AltGr risk.
        var candidate = new Chord(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModShift }, "Q");

        var result = config.ValidateChord("inputTypeC", candidate, excludeChordIndex: 0);
        Assert.False(result.AltGrWarning);
    }

    [Fact]
    public void ValidateChord_NoAltGr_WhenKeyNotInList()
    {
        var config = HotkeyConfig.Default();
        // 'C' is not in the avoid-list, even with alt → no risk.
        var candidate = new Chord(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModAlt }, "C");

        var result = config.ValidateChord("inputTypeC", candidate, excludeChordIndex: 0);
        Assert.False(result.AltGrWarning);
    }

    // -------------------------------------------------------------------------
    // Derived display (docs/SETTINGS.md §3.7)
    // -------------------------------------------------------------------------

    [Fact]
    public void DisplayString_JoinsWordsWithPlus_InCanonicalOrder()
    {
        Assert.Equal("Ctrl+Alt+Shift+C", HotkeyConfig.DisplayString(Hyper("C")));
    }

    [Fact]
    public void DisplayString_OrderIsCanonical_RegardlessOfInputOrder()
    {
        // Mods supplied out of order must still render Ctrl, Alt, Shift, key.
        var chord = new Chord(new[] { HotkeyConfig.ModShift, HotkeyConfig.ModAlt, HotkeyConfig.ModControl }, "k");
        Assert.Equal("Ctrl+Alt+Shift+K", HotkeyConfig.DisplayString(chord));
    }

    [Fact]
    public void DisplayString_CtrlShiftPreset()
    {
        var chord = new Chord(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModShift }, "U");
        Assert.Equal("Ctrl+Shift+U", HotkeyConfig.DisplayString(chord));
    }

    [Fact]
    public void PrimaryDisplay_EmptyForUnboundAction()
    {
        var config = HotkeyConfig.Default();
        Assert.Equal("", config.PrimaryDisplay("kvmAuto"));      // no chord
        Assert.Equal("Ctrl+Alt+Shift+C", config.PrimaryDisplay("inputTypeC"));
    }

    // -------------------------------------------------------------------------
    // Modifier normalisation + presets (docs/SETTINGS.md §3.2, §3.4)
    // -------------------------------------------------------------------------

    [Theory]
    [InlineData("control", "control")]
    [InlineData("Control", "control")]
    [InlineData("alt", "alt")]
    [InlineData("option", "alt")]   // synonym
    [InlineData("OPTION", "alt")]
    [InlineData("shift", "shift")]
    [InlineData("bogus", "")]        // unknown dropped
    public void NormaliseModifier_FoldsSynonymsAndDropsUnknown(string input, string expected)
    {
        Assert.Equal(expected, HotkeyConfig.NormaliseModifier(input));
    }

    [Fact]
    public void ApplyPreset_BakesModsAndSetsLabel()
    {
        var config = HotkeyConfig.Default();
        config.ApplyPreset(HotkeyPreset.CtrlShift);

        Assert.Equal(HotkeyPreset.CtrlShift, config.Preset);
        var chord = config.Bindings["inputTypeC"][0];
        Assert.True(chord.ModSet.SetEquals(new[] { HotkeyConfig.ModControl, HotkeyConfig.ModShift }));
        Assert.Equal("C", chord.Key); // key unchanged, only mods re-baked
        Assert.Empty(config.Bindings["kvmAuto"]); // empty stays empty
    }

    [Fact]
    public void DerivePreset_ReturnsCustom_AfterHandEdit()
    {
        var config = HotkeyConfig.Default(); // hyper
        Assert.Equal(HotkeyPreset.Hyper, config.DerivePreset());

        // Hand-edit one binding to Ctrl-only → no longer matches any named preset.
        config.Bindings["inputTypeC"][0] = new Chord(new[] { HotkeyConfig.ModControl }, "C");
        Assert.Equal(HotkeyPreset.Custom, config.DerivePreset());
    }

    // -------------------------------------------------------------------------
    // Shared fixture (docs/fixtures/settings.example.json) — cross-platform guard
    // -------------------------------------------------------------------------

    [Fact]
    public void Fixture_ParsesAndReproducesDefaultBindings()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "fixtures", "settings.example.json");
        Assert.True(File.Exists(path), $"Fixture not copied to output: {path}");

        var raw = File.ReadAllText(path);
        var parsed = HotkeyConfig.Parse(raw, overwriteOnRepair: false, out _);

        Assert.Equal(1, parsed.SchemaVersion);
        Assert.Equal(HotkeyPreset.Hyper, parsed.Preset);
        Assert.False(parsed.LaunchAtLogin);

        // The four available actions reproduce the §7 default chords exactly.
        Assert.True(Hyper("C").Matches(parsed.Bindings["inputTypeC"][0]));
        Assert.True(Hyper("D").Matches(parsed.Bindings["inputDP"][0]));
        Assert.True(Hyper("K").Matches(parsed.Bindings["kvmUSBC"][0]));
        Assert.True(Hyper("U").Matches(parsed.Bindings["kvmUpstream"][0]));

        // The three UNKNOWN-payload actions have no chord.
        Assert.Empty(parsed.Bindings["kvmAuto"]);
        Assert.Empty(parsed.Bindings["pbpOn"]);
        Assert.Empty(parsed.Bindings["pbpOff"]);

        // AltGr advisory list survives from the fixture.
        Assert.Contains("Q", parsed.AltGrAvoidList.Keys);
    }

    /// <summary>
    /// Cross-app contract guard (docs/SETTINGS.md §3.4/§3.8): a mac-written "option" modifier
    /// loads into the same in-memory chord here via the option↔alt synonym — the load half of
    /// the interop guarantee (the byte-identity half is DefaultToJson_EqualsSharedFixture).
    /// </summary>
    [Fact]
    public void MacWrittenOption_LoadsAsSamePhysicalChord()
    {
        const string macHyper = """
        {
          "schemaVersion": 1,
          "preset": "hyper",
          "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","option","shift"], "key": "C" } ]
          },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" }
        }
        """;

        var parsed = HotkeyConfig.Parse(macHyper, overwriteOnRepair: false, out _);
        Assert.True(Hyper("C").Matches(parsed.Bindings["inputTypeC"][0]));
    }
}

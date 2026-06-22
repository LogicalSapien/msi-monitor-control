import XCTest
@testable import MSIControl

/// Tests for the shared settings contract (`docs/SETTINGS.md`). These exercise the
/// model, Codable round-trip, the never-block load/fallback rules, validation, and
/// the apply-and-bake preset behaviour — all hardware-independent.
final class HotkeyConfigTests: XCTestCase {

    // MARK: Helpers

    /// A unique temp file URL per test (not created on disk).
    private func tempURL(_ name: String = "settings.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hotkeyconfig-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: Defaults

    func testDefaultConfigShape() {
        let def = HotkeyConfig.makeDefault()
        XCTAssertEqual(def.schemaVersion, kHotkeyConfigSchemaVersion)
        XCTAssertEqual(def.preset, .cmdShiftCtrl)
        XCTAssertFalse(def.launchAtLogin)
        // Available commands get the default ⌃⇧⌘ chord on their default key; UNKNOWN
        // ones are bound to an empty array (no chord).
        XCTAssertEqual(def.bindings["inputTypeC"], [HotkeyChord(mods: [.control, .shift, .command], key: "C")])
        // KVM Auto is now available (hardware-confirmed payload) → it gets a chord.
        XCTAssertEqual(def.bindings["kvmAuto"], [HotkeyChord(mods: [.control, .shift, .command], key: "A")])
        XCTAssertEqual(def.bindings["pbpOn"], [])
        // Every command has a key in the map.
        for command in Command.allCases {
            XCTAssertNotNil(def.bindings[command.actionId], "missing binding for \(command.actionId)")
        }
    }

    // MARK: Codable round-trip

    func testRoundTripPreservesConfig() throws {
        let original = HotkeyConfig.makeDefault()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testOptionAltSynonymNormalisesToOption() throws {
        // A Windows-written config may spell the modifier "alt"; we must read it.
        let json = """
        {
          "schemaVersion": 1, "preset": "cmdShiftCtrl", "launchAtLogin": false,
          "bindings": { "inputTypeC": [ { "mods": ["control", "alt", "shift"], "key": "C" } ] },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(HotkeyConfig.self, from: json)
        XCTAssertEqual(config.bindings["inputTypeC"]?.first?.mods, [.control, .option, .shift])
    }

    /// Repo `docs/fixtures/` directory.
    private func fixturesDir() -> URL {
        URL(fileURLWithPath: #filePath)            // …/Tests/MSIControlTests/HotkeyConfigTests.swift
            .deletingLastPathComponent()            // …/Tests/MSIControlTests
            .deletingLastPathComponent()            // …/Tests
            .deletingLastPathComponent()            // …/macos
            .deletingLastPathComponent()            // repo root
            .appendingPathComponent("docs/fixtures")
    }

    /// The macOS canonical fixture (the default preset is per-OS — Mac writes
    /// `command` — so each platform has its own fixture; SETTINGS.md §2.1/§3.8).
    private func macFixtureURL() -> URL {
        fixturesDir().appendingPathComponent("settings.example.macos.json")
    }

    /// The SHARED platform-independent fixture: the default config under the
    /// `ctrlShift` preset. Both apps must emit this byte-for-byte (mods are
    /// `["control","shift"]`, identical on Mac and Windows) — the one genuine
    /// cross-app byte-identity guarantee (SETTINGS.md §2.1).
    private func ctrlShiftFixtureURL() -> URL {
        fixturesDir().appendingPathComponent("settings.example.ctrlshift.json")
    }

    private func ctrlShiftConfig() -> HotkeyConfig {
        var c = HotkeyConfig.makeDefault()
        c.applyPreset(.ctrlShift)
        return c
    }

    /// ONE-OFF FIXTURE GENERATOR. Set REGEN_FIXTURE=1 to rewrite the macOS + shared
    /// ctrlShift fixtures from the encoder, then unset it. Skipped in normal runs.
    func testRegenerateFixtureWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REGEN_FIXTURE"] == "1",
                          "set REGEN_FIXTURE=1 to regenerate the fixtures")
        try HotkeyConfig.makeDefault().jsonData().write(to: macFixtureURL())
        try ctrlShiftConfig().jsonData().write(to: ctrlShiftFixtureURL())
    }

    /// The canonical contract (SETTINGS.md §3.8): the default config's `save()` bytes
    /// MUST equal the macOS fixture byte-for-byte. (The default preset is per-OS, so
    /// this is the macOS fixture; Windows has its own.)
    func testDefaultSaveBytesEqualFixtureBytes() throws {
        let url = macFixtureURL()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "macOS fixture not found at \(url.path)")
        let produced = try HotkeyConfig.makeDefault().jsonData()
        let fixture = try Data(contentsOf: url)
        XCTAssertEqual(produced, fixture,
                       "default save() must be byte-identical to the macOS fixture (SETTINGS.md §3.8)")
    }

    /// Platform-INDEPENDENT cross-app byte check (SETTINGS.md §2.1): the `ctrlShift`
    /// preset has the same mods on both platforms, so a config under it is genuinely
    /// byte-identical across apps. This asserts `default→ctrlShift save()` equals the
    /// SHARED fixture byte-for-byte — the Windows app points its own test at the SAME
    /// committed file, so byte-equality of both against it proves cross-app
    /// byte-identity. (Also a sanity check: no platform-specific mod token leaks in.)
    func testCtrlShiftPresetIsByteIdenticalToSharedFixture() throws {
        let url = ctrlShiftFixtureURL()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "shared ctrlShift fixture not found at \(url.path)")
        let produced = try ctrlShiftConfig().jsonData()
        let fixture = try Data(contentsOf: url)
        XCTAssertEqual(produced, fixture,
                       "ctrlShift save() must be byte-identical to the shared cross-app fixture (SETTINGS.md §2.1)")
        let text = String(decoding: produced, as: UTF8.self)
        XCTAssertFalse(text.contains("command"), "ctrlShift must not write a platform-specific 'command'")
        XCTAssertFalse(text.contains("\"alt\""), "ctrlShift must not write 'alt'")
    }

    func testMacFixtureParsesToDefaults() throws {
        let url = macFixtureURL()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "macOS fixture not found at \(url.path)")
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        XCTAssertEqual(config.bindings, HotkeyConfig.makeDefault().bindings)
        XCTAssertEqual(config.preset, .cmdShiftCtrl)
    }

    /// Mutual-loadability for the per-OS default: the WINDOWS fixture (mods
    /// `control, alt, shift`) must load in the macOS app and, via the alt→option
    /// synonym, produce the equivalent model. Proves cross-app interop even though
    /// the per-OS default isn't byte-identical across platforms.
    func testWindowsFixtureLoadsViaSynonym() throws {
        let url = fixturesDir().appendingPathComponent("settings.example.windows.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "windows fixture not found at \(url.path)")
        let (config, _) = HotkeyConfig.load(from: url)
        // alt normalises to option, so inputTypeC becomes ⌃⌥⇧C in our model.
        XCTAssertEqual(config.bindings["inputTypeC"],
                       [HotkeyChord(mods: [.control, .option, .shift], key: "C")],
                       "Windows 'alt' must load as 'option' via the synonym")
    }

    // MARK: Load / fallback (SETTINGS.md §4)

    func testMissingFileWritesDefaults() throws {
        let url = tempURL(); defer { cleanup(url) }
        let (config, outcome) = HotkeyConfig.load(from: url)
        XCTAssertEqual(outcome, .wroteDefault)
        XCTAssertEqual(config, HotkeyConfig.makeDefault())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "defaults should have been written to disk")
    }

    func testMalformedFileFallsBackToDefaultsWithoutOverwriting() throws {
        let url = tempURL(); defer { cleanup(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = "{ this is not valid json ".data(using: .utf8)!
        try garbage.write(to: url)

        let (config, outcome) = HotkeyConfig.load(from: url)
        XCTAssertEqual(outcome, .usedDefaultsInMemory)
        XCTAssertEqual(config, HotkeyConfig.makeDefault())
        // The malformed file must be preserved untouched (not overwritten).
        XCTAssertEqual(try Data(contentsOf: url), garbage)
    }

    func testNewerSchemaVersionIsIgnoredAndPreserved() throws {
        let url = tempURL(); defer { cleanup(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = """
        { "schemaVersion": 999, "preset": "cmdShiftCtrl", "launchAtLogin": true,
          "bindings": {}, "altGrAvoidList": { "keys": [], "note": "" },
          "futureField": 42 }
        """.data(using: .utf8)!
        try newer.write(to: url)

        let (config, outcome) = HotkeyConfig.load(from: url)
        XCTAssertEqual(outcome, .usedDefaultsInMemory)
        XCTAssertEqual(config, HotkeyConfig.makeDefault())
        // A file from a newer app version must NOT be clobbered.
        XCTAssertEqual(try Data(contentsOf: url), newer)
    }

    func testValidFileLoadsFromDisk() throws {
        let url = tempURL(); defer { cleanup(url) }
        var saved = HotkeyConfig.makeDefault()
        saved.launchAtLogin = true
        try saved.save(to: url)

        let (config, outcome) = HotkeyConfig.load(from: url)
        XCTAssertEqual(outcome, .loadedFromFile)
        XCTAssertTrue(config.launchAtLogin)
        XCTAssertEqual(config, saved)
    }

    // MARK: Validation (SETTINGS.md §3.5)

    func testDuplicateChordIsDetected() {
        let config = HotkeyConfig.makeDefault()
        // inputDP defaults to ⌃⇧⌘D — proposing it for inputTypeC is a duplicate.
        let clash = HotkeyChord(mods: [.control, .shift, .command], key: "D")
        let issues = config.validate(chord: clash, forAction: "inputTypeC")
        XCTAssertTrue(issues.contains(.duplicate(existingActionId: "inputDP")))
    }

    func testRebindingSameActionToOwnChordIsNotADuplicate() {
        let config = HotkeyConfig.makeDefault()
        let same = HotkeyChord(mods: [.control, .shift, .command], key: "C")
        let issues = config.validate(chord: same, forAction: "inputTypeC")
        XCTAssertFalse(issues.contains(where: { if case .duplicate = $0 { return true }; return false }))
    }

    func testAltGrWarningFiresForAvoidKeyWithOption() {
        let config = HotkeyConfig.makeDefault()
        // "E" is in the avoid-list; with option/alt this should warn (non-blocking).
        let chord = HotkeyChord(mods: [.control, .option, .shift], key: "E")
        let issues = config.validate(chord: chord, forAction: "inputTypeC")
        XCTAssertTrue(issues.contains(.altGrWarning(key: "E")))
    }

    func testAltGrWarningDoesNotFireWithoutOption() {
        let config = HotkeyConfig.makeDefault()
        // Same avoid-key but no option/alt → no AltGr concern.
        let chord = HotkeyChord(mods: [.control, .shift], key: "E")
        let issues = config.validate(chord: chord, forAction: "inputTypeC")
        XCTAssertFalse(issues.contains(.altGrWarning(key: "E")))
    }

    // MARK: Preset apply-and-bake (SETTINGS.md §3.2)

    func testApplyPresetRewritesAllModifiers() {
        var config = HotkeyConfig.makeDefault()
        config.applyPreset(.ctrlShift)
        XCTAssertEqual(config.preset, .ctrlShift)
        for chords in config.bindings.values {
            for chord in chords {
                XCTAssertEqual(chord.mods, [.control, .shift])
            }
        }
    }

    func testApplyPresetPreservesKeys() {
        var config = HotkeyConfig.makeDefault()
        config.applyPreset(.legacy)
        XCTAssertEqual(config.bindings["inputTypeC"]?.first?.key, "C")
        XCTAssertEqual(config.bindings["inputTypeC"]?.first?.mods, [.control, .option, .command])
    }

    func testInferredPresetDetectsCustom() {
        var config = HotkeyConfig.makeDefault()       // cmdShiftCtrl
        XCTAssertEqual(config.inferredPreset(), .cmdShiftCtrl)
        // Hand-edit one binding to an off-preset chord.
        config.bindings["inputTypeC"] = [HotkeyChord(mods: [.command], key: "C")]
        XCTAssertEqual(config.inferredPreset(), .custom)
    }

    // MARK: Derived display (SETTINGS.md §3.7)

    func testChordDisplayUsesCanonicalGlyphOrder() {
        let chord = HotkeyChord(mods: [.shift, .command, .control, .option], key: "C")
        XCTAssertEqual(chord.display, "⌃⌥⇧⌘C")
    }

    // MARK: Deterministic save + fixture parse (SETTINGS.md §2.1)

    func testSaveOutputIsDeterministic() throws {
        let config = HotkeyConfig.makeDefault()
        let a = try config.jsonData()
        let b = try config.jsonData()
        XCTAssertEqual(a, b, "same model must always serialise to identical bytes")
    }

    func testSavedConfigReloadsToSameModel() throws {
        let url = tempURL(); defer { cleanup(url) }
        let original = HotkeyConfig.makeDefault()
        try original.save(to: url)
        let (reloaded, outcome) = HotkeyConfig.load(from: url)
        XCTAssertEqual(outcome, .loadedFromFile)
        XCTAssertEqual(reloaded, original, "save→load must round-trip to the same model")
    }

    // MARK: Per-field resilience on load (SETTINGS.md §4, Codex blocker #2)

    func testLoadDropsSingleMalformedChordKeepsRest() throws {
        let url = tempURL(); defer { cleanup(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // inputDP has one good chord + one malformed (bad key "AB" and unknown mod);
        // inputTypeC is valid. The bad chord must be dropped, the rest kept.
        let json = """
        {
          "schemaVersion": 1, "preset": "cmdShiftCtrl", "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","option","shift"], "key": "C" } ],
            "inputDP":    [ { "mods": ["control","option","shift"], "key": "D" },
                            { "mods": ["bogus"], "key": "AB" } ]
          },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" }
        }
        """.data(using: .utf8)!
        try json.write(to: url)

        let (config, outcome) = HotkeyConfig.load(from: url)
        if case .loadedWithRepairs = outcome {} else { XCTFail("expected loadedWithRepairs, got \(outcome)") }
        XCTAssertEqual(config.bindings["inputTypeC"]?.count, 1)
        XCTAssertEqual(config.bindings["inputDP"], [HotkeyChord(mods: [.control, .option, .shift], key: "D")],
                       "the good inputDP chord survives; only the malformed one is dropped")
    }

    func testLoadMissingAltGrFallsBackToBuiltIn() throws {
        let url = tempURL(); defer { cleanup(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "preset": "cmdShiftCtrl", "launchAtLogin": false,
          "bindings": { "inputTypeC": [ { "mods": ["control","option","shift"], "key": "C" } ] } }
        """.data(using: .utf8)!
        try json.write(to: url)

        let (config, _) = HotkeyConfig.load(from: url)
        XCTAssertEqual(config.altGrAvoidList, .builtIn,
                       "a missing altGrAvoidList must fall back to the built-in default, not fail the load")
    }

    func testLoadInvalidKeyIsRejectedPerChord() throws {
        let url = tempURL(); defer { cleanup(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A two-character key must be rejected (Carbon would silently use only "A").
        let json = """
        { "schemaVersion": 1, "preset": "cmdShiftCtrl", "launchAtLogin": false,
          "bindings": { "inputTypeC": [ { "mods": ["control","shift"], "key": "AB" } ] },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" } }
        """.data(using: .utf8)!
        try json.write(to: url)

        let (config, _) = HotkeyConfig.load(from: url)
        XCTAssertEqual(config.bindings["inputTypeC"], [], "invalid multi-char key chord must be dropped")
    }

    // MARK: Validate-on-load: duplicates (SETTINGS.md §3.5, Codex blocker #3)

    func testLoadResolvesDuplicateChordsFirstWins() throws {
        let url = tempURL(); defer { cleanup(url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Both inputTypeC and inputDP claim ⌃⇧C. After load only one keeps it.
        let json = """
        { "schemaVersion": 1, "preset": "custom", "launchAtLogin": false,
          "bindings": {
            "inputTypeC": [ { "mods": ["control","shift"], "key": "C" } ],
            "inputDP":    [ { "mods": ["control","shift"], "key": "C" } ]
          },
          "altGrAvoidList": { "keys": ["Q"], "note": "x" } }
        """.data(using: .utf8)!
        try json.write(to: url)

        let (config, outcome) = HotkeyConfig.load(from: url)
        if case .loadedWithRepairs = outcome {} else { XCTFail("expected loadedWithRepairs, got \(outcome)") }
        let dup = HotkeyChord(mods: [.control, .shift], key: "C")
        let claimants = ["inputTypeC", "inputDP"].filter { config.bindings[$0]?.contains(dup) == true }
        XCTAssertEqual(claimants.count, 1, "exactly one action keeps the duplicated chord after load")
    }

    func testKeyValidationHelper() {
        XCTAssertTrue(HotkeyChord.isValidKey("C"))
        XCTAssertTrue(HotkeyChord.isValidKey("7"))
        XCTAssertFalse(HotkeyChord.isValidKey("AB"))
        XCTAssertFalse(HotkeyChord.isValidKey(""))
        XCTAssertFalse(HotkeyChord.isValidKey("é"))
    }

    // MARK: Commit / rollback decision (SETTINGS.md §3.5/§5, Codex blocker #4)

    func testDecideCommitAcceptsWhenNoRejection() {
        let previous = HotkeyConfig.makeDefault()
        var candidate = previous
        candidate.applyPreset(.ctrlShift)
        let decision = HotkeyConfig.decideCommit(previous: previous, candidate: candidate, rejectedActions: [])
        XCTAssertEqual(decision, .commit(candidate))
    }

    func testDecideCommitRollsBackOnRejectionKeepingPrevious() {
        let previous = HotkeyConfig.makeDefault()
        var candidate = previous
        candidate.bindings["inputTypeC"] = [HotkeyChord(mods: [.command], key: "C")]
        // OS rejected inputTypeC's new chord → must roll back to `previous`, not persist.
        let decision = HotkeyConfig.decideCommit(previous: previous, candidate: candidate,
                                                 rejectedActions: ["inputTypeC"])
        XCTAssertEqual(decision, .rollback(previous: previous, rejectedActions: ["inputTypeC"]))
    }

    // MARK: HotkeyCommitter live-registration behaviour (Codex re-review blocker #2)

    /// Spy registrar: records every config it was asked to register, and can be told
    /// to reject specific actionIds (simulating an OS-reserved chord).
    private final class SpyRegistrar: HotkeyRegistering {
        var appliedConfigs: [HotkeyConfig] = []
        var rejectActions: [String] = []
        func apply(config: HotkeyConfig) -> [String] {
            appliedConfigs.append(config)
            return rejectActions
        }
    }

    func testCommitterPersistsAndKeepsCandidateWhenAccepted() {
        let spy = SpyRegistrar()   // rejects nothing
        let previous = HotkeyConfig.makeDefault()
        var candidate = previous
        candidate.applyPreset(.ctrlShift)
        var persisted: HotkeyConfig?

        let result = HotkeyCommitter.commit(previous: previous, candidate: candidate,
                                            registrar: spy, persist: { persisted = $0 })

        XCTAssertTrue(result.committed)
        XCTAssertEqual(result.liveConfig, candidate)
        XCTAssertEqual(persisted, candidate, "accepted config must be persisted exactly once")
        XCTAssertEqual(spy.appliedConfigs, [candidate], "only the candidate is registered on success")
    }

    func testCommitterRollsBackReRegistersPreviousAndDoesNotPersistOnReject() {
        let spy = SpyRegistrar()
        spy.rejectActions = ["inputTypeC"]   // OS refuses the new chord
        let previous = HotkeyConfig.makeDefault()
        var candidate = previous
        candidate.bindings["inputTypeC"] = [HotkeyChord(mods: [.command], key: "C")]
        var persistCount = 0

        let result = HotkeyCommitter.commit(previous: previous, candidate: candidate,
                                            registrar: spy, persist: { _ in persistCount += 1 })

        XCTAssertFalse(result.committed)
        XCTAssertEqual(result.liveConfig, previous, "rolled-back live config is the previous one")
        XCTAssertEqual(result.rejectedActions, ["inputTypeC"])
        XCTAssertEqual(persistCount, 0, "a rejected change must NOT be persisted")
        // The registrar must have been asked to register the candidate FIRST, then
        // the previous config AGAIN — proving the user's working hotkeys are restored.
        XCTAssertEqual(spy.appliedConfigs, [candidate, previous],
                       "rollback must re-register the previous (working) config")
    }
}

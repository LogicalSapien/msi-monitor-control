# MSI Monitor Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dual-platform (macOS + Windows) menu-bar/tray utility that controls an MSI MD342CQP monitor (PBP toggle, KVM switch, input switch) via reverse-engineered USB HID commands, with global hotkeys.

**Architecture:** Public monorepo `logicalspine/msi-monitor-control` with `/macos` (Swift/SwiftUI) and `/windows` (C#/HidSharp). The exact HID payloads live in `docs/PROTOCOL.md` — the single source of truth both apps send byte-identically. macOS track produces PROTOCOL.md first (it owns the reverse-engineering); Windows track consumes it.

**Tech Stack:** Swift / SwiftUI (`MenuBarExtra`, `IOHIDManager`, Carbon hotkeys), C# (.NET 8 `net8.0-windows`, WinForms `NotifyIcon`, HidSharp, Win32 `RegisterHotKey`), GitHub Actions (build-only CI phase 1).

## Global Constraints

- **British English everywhere:** docs, UI copy, code identifiers, commits. (e.g. "colour", "behaviour", "initialise".)
- **Licence:** MIT, © logicalspine. Repo public under `logicalspine` org.
- **Tested model:** MSI MD342CQP only. May-work (unverified, README must say "use at your own risk"): MS321UP, MD272QP, MD272P, MD272XP, MD272QXP, MP275QPDG, MD272UPH.
- **Protocol:** raw USB HID (NOT DDC/CI). Reference: github.com/Phaseowner/MSI-Display-Switch (Swift, MD342CQP tested). Payloads reverse-engineered — README carries the safety note.
- **Both apps send byte-identical HID reports** sourced from `docs/PROTOCOL.md`.
- **macOS target:** macOS 13+ (MenuBarExtra). **Windows target:** .NET 8, `net8.0-windows`.
- **Phase 1 = build-and-run from source.** No signing, no installers, no releases. CI builds only.
- **Minimal diffs, minimal components.** No over-engineering, no speculative flexibility.
- **Four actions exactly:** PBP on/off toggle; KVM USB-C↔Upstream; Input Type-C↔DP; all hotkey-bound.

---

## Track A — Shared scaffold (done once, before/at repo creation)

### Task A1: Repository scaffold

**Files:**
- Create: `README.md`, `LICENSE`, `CONTRIBUTING.md`, `.gitignore`
- Create: `docs/PROTOCOL.md` (skeleton — payloads filled in Task B1)

**Interfaces:**
- Produces: the repo skeleton and `docs/PROTOCOL.md` path that both tracks reference.

- [ ] **Step 1: Create `LICENSE`** — standard MIT text, `Copyright (c) 2026 logicalspine`.

- [ ] **Step 2: Create `.gitignore`** covering both platforms:

```gitignore
# macOS / Swift / Xcode
.DS_Store
macos/.build/
macos/.swiftpm/
*.xcuserdata/
DerivedData/

# Windows / .NET
windows/bin/
windows/obj/
*.user
```

- [ ] **Step 3: Create `README.md`** with: one-line description; **Supported monitors** section stating MD342CQP is tested and the 7 others "may work, unverified, use at your own risk"; **Safety note** ("HID payloads obtained by reverse engineering — use at your own risk"); build/run instructions for each platform (filled as tracks complete); credit to github.com/Phaseowner/MSI-Display-Switch. British English.

- [ ] **Step 4: Create `CONTRIBUTING.md`** — how to build each app, that `docs/PROTOCOL.md` is the source of truth for payloads, and how to add a new model (extend PROTOCOL.md + the `Command` mappings).

- [ ] **Step 5: Create `docs/PROTOCOL.md` skeleton** with headed sections to be filled in Task B1: `## Device (VID/PID)`, `## HID interface (usage page / usage / report type / length)`, `## Payloads` (a table: Action | Bytes), `## Reverse-engineering notes`.

- [ ] **Step 6: Commit**

```bash
git add LICENSE .gitignore README.md CONTRIBUTING.md docs/PROTOCOL.md
git commit -m "chore: scaffold msi-monitor-control monorepo"
```

---

## Track B — macOS app (`/macos`) — RUNS FIRST (owns PROTOCOL.md)

### Task B1: Extract payloads → fill `docs/PROTOCOL.md`

**Files:**
- Modify: `docs/PROTOCOL.md`

**Interfaces:**
- Produces: the authoritative VID/PID, HID interface details, and the six payload byte arrays (PBP on, PBP off, KVM→USB-C, KVM→Upstream, Input→Type-C, Input→DP). Both apps depend on these exact bytes.

- [ ] **Step 1: Clone/read the reference source.** `git clone https://github.com/Phaseowner/MSI-Display-Switch` into a temp dir (outside the repo). Locate the Swift files that open the HID device and build the report bytes.

- [ ] **Step 2: Record the device identity** — extract the USB Vendor ID and Product ID used to match the MD342CQP, plus the HID usage page/usage (or report ID), report type (output vs feature), and report length. Write them into PROTOCOL.md's `## Device` and `## HID interface` sections.

- [ ] **Step 3: Record the six payloads** — copy the exact byte arrays the reference sends for input switching (Type-C, DP) and, if present, PBP and KVM. Fill the `## Payloads` table. If a given action's bytes are NOT discoverable in the reference (e.g. PBP/KVM not implemented there), mark it `UNKNOWN — needs reverse engineering on hardware` in the table and note it under `## Reverse-engineering notes` so it surfaces as a Needs-decision to the human (do NOT invent bytes).

- [ ] **Step 4: Commit**

```bash
git add docs/PROTOCOL.md
git commit -m "docs: document MD342CQP HID device + payloads in PROTOCOL.md"
```

### Task B2: `Command` model + payload table (unit-tested)

**Files:**
- Create: `macos/Sources/MSIControl/Command.swift`
- Test: `macos/Tests/MSIControlTests/CommandTests.swift`
- Create: `macos/Package.swift` (SwiftPM, library target `MSIControl` + executable target `MSIControlApp`)

**Interfaces:**
- Produces: `enum Command: CaseIterable { case pbpOn, pbpOff, kvmUSBC, kvmUpstream, inputTypeC, inputDP }` and `var payload: [UInt8]` returning the bytes from PROTOCOL.md. Consumed by `MSIDevice` and the menu/hotkey layer.

- [ ] **Step 1: Write the failing test** — assert each `Command.payload` equals the exact bytes from PROTOCOL.md (hard-code expected arrays from the doc), and that `Command.allCases.count == 6`.

```swift
import XCTest
@testable import MSIControl

final class CommandTests: XCTestCase {
    func testInputDPPayloadMatchesProtocol() {
        // expected bytes copied verbatim from docs/PROTOCOL.md
        XCTAssertEqual(Command.inputDP.payload, [/* bytes */])
    }
    func testAllSixCommandsExist() {
        XCTAssertEqual(Command.allCases.count, 6)
    }
}
```

- [ ] **Step 2: Run test, verify it fails** — `cd macos && swift test` → FAIL (no `Command`).

- [ ] **Step 3: Implement `Command.swift`** — the enum + `payload` computed property returning the PROTOCOL.md bytes. (Use the real bytes; if any are UNKNOWN from B1, that action is omitted from the menu and flagged to the human — do not ship invented bytes.)

- [ ] **Step 4: Run test, verify it passes** — `swift test` → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(macos): add Command model with HID payloads"`.

### Task B3: `MSIDevice` HID transport

**Files:**
- Create: `macos/Sources/MSIControl/MSIDevice.swift`
- Test: `macos/Tests/MSIControlTests/MSIDeviceTests.swift`

**Interfaces:**
- Consumes: `Command` from B2.
- Produces: `final class MSIDevice { var isConnected: Bool { get }; func send(_ command: Command) -> Result<Void, MSIError> }` and `enum MSIError: Error { case deviceNotFound, sendFailed(String) }`. Consumed by the app/hotkey layer.

- [ ] **Step 1: Write the failing test** — with no monitor attached, `MSIDevice().send(.inputDP)` returns `.failure(.deviceNotFound)` and `isConnected == false`. (This is the CI-runnable test; real send is manual smoke-tested.)

- [ ] **Step 2: Run test, verify it fails** — `swift test` → FAIL.

- [ ] **Step 3: Implement `MSIDevice.swift`** — use `IOHIDManager` to match by the VID/PID from PROTOCOL.md, open the device, and send `command.payload` as the report type PROTOCOL.md specifies (output or feature report). Return `.deviceNotFound` when no match; map IOKit errors to `.sendFailed`.

- [ ] **Step 4: Run test, verify it passes** — `swift test` → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(macos): add MSIDevice IOHIDManager transport"`.

### Task B4: Menu-bar app + global hotkeys

**Files:**
- Create: `macos/Sources/MSIControlApp/main.swift` (or `App.swift`), `macos/Sources/MSIControlApp/MenuBarView.swift`, `macos/Sources/MSIControlApp/HotKeys.swift`
- Modify: `macos/Package.swift` (executable target, `LSUIElement`)
- Modify: `README.md` (macOS build/run + default hotkeys)

**Interfaces:**
- Consumes: `MSIDevice`, `Command` from B2/B3.
- Produces: the runnable menu-bar app. No downstream consumer.

- [ ] **Step 1: Implement `MenuBarView`** — SwiftUI `MenuBarExtra` listing the available commands (PBP toggle, KVM USB-C, KVM Upstream, Input Type-C, Input DP), each calling `device.send(...)`; show a connected/not-connected indicator from `device.isConnected`; British-English labels.

- [ ] **Step 2: Implement `HotKeys.swift`** — register global hotkeys via Carbon `RegisterEventHotKey` mapping to each `Command`. Document defaults in README.

- [ ] **Step 3: Implement the app entry point** — `MenuBarExtra` scene; set `LSUIElement` (menu-bar-only, no Dock icon).

- [ ] **Step 4: Build** — `cd macos && swift build` → succeeds. Manual smoke test against the real MD342CQP (human-run): verify input switch works (known-good from reference), then PBP/KVM.

- [ ] **Step 5: Update README** macOS section with `swift build` / run steps and default hotkeys. **Commit** — `git commit -m "feat(macos): menu-bar app with actions and global hotkeys"`.

---

## Track C — Windows app (`/windows`) — RUNS AFTER B1 (needs PROTOCOL.md)

### Task C1: Project + `Command` model (unit-tested)

**Files:**
- Create: `windows/MsiMonitorControl.sln`, `windows/MsiMonitorControl/MsiMonitorControl.csproj` (`net8.0-windows`, WinForms, HidSharp PackageReference), `windows/MsiMonitorControl/Command.cs`
- Create: `windows/MsiMonitorControl.Tests/MsiMonitorControl.Tests.csproj` (xUnit), `windows/MsiMonitorControl.Tests/CommandTests.cs`

**Interfaces:**
- Consumes: `docs/PROTOCOL.md` payloads (must equal the macOS `Command.payload` bytes exactly).
- Produces: `enum Command { PbpOn, PbpOff, KvmUsbC, KvmUpstream, InputTypeC, InputDp }` and `static byte[] PayloadFor(Command c)`. Consumed by `MsiDevice` and tray/hotkey layer.

- [ ] **Step 1: Write the failing test** — assert `Command.PayloadFor(Command.InputDp)` equals the exact bytes from PROTOCOL.md (same bytes the macOS test uses), and all six commands map to a payload.

```csharp
public class CommandTests {
    [Fact]
    public void InputDpPayloadMatchesProtocol() {
        Assert.Equal(new byte[] { /* same bytes as PROTOCOL.md */ }, Command.PayloadFor(CommandKind.InputDp));
    }
}
```

- [ ] **Step 2: Run test, verify it fails** — `cd windows && dotnet test` → FAIL.

- [ ] **Step 3: Implement `Command.cs`** — enum + `PayloadFor` returning PROTOCOL.md bytes (byte-identical to macOS).

- [ ] **Step 4: Run test, verify it passes** — `dotnet test` → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(windows): add Command model with HID payloads"`.

### Task C2: `MsiDevice` HID transport (HidSharp)

**Files:**
- Create: `windows/MsiMonitorControl/MsiDevice.cs`
- Test: `windows/MsiMonitorControl.Tests/MsiDeviceTests.cs`

**Interfaces:**
- Consumes: `Command` from C1.
- Produces: `class MsiDevice { bool IsConnected { get; } MsiResult Send(CommandKind c) }` with a result type carrying `DeviceNotFound`/`SendFailed`. Mirrors macOS `MSIDevice` semantics.

- [ ] **Step 1: Write the failing test** — with no monitor attached, `new MsiDevice().Send(InputDp)` reports `DeviceNotFound` and `IsConnected == false`.

- [ ] **Step 2: Run test, verify it fails** — `dotnet test` → FAIL.

- [ ] **Step 3: Implement `MsiDevice.cs`** — use HidSharp `DeviceList.Local` to find by VID/PID from PROTOCOL.md, open, and `stream.Write(payload)` (or `SetFeature` per PROTOCOL.md report type). Return DeviceNotFound/SendFailed accordingly.

- [ ] **Step 4: Run test, verify it passes** — `dotnet test` → PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat(windows): add MsiDevice HidSharp transport"`.

### Task C3: System-tray app + global hotkeys

**Files:**
- Create: `windows/MsiMonitorControl/TrayApp.cs`, `windows/MsiMonitorControl/HotKeys.cs`, `windows/MsiMonitorControl/Program.cs`
- Modify: `README.md` (Windows build/run + default hotkeys)

**Interfaces:**
- Consumes: `MsiDevice`, `Command` from C1/C2.
- Produces: runnable tray app.

- [ ] **Step 1: Implement `TrayApp.cs`** — `NotifyIcon` with a context menu listing the actions, each calling `device.Send(...)`; show connected state; British-English labels.

- [ ] **Step 2: Implement `HotKeys.cs`** — Win32 `RegisterHotKey` for each command, same default chords as macOS where possible (document in README).

- [ ] **Step 3: Implement `Program.cs`** — message-loop host for the tray + hotkeys (no visible main window).

- [ ] **Step 4: Build** — `cd windows && dotnet build` → succeeds. Manual smoke test against real MD342CQP (human-run).

- [ ] **Step 5: Update README** Windows section. **Commit** — `git commit -m "feat(windows): system-tray app with actions and global hotkeys"`.

---

## Track D — CI (build-only, phase 1)

### Task D1: GitHub Actions build workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: both buildable apps. Produces: CI gate on push/PR.

- [ ] **Step 1: Write `.github/workflows/build.yml`** — two jobs: `macos` on `macos-latest` running `swift build` (and `swift test`) in `macos/`; `windows` on `windows-latest` running `dotnet build` (and `dotnet test`) in `windows/`. Triggers: `push` + `pull_request`.

- [ ] **Step 2: Push and verify both jobs go green** — fix any cross-platform build issues surfaced.

- [ ] **Step 3: Commit** — `git commit -m "ci: build macOS and Windows apps on push"`.

---

## Phase 2 (separate plan, after phase 1 verified)

Packaging + GitHub Releases: macOS `.app`/`.dmg`, Windows `.exe`/installer, published on tag push via Actions (free on public repos). Apps unsigned — README documents Gatekeeper/SmartScreen bypass. Not part of this plan.

---

## Self-Review

- **Spec coverage:** 4 actions (B2/C1 Command enum ×6 covers on/off/USB-C/Upstream/Type-C/DP); hotkeys (B4/C3); HID protocol + PROTOCOL.md single-source (A1/B1, consumed by C1); monorepo layout (A1); tested-vs-may-work + safety note (A1 README); build-only CI (D1); phase 2 deferred (noted). British English + MIT + targets in Global Constraints. ✓
- **Dependency:** C-track tasks require B1's PROTOCOL.md. Stated at track headers. ✓
- **Placeholder scan:** byte arrays are intentionally `/* bytes */` because they're extracted in B1 from the live reference — the plan instructs teammates to copy them verbatim and to flag (not invent) any UNKNOWN payload as a Needs-decision. This is a deliberate hardware-derived value, not a lazy placeholder. ✓
- **Type consistency:** macOS `MSIDevice.send(Command) -> Result<Void, MSIError>` and Windows `MsiDevice.Send(CommandKind) -> MsiResult` mirror each other; `Command`/`CommandKind` six cases consistent across B2/C1. ✓

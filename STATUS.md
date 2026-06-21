# STATUS — msi-monitor-control

**Created:** 2026-06-22

## Current focus
Phase 1 (Functional MVP) just kicked off. Two teammates building against
`docs/superpowers/plans/2026-06-22-msi-monitor-control.md`:
- **msi-mac** — Track A (scaffold), Track B (macOS app), `docs/PROTOCOL.md`, D-macos CI.
- **msi-windows** — Track C (Windows app), D-windows CI. Blocked on PROTOCOL.md until B1 lands.

## Blockers
- Windows payload tasks (C1+) need `docs/PROTOCOL.md` from macOS Task B1 first.
- Any HID payload not discoverable in the reference repo → Needs-decision (do not invent).

## Next steps
1. msi-mac: scaffold + extract payloads → PROTOCOL.md.
2. msi-windows: project skeleton + tray shell while waiting, then payloads once PROTOCOL.md lands.
3. Build-only CI green on both platforms.
4. Human smoke-test on the real MD342CQP.

## Decisions (with why)
- **Raw USB HID, not DDC/CI** — reference repo (Phaseowner/MSI-Display-Switch) is HID and lists
  MD342CQP as tested; input switching from it briefly worked on the user's monitor.
- **Monorepo** — keeps the two platforms in sync via a shared PROTOCOL.md.
- **Phase 1 build-only CI, phase 2 = installable releases** to GitHub Releases (unsigned, documented).

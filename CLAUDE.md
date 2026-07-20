# msi-monitor-control — repo instructions

Public open-source monorepo (MIT, © LogicalSapien) for a dual-platform utility that
controls an **MSI MD342CQP** monitor over **raw USB HID** (NOT DDC/CI).

## Layout
- `macos/` — Swift / SwiftUI menu-bar app (owns the protocol reverse-engineering)
- `windows/` — C# / .NET 8 system-tray app (HidSharp)
- `docs/PROTOCOL.md` — **single source of truth** for the HID payloads. Both apps send
  byte-identical reports sourced from here. macOS produces it; Windows consumes it.
- `docs/superpowers/specs/` and `docs/superpowers/plans/` — the approved design + plan.

## The plan
Implement strictly against `docs/superpowers/plans/2026-06-22-msi-monitor-control.md`.
Read the Global Constraints section first — it is binding on every task.

## House rules (open-source quality)
- **British English everywhere**: docs, UI copy, code identifiers, commit messages.
- **No internal ticket/tracker references anywhere** — commit messages, docs, code
  comments. This is a public repo; internal IDs mean nothing to outside readers.
  (Overrides the workspace-level ticket-reference rule.)
- MIT licence, © LogicalSapien. Public repo — keep the code clean and reviewable.
- Minimal diffs, minimal components. No over-engineering, no speculative flexibility.
- Reverse-engineered payloads: **never invent bytes.** If a payload can't be found in the
  reference, flag it as UNKNOWN / Needs-decision — do not ship a guess.
- Tested model = MD342CQP only. Other MSI models are "may work, unverified" (README).

## Workflow
- Everything via Git + GitHub. CI (build-only in phase 1) runs on push/PR.
- This is desktop software — there are no servers to touch.
- Update `STATUS.md` before going idle.

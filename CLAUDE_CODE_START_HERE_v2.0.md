# CLAUDE CODE — START HERE (Rentro v2.0)

**Read in this order:**

1. `RENTRO_PRD_v2.0.md` — complete product requirements and acceptance tests.
2. `FIGMA_SCREEN_MANIFEST_v2.0.json` — exact source IDs, Light/Dark pairings and all 39 supplied references.
3. `FIGMA_SCREEN_MATRIX_v2.0.csv` — flat route-to-Figma lookup.
4. `V1_TO_V2_CHANGELOG.md` — intentional changes from the previous PRD.

## First instruction to Claude Code

```text
You are working on the existing Rentro iOS application. Do not rebuild or delete existing functionality without reviewing the current repository.

Read RENTRO_PRD_v2.0.md and FIGMA_SCREEN_MANIFEST_v2.0.json fully. Compare the current Xcode/SwiftUI project, assets, SwiftData schema, Sign in with Apple capability and any existing CloudKit configuration against the PRD. Write a short discrepancy and implementation plan before modifying code.

Implement incrementally by P0/P1, preserving existing functionality. Treat canonical Figma node IDs in the manifest as the appearance source of truth for the screen variants, use T01–T05 dedicated tracker designs, and use the BRAND section for wordmark/intro/icons. Recreate native layouts, not screenshots.

Bottom navigation MUST be exactly Home, Rentals, Devices, Map, Settings, using native SwiftUI TabView and native Apple toolbar/navigation/back behavior. Use semantic Light/Dark colors (teal/green, never default blue), SF Pro UI typography, SF Pro Rounded wordmark and SF Symbols. Group aligned label-value rows with real stacks and right-aligned trailing columns; all tappable controls >=44pt except where the native system controls own geometry.

Use SwiftData as the P0 source of truth, Sign in with Apple for authentication, and CloudKit only where sync/sharing is required. Do not fake Find My APIs, promise always-live location or bypass consent. Trackers use public Core Location best-effort with explicit disclosure and revocation. Native LaunchScreen stays static; optional brand intro is a non-blocking first-run in-app animation and respects Reduce Motion.

Begin with a repository inventory, then implement the smallest complete verified vertical slice. Run the build and tests that are actually available; never claim success for tests not run. For every touched screen provide Figma node ID, Light/Dark screenshots, functional test results, and unresolved differences.
```

## Mandatory source/precedence rules

- Figma page: https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-578&m=dev
- Admin: `FLOW · LIGHT · Rentro` `48:3304` and Dark `48:3305`, do not use original Page 1 as primary.
- New Rental: S05-S08 four screens, NOT legacy `New Rental · LEGACY REFERENCE` frames.
- Tracking: use dedicated T01–T05 frames, not duplicate generic HIG tracking route views when they conflict.
- Branding: `BRAND · Rentro Identity & Launch` `58:4299`.
- Existing 39 references include components/sections, NOT 39 full pages.
- Many Figma source labels are sample values. Use live backend data after repository and configuration work.

## Phase gates

**Phase A · Existing repo and design:** Audit implementation, make routing/token/component plan, retain working code. Implement brand and native UI shells with screenshots and preview fixtures.

**Phase B · Business P0:** Sign in with Apple, Keychain session state, SwiftData schema/migrations, booking constraints, rental lifecycle, manual payments/deposit ledger, Settings, alerts, all required validation/tests.

**Phase C · Tracker P1 PoC:** Distinct sandboxed tracker target, pairing/consent/permissions, recent map, diagnostics/revocation. Test on real devices; no 24/7 telemetry promise.

**Phase D · Hardening/P1:** CloudKit sharing/role testing, reports, exports, accessibility, localization, security, TestFlight.

## Completion report template

```text
Routes implemented:
Figma IDs verified (Light / Dark):
Existing code kept / modified:
New files and migrations:
Build commands executed + results:
Tests executed + results:
Known limitations / blocked external setup:
Next accepted task:
```

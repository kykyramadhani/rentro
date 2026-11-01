# Localization (en + id)

- Catalogs: `Apps/RentroAdmin/Resources/Localizable.xcstrings`, `Apps/RentroTracker/Resources/Localizable.xcstrings`, `Apps/RentroTracker/Resources/InfoPlist.xcstrings` (permission texts).
- English is the source language; Indonesian lives in `scripts/id_strings.py` (single source of truth).
- Workflow after changing UI text: build both apps with `-derivedDataPath build` → `scripts/sync_strings.sh` → add `id` text to `scripts/id_strings.py` → `python3 scripts/apply_id.py` (fails on a missing key or a changed `%@`/`%lld` specifier) → rebuild.
- Rules: SwiftUI literals localize themselves; `String`-typed values need `String(localized:)`; stable data keys (event type, checklist keys) stay English and only their display text is localized.
- Verified: both apps build with `id.lproj`; UI tests launch in Indonesian (tab bar, tracker pair screen); Home, Rentals, Settings read in Indonesian on the simulator (`Docs/screenshots/id/`).
- Not verified: a full visual pass of every screen in Indonesian; translations are machine-quality and have not been reviewed by a native speaker; plural forms use explicit one/other keys, not catalog plural variations; dates/numbers follow the device locale.

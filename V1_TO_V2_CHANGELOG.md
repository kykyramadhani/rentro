# Rentro — PRD v1.0 → v2.0 change log

| Priority | Change | Engineering effect |
|---|---|---|
| Required | Figma HIG duplicate page `43:578` is now canonical | Stop mapping to old `3:* / 6:*` Page 1 for new screens |
| Required | 37 admin route descriptions now have verified Figma links | Pixel/detail screenshot testing per route; S19 is embedded sheet |
| Required | Four-step New Rental wizard is canonical | Do not implement legacy combined New Rental mockup as the flow |
| Required | Settings fifth tab has designed screens | Replace More label and symbol everywhere; 7 grouped detail routes |
| Required | Apple iOS 27 native toolbar/bottom tab visual rules | Use SwiftUI system views rather than screenshot assets/manual control geometry |
| Required | Row/capsule alignment/HIG audit is in source | Implement real shared aligned rows, 48pt fields/buttons, 44pt minimum tap targets |
| Required | Tracker frames T01–T05 are real assets | Use dedicated design variants for tracker and explicit consent state handling |
| Required | Brand uses SF Pro Rounded wordmark | Install Light/Dark brand assets/components in Sign In |
| Required | Static launch vs animated brand intro distinction | LaunchScreen is OS static, animated intro only inside app where context warrants |
| Required | App icon Light/Dark 1024 artboards | Export appropriate assets; verify clear/tinted variations per platform/toolchain |
| Required | v1 business rules retained | Atomic booking constraint, precise IDR ledger and deposits, consent-based location/RLS |
| Additional | 20 new tests AT-31–AT-50 | Visual quality, source traceability, tracker lifecycle, HIG and brand quality gates |
| Additional | JSON/CSV Figma source manifest | Claude Code can resolve exact node pairs instead of guessing by URL order |
| Unchanged | No MDM, no Find My APIs or scraping | Apple Find My remains an external website/action |
| Unchanged | Teal/green Light/Dark semantic tokens | Default blue selected tint prohibited |

## Deliberate unresolved items

- Verify user's exact Xcode project, current branches, SDK, app group/bundle IDs and existing Supabase migrations before changing code.
- Tinted/clear icon variants are not confirmed as separate Figma source frames.
- Backend, tracker reliability, notification permissions, RLS and real-device behavior cannot be confirmed from Figma screen visuals alone.
- Brand and tracking fixture business names vary; production always uses authenticated entity name.
- Auth/password recovery, OS permissions, loading/empty/error dialogs are required even where not modeled as unique Figma artboards.

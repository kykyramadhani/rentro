# RENTRO — PRODUCT REQUIREMENTS DOCUMENT (PRD)

**Version:** 2.0  
**Updated:** 25 October 2026  
**Status:** Implementable specification, Figma-mapped; real device/backend verification outstanding  
**For:** Product owner, Claude Code, SwiftUI engineers, QA and privacy reviewers  
**Original:** Updated from `RENTRO_PRD_v1.0.md`—this replaces, rather than supplements, its outdated Figma screen-status assumptions.  
**Canonical Figma page:** [Rentro · HIG Audit & Missing Screens](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-578&m=dev)

> **Implementation contract:** This document describes required behavior. Figma defines the look of verified screens. These are **not** 39 different screens: the 39 supplied links resolve to **2 sections containing 41 Light + 41 Dark frames**, 10 dedicated T01–T05 tracking frames, shared icon/search/wordmark components, one audit board and one branding section. A legacy New Rental frame in each flow is for reference only, and must not replace the current four-step rental wizard. Do not treat static Figma examples as real data.

> **Existing code first:** Inspect and preserve any currently working Rentro code/repository before implementing changes. No project deletion, large-scale rewrite, or recreation of existing functionality without technical justification.

---

## 0. What changed since PRD v1.0

| Area | v1.0 | v2.0 source / required change |
|---|---|---|
| Figma coverage | 6 types / 12 core frames, other features concept-only | 41 paired canonical Light/Dark frames (one legacy pair); 37 admin route specs with one embedded map sheet, five tracker screens, plus brand assets |
| Navigation | Intended fifth tab Settings | Settings now visibly designed. Use **Home · Rentals · Devices · Map · Settings**; legacy component names containing `More` are deprecated |
| Top navigation | Generic HIG requirements | Reuse Apple **iOS 27 Toolbar - Top - iPhone** visual pattern; native SwiftUI `NavigationStack`/toolbar on-device |
| Forms/rows | Generic 4-pt grid | Preserve measured center alignment, 48-pt fields/buttons, grouped settings, 44-pt hit targets and right-aligned value columns; scale with Dynamic Type |
| Branding | Generic Rentro title/icon | Reusable SF Pro Rounded Heavy `Rentro` wordmark, static launch preview, optional Motion brand intro, Light/Dark monogram `R` app icons |
| Tracker | Concept design gap | Dedicated T01–T05 Light/Dark references verified; consent, pairing, diagnostics, revoke and best-effort transport remain P1/experimental |
| Prototype | Specified routes | Figma interactive prototyping exists, but is **not** a backend/functional test. Build actual navigation/state in SwiftUI |
| Readiness | v1.0 PRD data model and flows | Keep booking-conflict protection, ledger separation, privacy and security; replace third-party backend assumptions with SwiftData local-first + CloudKit |

**Source-precedence order:** (1) this PRD for state, business logic and safety; (2) canonical `FLOW · LIGHT/DARK · Rentro` for admin UI; (3) dedicated `T01–T05` frames for tracker-specific UI (higher priority than generic HIG tracker duplicates); (4) `BRAND · Rentro Identity & Launch` for wordmark, icons and introductory motion; (5) Apple HIG/native APIs when Figma uses demo elements or conflicts with runtime system behavior. Explicit questions/assumptions are logged, not silently guessed.

---

## 1. Product definition

### 1.1 Vision
Rentro helps an Indonesian iPhone rental business run its daily operations in one native iOS app: register devices, manage customers, create and complete rentals, track pickup/return times, manage payments and deposits, inspect a consent-based **last-known-location fleet map**, and open Apple's Find My separately if a device needs recovery assistance.

### 1.2 Who it serves
- **Owner:** administers the business, sees fleet, money, staff, tracking and settings.
- **Staff:** handles checkouts/returns, customer records and permitted payments.
- **Viewer (future):** can observe assigned operational information without edits.
- **Renter:** is the recipient of the rental, not an administrator or regular logged-in Rentro business user.
- **Rental-device user:** interacts with the tracker onboarding and permission/consent UI on the rented iPhone.

### 1.3 Jobs to be done
1. Know which iPhone is available for a requested time slot.
2. Create a booking in a few clear, validated steps.
3. See who holds a rented iPhone and when it must return.
4. Record real pickup and actual return accurately; calculate charges transparently.
5. See income, outstanding balance and refundable deposits without mixing them.
6. See the last reported location **and timestamp** of paired iPhones, without falsely claiming continuous live GPS.
7. Quickly open Find My for manual recovery support.

### 1.4 Decisions already finalized
| Decision | Requirement |
|---|---|
| Name | Rentro |
| Main navigation | **Home, Rentals, Devices, Map, Settings** |
| Tab five | **Settings**, NOT More; `gearshape` / `gearshape.fill` SF Symbol |
| Design style | Teal minimal, white/off-white surfaces, rounded native iOS UI, 4-point spacing grid |
| Color theme | Semantic Figma variables; System / Light / Dark appearance; **green/teal accent only**, no blue selected tab |
| Typography / symbols | SF Pro via `.system(...)`; SF Symbols via `Image(systemName:)` |
| Tab bar | Native SwiftUI `TabView` with system Liquid Glass behavior on supported iOS, not a hand-drawn clone |
| Location | Companion app using public Core Location APIs and meaningful consent, updates are **best effort**, not guaranteed live |
| Find My | Button opens `https://www.icloud.com/find` as an external Apple service; **no API-level device lookup**, no automated single-device selection |
| MDM | **Explicitly excluded** (no enrollment, no remote locking/wiping) |
| Apple Accounts | Do not require Apple Account credentials, do not embed Apple Find My web UI or scrape iCloud |
| Currency | IDR; display `Rp 250.000`; currency amounts stored exactly, never binary float |
| Localization | Match English Figma copy in initial UI, structure strings for Indonesian localization; localize dates/amounts appropriately |
| Business tenancy | One business per owner for MVP, but database includes `business_id` everywhere and supports expansion |

### 1.5 Scope/priority codes
- **P0:** must work in usable rental-management MVP.
- **P1:** needed for complete proposed V1, after P0 is stable.
- **P2:** future, not to be quietly implemented without approval.
- **Experimental:** must be validated on real devices; no promise of 24/7 performance.

**P0:** auth, business profile, Home, customers, inventory, availability, rental wizard, rental detail, pickup, return, pricing, payments/deposits, alerts for due/overdue, Settings, theme, privacy/security baseline, mocked-but-explicitly-labeled location empty states, Find My shortcut.  
**P1:** paired tracker, live-updating last-known map, location-status handling, device pairing, location history with limited retention, export/reports, additional staff roles.  
**P2:** multi-business subscriptions, customer self-service, integrated payment gateway, e-sign contracts, OCR ID, WhatsApp messaging, detailed GPS analytics, advanced fleet automation.

> **Dependency:** Location functionality is not a substitute for permission or operational safety. Delivery of the companion tracking feature is subject to iOS background-location testing, App Review rules and the lawful consent/notice flow. P0 rental management must remain fully useful without tracker access.

### 1.6 Success measures and acceptance targets
- 100% of completed rentals have a customer, unit, pickup timestamp, return timestamp, amount due and recorded payment state.
- Zero overlapping confirmed/active bookings for a single device, including concurrent submissions from two clients.
- Status derived deterministically; no late booking shown as “available” if it conflicts.
- Creating a rental normally takes no more than 5 steps from entry to confirmation.
- A location marker always shows age (e.g. “Last reported 18 min ago”); never “Online” based only on coordinates.
- No PII or location records leak between businesses or staff roles.
- All important flows usable in both appearances, VoiceOver, and with increased text size.
- Manual UX quality target: minimum 44 × 44 pt touch targets; 4-pt spacing increments except intrinsic system-layout dimensions and typography baselines.

---

## 2. Verified Figma source-of-truth, assets, and design system

### 2.1 Figma page, frame structure and interpretation

- File: `CPVUgH5MmmOvlx3ArxEF94`, page `43:578` (`Rentro · HIG Audit & Missing Screens`). The original Figma page is a design baseline, **not** the primary implementation source.
- Main navigation flows: `FLOW · LIGHT · Rentro` (`48:3304`) and `FLOW · DARK · Rentro` (`48:3305`), each with 41 frame layouts. Each includes a **legacy New Rental reference**; prefer the separate four-step current flow.
- Additional dedicated tracker screens: `T01–T05` in Light and Dark, outside the main flows. These are the **preferred tracker visual variants**; functional tracker requirements remain governed by section 6 and iOS permission policies.
- Brand section `58:4299` (`BRAND · Rentro Identity & Launch`) includes static launch previews, motion intros and two 1024-square icon source frames.
- Audit board `44:4318` contains design rationale/checklists, **not** an app screen.
- Many of the 39 user-listed nodes are component masters. A component reference is **not** a new route. See Appendix A for every supplied link.

### 2.2 Canonical admin & supporting route map

`Embedded` means part of another screen and not a separately pushed screen. Each route below has both Light/Dark visual references.

| Route | Screen | Priority | Light Figma | Dark Figma | Coverage |
|---|---|---|---|---|---|
| S00 | Native launch / startup gate | P0 | [58:4312](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=58-4312&m=dev) | [58:4316](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=58-4316&m=dev) | Brand launch mockup |
| S01 | Sign In | P0 | [44:578](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-578&m=dev) | [44:1289](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1289&m=dev) | Verified screen |
| S02 | Business Setup | P0 | [44:606](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-606&m=dev) | [44:1317](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1317&m=dev) | Verified screen |
| S03 | Home / Dashboard | P0 | [43:579](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-579&m=dev) | [43:1054](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1054&m=dev) | Verified screen |
| S04 | Rentals list | P0 | [43:684](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-684&m=dev) | [43:1159](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1159&m=dev) | Verified screen |
| S05 | New Rental / Customer | P0 | [45:578](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-578&m=dev) | [45:919](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-919&m=dev) | Verified screen |
| S06 | New Rental / Device & Schedule | P0 | [45:670](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-670&m=dev) | [45:1011](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1011&m=dev) | Verified screen |
| S07 | New Rental / Price & Payment | P0 | [44:1202](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1202&m=dev) | [44:1913](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1913&m=dev) | Verified screen |
| S08 | New Rental / Review | P0 | [44:1243](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1243&m=dev) | [44:1954](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1954&m=dev) | Verified screen |
| S09 | Rental Detail | P0 | [44:640](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-640&m=dev) | [44:1351](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1351&m=dev) | Verified screen |
| S10 | Pickup / Check-out | P0 | [44:688](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-688&m=dev) | [44:1399](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1399&m=dev) | Verified screen |
| S11 | Return / Check-in | P0 | [44:730](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-730&m=dev) | [44:1441](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1441&m=dev) | Verified screen |
| S12 | Extend Rental | P0 | [44:781](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-781&m=dev) | [44:1492](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1492&m=dev) | Verified screen |
| S13 | Cancel Reservation | P0 | [44:818](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-818&m=dev) | [44:1529](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1529&m=dev) | Verified screen |
| S14 | Devices list | P0 | [43:779](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-779&m=dev) | [43:1254](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1254&m=dev) | Verified screen |
| S15 | Device Detail | P0 | [43:955](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-955&m=dev) | [43:1431](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1431&m=dev) | Verified screen |
| S16 | Add / Edit Device | P0 | [44:851](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-851&m=dev) | [44:1562](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1562&m=dev) | Verified screen |
| S17 | Device Maintenance | P0 | [44:887](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-887&m=dev) | [44:1598](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1598&m=dev) | Verified screen |
| S18 | Fleet Map | P1 | [43:883](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-883&m=dev) | [43:1358](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1358&m=dev) | Verified screen |
| S19 | Device map bottom sheet | P1 | [43:883](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-883&m=dev) | [43:1358](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1358&m=dev) | Embedded in S18 |
| S20 | Location History | P1 | [45:704](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-704&m=dev) | [45:1045](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1045&m=dev) | Verified screen |
| S21 | Customers | P0 | [44:931](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-931&m=dev) | [44:1642](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1642&m=dev) | Verified screen |
| S22 | Customer Detail | P0 | [44:969](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-969&m=dev) | [44:1680](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1680&m=dev) | Verified screen |
| S23 | Add / Edit Customer | P0 | [44:1011](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1011&m=dev) | [44:1722](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1722&m=dev) | Verified screen |
| S24 | Payments & Deposits | P0 | [44:1048](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1048&m=dev) | [44:1759](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1759&m=dev) | Verified screen |
| S25 | Record Payment | P0 | [44:1090](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1090&m=dev) | [44:1801](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1801&m=dev) | Verified screen |
| S26 | Deposit Settlement | P0 | [44:1126](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1126&m=dev) | [44:1837](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1837&m=dev) | Verified screen |
| S27 | Alerts | P0 | [44:1163](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1163&m=dev) | [44:1874](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-1874&m=dev) | Verified screen |
| S28 | Settings | P0 | [43:4387](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4387&m=dev) | [43:4751](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4751&m=dev) | Verified screen |
| S29 | Business Profile | P0 | [43:4487](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4487&m=dev) | [43:4851](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4851&m=dev) | Verified screen |
| S30 | Rental Rates & Policies | P0 | [43:4521](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4521&m=dev) | [43:4885](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4885&m=dev) | Verified screen |
| S31 | Appearance | P0 | [43:4558](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4558&m=dev) | [43:4922](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4922&m=dev) | Verified screen |
| S32 | Notifications | P0 | [43:4591](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4591&m=dev) | [43:4955](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4955&m=dev) | Verified screen |
| S33 | Team & Permissions | P1 | [43:4634](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4634&m=dev) | [43:4998](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4998&m=dev) | Verified screen |
| S34 | Privacy & Data | P0 | [43:4667](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4667&m=dev) | [43:5031](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-5031&m=dev) | Verified screen |
| S35 | About & Support | P0 | [43:4712](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-4712&m=dev) | [43:5076](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-5076&m=dev) | Verified screen |
| S36 | Reports & Export | P1 | [45:737](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-737&m=dev) | [45:1078](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1078&m=dev) | Verified screen |

### 2.3 Dedicated tracker frame mapping

For tracker implementation, prioritize these independently designed T-frames over the visually different generic `HIG / Pair Device`, `HIG / Tracker Home`, etc., which remain supplementary references.

| Tracker route | Primary Light | Primary Dark | Secondary Light | Secondary Dark |
|---|---|---|---|---|
| T01 · Pair Device | [44:4000](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4000&m=dev) | [44:4026](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4026&m=dev) | [45:771](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-771&m=dev) | [45:1112](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1112&m=dev) |
| T02 · Tracking Consent | [44:4052](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4052&m=dev) | [44:4085](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4085&m=dev) | [45:795](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-795&m=dev) | [45:1136](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1136&m=dev) |
| T03 · Tracker Home | [44:4118](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4118&m=dev) | [44:4150](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4150&m=dev) | [45:827](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-827&m=dev) | [45:1168](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1168&m=dev) |
| T04 · Tracker Diagnostics | [44:4182](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4182&m=dev) | [44:4225](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4225&m=dev) | [45:856](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-856&m=dev) | [45:1197](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1197&m=dev) |
| T05 · Unpair Tracker | [44:4268](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4268&m=dev) | [44:4293](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4293&m=dev) | [45:894](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-894&m=dev) | [45:1235](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=45-1235&m=dev) |

### 2.4 Verified local design tokens/components

- `Rentro · Semantic Colors`: **50 COLOR variables** in `Light` and `Dark` modes. Bind/translate as semantic Color assets, never reproduce inline hex on every view.
- `Rentro · Typography`: native SF Pro family token, modes `Light`, `Dark`.
- `Rentro · Layout`: five layout variables including `space/4`, `space/8`, `space/12`, `radius/12`, and `radius/16`; use 4-pt rhythm while permitting intrinsic Dynamic Type growth.
- Reusable `Rentro / Search Field` master `43:1588`, 346×48 Figma reference, real native `magnifyingglass`, clear/edit/cancel interaction and accessible placeholder.
- Apple iOS 27 official library references for status bar, top toolbar/back/title and bottom tab Liquid Glass. **In SwiftUI use native APIs**, never draw status bar time, battery or Dynamic Island.
- KPI icon component masters for available, rented, pickup, return, warning and phone in Light/Dark. SF Symbols on production UI, not generic Unicode pictograms.
- Navigation component masters with `More` in their filename (`43:1576`, `43:1586`) are **legacy only**. Product route and visible fifth tab must be named `Settings`, symbol `gearshape.fill`, accent green/teal.
- Canonical Light/Dark core screens are 390×844 mockups only; layout must adapt to real iPhone geometry, text sizes and safe areas.

### 2.5 UI system implementation constraints

1. Native `TabView` (five tabs), `NavigationStack`, `.toolbar`, list/form structure, `sheet`, `confirmationDialog`, and MapKit; don't copy Figma toolbar/status-bar pixels into production content.
2. Green/teal app accent in both appearances; system-blue selection must not leak into tabs, navigation links or controls.
3. Use SF Pro for UI and the Figma SF Pro Rounded Heavy **wordmark asset/treatment** for branding. SF Symbols must come from system symbols or exact licensed assets; do not use emoji/fake glyphs.
4. 4-pt spacing increments for designed gaps/paddings (4/8/12/16/20/24/32), standard 48-pt textfield/button patterns, **at least 44×44-pt interaction targets**. Let native system dimensions override visual pixel-matching when needed.
5. All one-line card/field text **vertically centered**. Two-column summary rows: left label, trailing value right-aligned, matching baseline/optical center; no unintended vertical wrapping of money/timestamps. Two-line title/subtitle rows vertically center the combined text stack.
6. Use Auto Layout patterns in Figma as a *behavioral hint*: SwiftUI stacks, grid, alignment guides, readable constraints; not absolute 390-wide geometry.
7. Layout after safe-area insets; no manually fixed top status bar or bottom home indicator. Hero surfaces and list scroll behavior respect native bar overlap.
8. `System | Light | Dark` preference; default System. Semantic colors, sheets, alerts, search keyboard, maps and status surfaces must switch consistently.
9. Search, filters, badges and cards are truly interactive. All lists support meaningful loading, populated, empty, filtered-empty, permission denied, offline, and error/retry states.
10. Respect Dynamic Type, VoiceOver, accessibility values, bold text, Reduce Motion, Reduce Transparency and minimum contrast. Labels never rely solely on color. On larger fonts, allow multiline/wrapping and height expansion rather than clipping.
11. No `More` tab, no extra Customers/Payments tabs, no duplicated app navigation bars on pushed screens.
12. User-entered or server-loaded values replace demo text/names and local preview counts in production; fictitious unit positions cannot be shown as live map data.

### 2.6 Design components to build in SwiftUI

`RentroWordmark`, `BrandMonogram`, `RentroColorTokens`, `RentroSearchField`, `RentroTabScaffold`, `RentalCard`, `DeviceCard`, `FleetKpiCard`, `StatusPill`, `SectionHeading`, `RentroFormField`, `AlignedLabelValueRow`, `TwoLineTrailingRow`, `PaymentAmountRow`, `CustomerRow`, `AvailabilityNotice`, `PrimaryAction`, `DestructiveAction`, `EmptyState`, `ErrorRetryState`, `OfflineBanner`, `MapDeviceMarker`, `LocationFreshnessBadge`, `DeviceInfoBottomSheet`, `TrackerHealthRow`, `PermissionExplainer`, `ConfirmationSheet`, `AnimatedBrandIntro`. These must have previews in Light/Dark, long-content and accessibility sizes.

## 3. Information architecture and navigation

```text
Root
├── Unauthenticated
│   ├── Welcome / Sign in
│   └── Create business / accept team invite
├── Admin authenticated: TabView
│   ├── Home
│   │   ├── Due Today / Overdue summary
│   │   ├── Activity / Alerts
│   │   └── Create Rental (sheet)
│   ├── Rentals
│   │   ├── Search + filters
│   │   ├── Rental Detail
│   │   │   ├── Pickup / check-out
│   │   │   ├── Extend rental
│   │   │   ├── Return / check-in
│   │   │   ├── Record payment / deposit action
│   │   │   └── Cancel rental
│   │   └── New Rental wizard (sheet)
│   ├── Devices
│   │   ├── Search + filters
│   │   ├── Device Detail → Map / Find My external
│   │   ├── Add / Edit Device
│   │   ├── Set maintenance / condition
│   │   └── Pair tracking device
│   ├── Map
│   │   ├── Device search / filters
│   │   └── Device location sheet → Device Detail
│   └── Settings   [must replace old More]
│       ├── Business Profile
│       ├── Rental Rates & Policies
│       ├── Appearance
│       ├── Notifications
│       ├── Team & Permissions (P1)
│       ├── Privacy & Data
│       ├── About / Support
│       └── Sign Out
├── Secondary accessible routes
│   ├── Customers → customer list/detail/create/edit
│   ├── Payments & Deposits → ledger/record/refund
│   ├── Alerts / Notifications center
│   └── Reports / Exports (P1)
└── Paired rental-device experience (distinct authorized role / recommended distinct app target)
    ├── Pair device with one-time code/QR
    ├── Explain and request OS location authorization
    ├── Tracking status / consent management
    └── Troubleshooting / Unpair
```

**Routing principle:** selected tab and navigation stack retain state while switching tabs. Sheets dismiss back to the originating context. A detail view is not an extra sixth tab. Settings is the sole fifth tab. Contextual links into Customers, Payments and Alerts do not invent new tabs.

---

### 3.1 Updated launch and deep-link routing

```text
OS static LaunchScreen (no animation)
  → App route gate (restore secure session, business, device role)
    → Unauthenticated admin: [optional first-run Brand Intro] → Sign In → Business Setup → Home
    → Authenticated admin: last appropriate tab / NavigationStack (skip intro)
    → Paired tracker target: Tracker Home, or Pair if unpaired
    → Invalid/revoked session: secure Sign In (no protected content flash)
```

**Do not force every returning user through splash animation.** The Figma prototype (static launch → motion intro → Sign In) demonstrates branding, not a mandatory startup delay. Persist session-aware destination and respect Reduce Motion.

### 3.2 Primary actionable flows from verified screen references

- **New rental:** `S04/S03 → S05 → S06 → S07 → S08 → S09`. Back preserves draft. Confirm is server-authoritative and idempotent.
- **Handover:** `S09 reserved → S10 → S09 active`. Return: `S09 active → S11 → S09 completed`; deposit settlement handled separately by `S26`.
- **Extensions/cancel:** `S09 → S12` with conflict check; `S09 reserved → S13` with destructive confirm and financial/audit consequences.
- **Fleet:** `S14 → S15 → S18/S20`; `Open Find My` is external and not a location lookup API.
- **Finance:** `S24 → S25/S26`; reports in `S36` after P0 ledger is reliable.
- **Customers:** `S21 → S22 → S23` or `S21 → S23`; from S22 new rental enters S05 with selection.
- **Settings:** `S28 → S29–S35`; saving data returns to root/back context, tab state persists.
- **Companion:** `T01 → T02 → system prompt → T03 → T04/T05`; tests must include revoke, permission-denied and app-background degradation.

## 4. Core business rules (normative)

### 4.1 Entities and identifiers
- Business ID: UUID; readable business name.
- Device ID: UUID; **Unit Code** e.g. `IP-001` unique within business. Model, storage, color, serial/IMEI (sensitive), photos, purchase/maintenance state.
- Customer ID: UUID; customer contact, address/notes only if needed; minimize sensitive identity documents.
- Rental ID: UUID + readable `RNT-000123` generated server-side per business, never user-entered.
- All timestamps: UTC at rest, shown using a **business-configurable timezone** (default `Asia/Makassar` is reasonable for Bali, not a fixed assumption for all businesses).
- All money: exact IDR decimal/integer; no floating-point for ledger calculations.
- All price/deposit/rate data snapshotted into rentals at booking so later rate changes don't alter history.

### 4.2 Rental lifecycle
**Persisted workflow state**: `draft` (local only), `reserved`, `active`, `completed`, `cancelled`.  
**Derived badges**: `upcoming` = `reserved` with future pickup; `due_today` = active due today in business timezone; `overdue` = active and now later than expected end; `returned` = completed.

Allowed transitions:
```text
draft → reserved → active → completed
              ↘ cancelled
reserved → cancelled
active → completed (including overdue)
```
Do NOT create an `overdue` stored lifecycle state unless it is strictly synchronized; derive from time and `active`. A device can be **maintenance / inactive / retired** independently of rental state; don't merge them.

### 4.3 Availability and date rules
- A device is bookable only when enabled, not under maintenance covering the rental period and without overlapping `reserved`/`active` rentals.
- Intervals are half-open `[pickup_at, expected_return_at)`, so same-time handover boundaries are not automatically overlapping; operational turnaround buffer is configurable.
- The domain layer must revalidate booking conflicts immediately before save. For local-only MVP this occurs inside the SwiftData write transaction; when CloudKit sync is enabled, incoming remote changes must trigger post-merge conflict detection and an explicit resolution state rather than silent double-booking.
- `expected_return_at` must be after `pickup_at`; neither can be ambiguous/unparseable, and business timezone must be recorded.
- Reserved does not imply picked up. Actual pickup sets `actual_pickup_at` and `active`. Actual return sets `actual_return_at` and `completed`, updating device state accordingly.
- Do not delete completed/cancelled rentals from history; allow notes and compensating transactions.

### 4.4 Duration and pricing
- Rental period: `durationMinutes = ceil((end - start)/60 seconds)`, but price billed according to the configured **rate unit** and rounding policy.
- Recommended default: `daily` rate, every started 24-hour period counts as one day. Minimum 1 day; business can change hourly/daily rates per device.
- Formula: `base = billableUnits * rateSnapshot`; `subtotal = base + addons - discounts`; `totalCharges = subtotal + lateFees + damageFees`; `balanceDue = totalCharges - netAppliedPayments`.
- Deposit is **held liability**, not rental income. Deposit collected/returned/partially withheld is tracked separately with ledger entries.
- Rounding, discounts, late-fee grace and damage charges must be configurable and disclosed on transaction detail. Do not silently charge fees without confirmation.
- User can override the quoted price only with appropriate permission and a required reason captured in audit log.

### 4.5 Payment rules
- Payment methods: `cash`, `bank_transfer`, `e_wallet`, `other`; record references and timestamps.
- Payment states are derived: `unpaid`, `partial`, `paid`, `overpaid`; refunds and deposits are separate transactions.
- Financial list distinguishes `rental payment`, `deposit received`, `deposit refunded`, `deposit deduction`, `manual adjustment`.
- No actual payment-gateway processing in P0: record manual payments only and label appropriately.

### 4.6 Location state and truthful freshness
**Do not implement `FindMy.getDevices()` or scrape Apple's iCloud/find web app.** Rentro's map only uses coordinates explicitly received from a paired, permission-granted companion app.

Default freshness definitions (settings can adjust later):
- `recent`: location timestamp ≤ 5 minutes ago.
- `aging`: 5–30 minutes old.
- `stale`: > 30 minutes old.
- `never_reported`: no usable coordinate.
- `permission_required`: location authorization denied/restricted/unknown, as explicitly reported.
- `unreachable/unknown`: tracker hasn't checked in; **do not claim powered off** without evidence.

Display “Last reported X min ago”, source, accuracy where provided, and device unit code. Never say “Live”, “Currently here”, “Online” or “Offline” solely because a pin exists or doesn't exist. Show stale markers dimmed, and allow a list-only alternative.

### 4.7 Notification rules
- Pickup reminder and return reminder can be configured relative to deadlines; default relative choices e.g. 24h, 2h.
- Overdue alert generated when active rental crosses `expected_return_at`, with idempotency key. No hourly duplicate spam.
- Missing location alerts **must require a configurable threshold and an enabled consent-based tracker**; no false theft claims.
- Push must be optional and permission requested contextually; in-app notification center remains available if push denied.

### 4.8 Privacy and safety
- Tell rental-device user **who receives location, what is collected, why, when tracking starts/stops, retention duration, and how to revoke permission/contact owner** before the OS prompt.
- Respect OS authorization and allow tracking to be disabled. If disabled, admin sees clear degraded state; no covert bypass.
- Device tracking should normally be limited to the agreed rental period or a clearly disclosed operating context; never harvest renter movement indefinitely.
- Do not automatically lock, wipe, or initiate police/recovery actions from overdue thresholds. There is **no MDM**.
- Shared Apple Account across rented phones carries privacy/synchronization risks. Rentro must not request Apple Account passwords, handle iCloud Photos, or rely on shared Apple Account integration.
- Sensitive ID/serial/IMEI/customer notes access is restricted by role. Avoid storing KTP photo until a separate privacy/security review.

---

## 5. Screen-by-screen functional PRD — Admin iOS

All 37 route contracts below are retained and updated from v1.0. Figma mapping in section 2.2 supersedes older inline source IDs. Every screen below defines: **Priority**, **entry**, **visible UI**, **actions**, **validation/edge states**, and **acceptance checks**. Unless stated otherwise, all screens must work in Light/Dark appearance, Dynamic Type, reduced motion, VoiceOver and offline/degraded contexts. `Loading`, `Empty`, `Error` and `No results` are not optional placeholder omissions.

### S00 — OS Static Launch & startup route gate [P0; Figma 58:4312 / 58:4316]
- **Entry:** cold start, deep link, return from background.
- **UI:** static Apple LaunchScreen storyboard/background derived from Figma brand palette, not an animation. Optional `B02` in-app brand intro after launch on appropriate first-run paths only; then secure session restore/progress if needed.
- **Logic:** if signed out → S01; if authenticated without business → S02; if Admin → S03; if paired Tracker identity → T03. No indefinite spinner.
- **Acceptance:** no flash of another user's content; revoked account routes to sign-in; deep link resumes after valid auth; static OS launch never blocks startup; no forced branding intro on every reopen.

### S01 — Sign in with Apple [P0; verified Figma 44:578 / 44:1289]
- **UI:** Rentro wordmark, supporting copy, native `SignInWithAppleButton`, legal links, loading/error states. Remove email, password and “Forgot password” from the implementation even if an older Figma snapshot still shows them.
- **Actions:** authenticate with Apple using `AuthenticationServices`; persist the stable Apple user identifier and app session metadata in Keychain; sign out locally; handle credential revocation/invalid state.
- **Validation:** prevent double-submit, handle cancellation separately from failure, never log authorization codes/identity tokens, and do not assume Apple returns name/email after the first successful authorization.
- **Routing:** authenticated owner without a business → S02; authenticated owner with an existing local/cloud business → S03.
- **Acceptance:** no email/password auth exists; protected screens cannot appear before a valid Apple credential state is resolved; relaunch restores the correct route; revoked credentials return to Sign in with Apple without exposing prior protected content.

### S02 — Business Setup [P0; verified Figma 44:606 / 44:1317]
- **UI:** business name, WhatsApp/phone (optional), address/city (optional), IANA timezone, currency IDR, default day rate and late-fee policy, owner confirmation.
- **Actions:** create business, join existing business by verified invite (P1), skip optional fields.
- **Acceptance:** business is created transactionally with current user as owner; store business timezone and P0 defaults.

### S03 — Home / Dashboard [P0; verified Figma 43:579 / 43:1054]
- **UI:** teal hero with greeting + search component, KPI grid (`Total devices`, `Currently rented`, `Available`, `Overdue`), `Today's activity`, prominent contextual “New Rental” action, bottom tab bar.
- **Actions:** tap KPI → corresponding filtered list; tap activity → rental detail; search global devices/customers/rentals; create rental; open Alerts.
- **Rules:** device totals count distinct enabled inventory; rented count actual active; overdue derived at render; available considers current booking/maintenance; today's pickup/return uses business timezone.
- **Empty:** “No activity scheduled today”; all-zero dashboard suggests “Add your first device”.
- **Acceptance:** KPIs reconcile with underlying queries; all rows open relevant detail; no dead `View all` text; amounts/counts refresh after pickup/return.

### S04 — Rentals list [P0; verified Figma 43:684 / 43:1159]
- **UI:** search, filter pills `All`, `Active`, `Upcoming`, `Overdue` (with counts optional), list of cards showing customer, unit, booking code, key timestamps and status; `New` action.
- **Actions:** search customer/booking/unit; choose filter; sort by next action, scheduled date or newest; tap card; create rental.
- **Rules:** `Overdue` filter uses computed derived state; `Active` excludes overdue only if UX explicitly describes it (recommended: active includes overdue, Overdue is targeted subset).
- **Empty:** “No rentals yet” + Create Rental; “No overdue rentals” with calm success neutral state; filtered no result differs from global empty.
- **Acceptance:** filter and search compose; keyboard dismisses; pagination; statuses correct after time change and returning from detail.

### S05 — New Rental / Customer [P0; verified Figma 45:578 / 45:919]
- **UI:** navigation title `New Rental`, 1 of 4 step indicator, existing customer picker/search, selected customer summary, `Add Customer`, Continue.
- **Actions:** select or create; draft persists until exit; back/cancel with discard confirmation.
- **Validation:** exactly one customer required; customer must belong to current business.
- **Acceptance:** cannot continue without customer; returning from Add Customer selects saved customer.

### S06 — New Rental / Device & Schedule [P0; verified Figma 45:670 / 45:1011]
- **UI:** device picker with available inventory, date/time pickup and return, duration preview, availability messages.
- **Actions:** choose device, change period, inspect conflict if unit unavailable, continue/back.
- **Validation:** end > start; device is bookable for entire interval plus policy turnaround; cannot accept past pickup unexpectedly without explicit immediate-rental path.
- **Acceptance:** quote recalculates from schedule; exact conflict shown with actionable alternate device/time; backend repeats validation when confirming.

### S07 — New Rental / Price & Payment [P0; verified Figma 44:1202 / 44:1913]
- **UI:** rate snapshot, billable units, subtotal, optional addon/discount, security deposit, expected total, amount paid now, payment method, payment note.
- **Actions:** edit discount with permission, record initial payment, continue.
- **Validation:** no negative values except explicit discount adjustment, discount cannot exceed approved policy; deposit is not double-counted in total charges.
- **Acceptance:** all totals deterministic; formatted IDR; partial payment allowed if business rules permit.

### S08 — New Rental / Review [P0; verified Figma 44:1243 / 44:1954]
- **UI:** customer, unit, dates, fee breakdown, deposit, payment status, policy/disclosure acknowledgement, Confirm Rental.
- **Actions:** edit each section, confirm once; show success with “View Rental” and “Start Pickup”.
- **Validation:** rerun conflict check in server transaction; show explicit conflict if availability changed; idempotency protects against double-tapping.
- **Acceptance:** one new `reserved` rental + snapshot + associated payment entries, or no partial records on failure.

### S09 — Rental Detail [P0; verified Figma 44:640 / 44:1351]
- **UI:** rental code, status, primary next action, customer contact, device link, schedule (planned vs actual), cost breakdown, payments, deposit, policy/notes, event timeline.
- **Actions:** Pickup if reserved; Return if active; Extend if active and permitted; Record Payment; Cancel if reserved; contact customer with confirmation; open device detail.
- **States:** reserved/active/overdue/completed/cancelled render different actions; expired/missing customer shows consistent record snapshot.
- **Acceptance:** event history auditable; no incorrect buttons for terminal state; editing permissions enforced server-side.

### S10 — Pickup / Check-out [P0; verified Figma 44:688 / 44:1399]
- **UI:** customer/unit confirmation, planned pickup vs actual time, condition notes, checklist (screen, cameras, battery, accessories), optional photos, confirm handover.
- **Actions:** mark checklist, confirm actual pickup, cancel.
- **Validation:** reservation exists; device not already active with another rental; condition checklist required if policy says so.
- **Acceptance:** atomic `reserved→active`, sets `actual_pickup_at`, updates availability, app offers pairing/tracker status when configured.

### S11 — Return / Check-in [P0; verified Figma 44:730 / 44:1441]
- **UI:** actual return time, device/condition confirmation, fees from late duration, optional damage charge with reason, final amount due, collected payments, deposit settlement instructions.
- **Actions:** confirm return, optionally record payment, go to deposit refund, mark maintenance if device needs repair.
- **Validation:** active rental only; return time cannot precede pickup; any charge override requires reason; show outstanding balance.
- **Acceptance:** atomic transition to completed; device available unless maintenance; actual duration persisted; deposit stays held until explicitly settled.

### S12 — Extend Rental [P0; verified Figma 44:781 / 44:1492]
- **UI:** original return, proposed new return, added billable units, added charge, customer confirmation note.
- **Actions:** preview extension, confirm.
- **Validation:** extend only future to later time, check next reservations and policy conflicts, no silent override.
- **Acceptance:** old/new deadlines stored in audit trail; alerts rescheduled idempotently; total recalculated from existing rate snapshot and policy.

### S13 — Cancel Reservation [P0; verified Figma 44:818 / 44:1529]
- **UI:** reason, refund/deposit information, destructive confirmation.
- **Actions:** cancel from reserved state only; initiate manual refund entry if needed.
- **Acceptance:** releases future slot; keeps booking and transaction history; active rental requires a return/incident flow, not cancel.

### S14 — Devices list [P0; verified Figma 43:779 / 43:1254]
- **UI:** shared search component, filters `All`, `Available`, `Rented` (additional `Maintenance` in optional overflow), device cards with model, unit code, storage, rental status, Add Unit.
- **Actions:** search model, unit code or last 4 of serial where allowed; tap detail, add unit, change filter.
- **States:** not paired tracker must not make device disappear from inventory.
- **Acceptance:** filters reflect current time and inventory state; no booking conflict hidden; Add Unit works.

### S15 — Device Detail [P0; verified Figma 43:955 / 43:1431]
- **UI:** device identity, status, current renter / due date if active, condition, latest location age and accuracy, short location preview, `View Map`, `Open Find My`, Edit, tracking status.
- **Actions:** map focuses this unit; Find My launches Apple site separately; add/edit; reserve; mark maintenance; pair/unpair tracker (P1).
- **States:** no location → “No location received”; permission missing → “Location permission required”; stale → honest timestamp and badge.
- **Acceptance:** direct Find My shortcut is external and never claims official integration; only authorized staff see IMEI/serial and customer contact.

### S16 — Add / Edit Device [P0; verified Figma 44:851 / 44:1562]
- **UI:** Unit Code, model preset/free text, capacity, color, optional serial/IMEI, optional image, default rental rate, deposit, condition, active flag.
- **Actions:** save, cancel, choose photo from Photos/camera with correct permission handling, retire (not hard delete if history exists).
- **Validation:** Unit Code unique per business, supported model/capacity sane, serial not required; avoid storing unrelated Photos metadata.
- **Acceptance:** card list updates; prior rental invoices remain unchanged after editing current device rate.

### S17 — Device Maintenance [P0; verified Figma 44:887 / 44:1598]
- **UI:** status `Available / Maintenance / Retired`, issue description, maintenance start/end, checklist, internal notes.
- **Actions:** place in maintenance, restore to active inventory, close issue.
- **Validation:** cannot start maintenance in a way that silently invalidates confirmed rental; show impact and require resolution.
- **Acceptance:** maintenance blocks overlapping bookings; history preserved.

### S18 — Fleet Map [P1; verified Figma 43:883 / 43:1358]
- **UI:** full-screen MapKit content, translucent native controls, search field, location pins for opted-in paired devices, summary of recent/aging/stale/never reported, selectable map/list view, device bottom sheet.
- **Actions:** select pin, filter recent/stale, search device, center on all known locations, open detail.
- **Rules:** map art in Figma is only visual sample; production uses Apple MapKit. Default zoom should encompass available pins; if zero, show empty state rather than a fabricated pin. Do not obtain location via Apple Find My.
- **States:** loading, offline map, no paired devices, all stale, individual permission denied, malformed/low-accuracy coordinates.
- **Acceptance:** last-known and timestamp always visible, 100 units render without freezing, selected pin links to the correct device; map not required to make a rental transaction.

### S19 — Device map bottom sheet [P1; embedded visual in S18]
- **UI:** selected unit, current rental status, last reported timestamp, accuracy radius, permission/health indicator, “Device Details”, “Open Find My”.
- **Actions:** collapse/expand sheet, go to detail, open Apple Find My external.
- **Acceptance:** selection remains stable through Realtime updates; no reading private customer details to unauthorized roles.

### S20 — Location History [P1; verified Figma 45:704 / 45:1045]
- **UI:** short retention-limited location events list and optional map route, each point tagged with server receive time, device measurement time and accuracy.
- **Actions:** choose allowed range, show disclosure, delete/export according to retention policy.
- **Restrictions:** no covert monitoring dashboard; no history beyond disclosed retention; no interpolation as factual movements.
- **Acceptance:** “No history” meaningful; protected by business role and consent, no infinite retention.

### S21 — Customers [P0; verified Figma 44:931 / 44:1642]
- **UI:** customer search, name, phone, rental count, latest rental, Add Customer.
- **Actions:** tap detail, call/message via system handoff, add customer.
- **Acceptance:** search case-insensitive, safely handles duplicate names, no unapproved disclosure of full PII.

### S22 — Customer Detail [P0; verified Figma 44:969 / 44:1680]
- **UI:** name, contact, notes, rental timeline, active balances, edit action.
- **Actions:** edit, start new rental with customer preselected, open historical rental, anonymization/deletion request flow subject to retention obligations.
- **Acceptance:** cross-links correct; no stale rental count.

### S23 — Add / Edit Customer [P0; verified Figma 44:1011 / 44:1722]
- **UI:** full name (required), contact phone (recommended/required by policy), WhatsApp same as phone toggle, optional email/address/internal note and privacy notice.
- **Validation:** trim, normalize Indonesian phone formatting, duplicate warning (not auto merge), field length limits; no unneeded government-ID document upload in P0.
- **Acceptance:** saves once, local validation before server, user informed about intended storage.

### S24 — Payments & Deposits [P0; verified Figma 44:1048 / 44:1759]
- **UI:** ledger with dated rows, paid/unpaid balance, filters for rental payment/deposit/refund, totals as separate categories, export later.
- **Actions:** open payment, record payment, inspect deposit liability, link back to rental.
- **Acceptance:** deposits excluded from income metric; transactions cannot be silently deleted; canceled refunds represented as new entries.

### S25 — Record Payment [P0; verified Figma 44:1090 / 44:1801]
- **UI:** rental reference, amount, method, paid at, note/reference, `Save Payment`.
- **Validation:** positive amount, correct currency, staff permission, overpayment confirmation, idempotent save.
- **Acceptance:** updates payment balance and audit trail instantly; offline entry queued only with clear pending state and no fabricated “success”.

### S26 — Deposit Settlement [P0; verified Figma 44:1126 / 44:1837]
- **UI:** held amount, proposed refund, proposed documented deductions, outstanding deposit liability, method, reference.
- **Actions:** refund full/partial, deduct by authorized reason, confirm settlement.
- **Validation:** cannot refund more than held; all deductions require reason; cannot both count withheld deposit as rental payment and keep it as liability.
- **Acceptance:** bookkeeping balances and rental detail reconcile.

### S27 — Alerts [P0; verified Figma 44:1163 / 44:1874]
- **UI:** due today, overdue, pending pickup, payment due, tracking permission/stale alerts (P1); timestamps, severity and unread state.
- **Actions:** tap action → relevant rental/device; mark read; filter type.
- **Acceptance:** deep links route correctly; alert deduplication; push denied does not hide in-app alerts.

### S28 — Settings [P0; verified Figma 43:4387 / 43:4751]
- **UI:** top title **Settings** and gear SF Symbol, distinct grouped sections:
  1. `Business` → S29 Business Profile, S30 Rental Rates & Policies.
  2. `Preferences` → S31 Appearance, S32 Notifications.
  3. `Management` → S33 Team & Permissions (P1), S34 Privacy & Data.
  4. `Help` → S35 About & Support.
  5. destructive bottom row `Sign Out` with confirmation.
- **Actions:** navigate to each, sign out securely. Show business name/role near top; no unrelated “More” menu.
- **Empty:** business profile defaults available; unavailable optional features explicitly marked “Coming later” or omitted, never dead rows.
- **Acceptance:** fifth tab visually reads `Settings`, accessibility says `Settings`, icon is `gearshape`/`gearshape.fill`, selected tint is Rentro teal (NOT system blue); settings rows all work.

### S29 — Business Profile [P0; verified Figma 43:4487 / 43:4851]
- **UI:** business name, phone, address, default timezone, currency readonly IDR for P0, logo optional.
- **Actions:** edit and save with confirmation for timezone change.
- **Acceptance:** timezone controls presentation/scheduling but past UTC timestamps remain unchanged; only owner/admin can edit.

### S30 — Rental Rates & Policies [P0; verified Figma 43:4521 / 43:4885]
- **UI:** default hourly/daily rate, minimum charge, late-fee grace period, late-fee unit/amount, default deposit, turnaround buffer, optional staff override policy.
- **Actions:** modify, preview sample quote, save.
- **Acceptance:** new bookings use new policy; historical bookings retain snapped policy values; all rates nonnegative and auditable.

### S31 — Appearance [P0; verified Figma 43:4558 / 43:4922]
- **UI:** segmented or native list options `System`, `Light`, `Dark` (default System), with descriptive preview.
- **Actions:** choose preference saved in local settings; applied across entire app and sheet/popup contexts.
- **Acceptance:** changing System uses OS scheme; selection persists app relaunch; selected controls have teal, not blue. Support increased contrast and reduced transparency.

### S32 — Notifications [P0; verified Figma 43:4591 / 43:4955]
- **UI:** OS permission status, `Open iOS Settings` if denied, toggles for pickup, return, overdue and optional tracking freshness alerts, lead times.
- **Actions:** change preferences, request permission in context, test notification (optional dev mode only).
- **Acceptance:** toggles persist locally in SwiftData/AppStorage as appropriate and sync through CloudKit when enabled; the in-app alert center remains functional without push.

### S33 — Team & Permissions [P1; verified Figma 43:4634 / 43:4998]
- **UI:** owner/admin/staff membership list, pending invites, role explanation, invite by email, revoke confirmation.
- **Actions:** invite, change role, revoke with immediate session impact.
- **Validation:** cannot remove last owner; owner-only role assignment and location-visibility permission.
- **Acceptance:** CloudKit sharing/role enforcement is validated on separate Apple IDs; revocation removes future shared access and UI hiding is never treated as the authorization mechanism.

### S34 — Privacy & Data [P0; verified Figma 43:4667 / 43:5031]
- **UI:** what Rentro stores (customer info, device serial, financial data, tracking consent and last locations), retention settings, disclosure/policy link, export/delete request, role-specific location access.
- **Actions:** inspect consent history, request permitted export/deletion, open privacy/support.
- **Acceptance:** no silent location collection; permissions accurately reflect tracker status; no direct access to other businesses' records.

### S35 — About & Support [P0; verified Figma 43:4712 / 43:5076]
- **UI:** app name/version/build, support contact, legal/terms/privacy links, acknowledgement of Apple Find My external functionality.
- **Actions:** open links in system browser, contact support.
- **Acceptance:** legal links are real valid configured URLs before release, not fake placeholders.

### S36 — Reports & Export [P1; verified Figma 45:737 / 45:1078]
- **UI:** date range, currency totals for rental revenue, separate deposits, utilization by device, overdue count, generated summary, export CSV/share sheet.
- **Actions:** choose range and export via native share sheet.
- **Validation:** access authorized only; fetch/filter the permitted local or CloudKit-shared records by business/date; CSV injection is escaped.
- **Acceptance:** sums reconcile with ledger and returns; empty range says `No data for this period`.

---

### 5.1 Canonical event → destination contract (UI must never be inert)

| Source | User action | Destination / mutation | Permission / side effect |
|---|---|---|---|
| S01 | Sign In | Auth session → S02 or S03 | Auth error handled; no enumeration |
| S02 | Create Business | Atomic business + owner membership → S03 | Owner only after authenticated |
| S03 | KPI / activity / New Rental | S04/S14/S27/S09/S05 | Correct pre-filter; no dead text links |
| S04 | Select status filter / search / card / New | Filtered list / S09 / S05 | Search/filter compose, empty state and cancel |
| S05–S08 | Continue / Back / Confirm | Next/previous wizard step / S09 | Draft persisted; conflict checked at confirmation |
| S09 | Pickup / Return / Extend / Cancel | S10 / S11 / S12 / S13 | Lifecycle-gated |
| S14 | Unit card / Add | S15 / S16 | Role allows edit |
| S15 | View Location / Find My / Maintenance | S18 / external Apple website / S17 | External link clear; no Find My API |
| S18 | Select marker or result | S19 → S15 | Timestamp and accuracy truthful |
| S21–S23 | Select / create / edit customer | S22 / S23 / list | Role check and input validation |
| S24–S26 | Record / settle | Ledger mutation then contextual return | Idempotent, separate deposit accounting |
| S28 | Seven grouped rows / Sign Out | S29–S35 / session revoke | Sign Out confirmation |
| S32 | Push toggle | Authorization state & preference | iOS prompt only on intent; in-app fallback |
| S36 | Export CSV | Native ShareLink/Share Sheet | Tenant-filtered, formula injection-safe |
| T01–T05 | Pair / consent / diagnostics / unpair | tracker state machine | Paired-device auth only, background best-effort |

### 5.2 Standard screen state contract (required for **every** route)

- **Loading:** placeholders/skeletons only when justified; controls protected from double-submit.
- **Populated:** values from authenticated tenancy and backend; UI updates after successful mutation.
- **Global empty:** meaningful next action (e.g., “Add your first device,” “No rentals yet”).
- **Filtered empty:** explain that filter/search found no results and show clear/reset action.
- **Error/offline:** clear message and Retry; financial, booking and permissions screens must never misrepresent an unconfirmed mutation as success.
- **Unauthorized/not found:** explain restricted/removed record without leaking other tenant information.
- **Large Text/VoiceOver:** maintain information hierarchy; captions and amounts cannot overlap, truncate critical action labels or drift off baseline.
- **Sensitive data:** mask/restrict customer phone, identifiers, finances and locations according to role/consent.

### 5.3 Usability rules for the visually verified form/row patterns

- Form field: label above control, 48-pt reference height, 12-pt horizontal inset, `textContentType`, keyboard matching data, error and helper copy. `Return` key action predictable.
- One-line detail/money row: leading label and trailing value on the same vertical center line; value trailing alignment anchored to shared right margin.
- Two-line row: title/subtitle vertically balanced as a stack with 4-pt interline gap; chevron vertically centered to row.
- Capsules: content hugging with predictable padding, not giant fixed-width text pills; 24/28/32-pt visual pills may sit inside larger 44/48-pt interactive targets.
- Buttons: `Primary` filled brand, `Secondary` neutral surface, `Destructive` red treatment; all at least 44-pt hit region, no icon-only ambiguous button.
- Native top navigation: back/title actions implemented with system toolbar; never draw manual `‹ Back` as text in production.

## 6. Rental-device companion experience (P1, consent-based; dedicated T-frames verified)

**Packaging recommendation:** **one repository**, with two clearly segregated iOS targets sharing a Swift package (`RentroAdmin` and `RentroTracker`) to avoid exposing admin financial/customer UI on devices handed to renters. This fulfills the prior goal of a shared Swift codebase with Admin/Device experiences. A single binary with securely gated modes is possible, but not the default handoff choice. Do not accidentally ship an unprotected admin mode to rental units.

### T01 — Pair device [P1; Figma 44:4000 / 44:4026]
- **UI:** device-specific one-time QR or short code, unit name, pairing progress; no Apple Account sign-in.
- **Actions:** enter/scan code, confirm correct unit.
- **Backend:** one-time token stored **hashed**, short expiry (e.g. 10 min), device-bound association, revoked after use; admin authentication required to issue pairing token.
- **Acceptance:** expired/reused code rejected; cannot pair to another company's unit; device user never receives server secret.

### T02 — Tracking explainer, consent & OS permissions [P1; Figma 44:4052 / 44:4085]
- **UI:** plain-language disclosure naming rental business, data fields (lat/long, accuracy, timestamp, optional battery/diagnostics), purpose, visible sharing window, retention, ability to revoke consent and support contact.
- **Actions:** accept explicit tracking terms (as permitted by applicable law) and proceed to system authorization; decline with honest “Not tracking” state; open OS Settings if denied.
- **Authorization:** prefer When In Use and request extended/background privileges only when necessity demonstrated; include correct Info.plist location usage strings and background modes before enabling. Never prompt repeatedly in a loop.
- **Acceptance:** no coordinates before legally valid agreement/permission; changes of OS authorization surfaced to admin/companion without bypass attempts.

### T03 — Paired Tracker Home [P1; Figma 44:4118 / 44:4150]
- **UI:** unit identity, `Sharing / Paused / Permission Required / No recent signal`, last update time, precision status, privacy summary, support, end-of-rental date.
- **Actions:** review details, adjust permitted sharing, open diagnostics and iOS Settings, stop sharing/revoke if user controls allow.
- **Acceptance:** admin-only data inaccessible; never claims permanent background capability.

### T04 — Tracker diagnostics [P1; Figma 44:4182 / 44:4225]
- **UI:** permission and accuracy status, last GPS fix, last uploaded/acknowledged event, connectivity, battery impact guidance, troubleshooting list.
- **Actions:** send user-initiated test location after permission, retry upload, contact business.
- **Acceptance:** distinguishes GPS acquisition failure from HTTP upload failure, offline storage bounded and encrypted; no invisible tracking tricks.

### T05 — Unpair / close tracking agreement [P1; Figma 44:4268 / 44:4293]
- **UI:** unit identity, confirmation and effect on reporting, contact business.
- **Logic:** server revoke token/association, stop collection, wipe locally queued coordinates as permitted by retention policy; keep necessary audit events.
- **Acceptance:** subsequent upload rejected; device shows `Not paired`; re-pairing requires fresh approval.

### T06 — Foreground/background location transport [P1; service, not a visual screen]
- Use public Core Location APIs appropriate to targeted SDK; optional background mode only if justified, enabled and reviewed.
- **Recommended behavior:** location update on meaningful movement + app active/rental start; adaptive throttle and batching; preserve device battery; never invent a fixed 30-second telemetry SLA.
- Store `measured_at`, `received_at`, `horizontal_accuracy_m`, `permission_status`, `sharing_active`, `source`, and optional `battery_level` with explicit notice. Skip invalid points and unreasonable accuracy.
- Limited retry queue for offline uploads with exponential backoff, timestamp deduplication, maximum retained queue size and expiration.
- Do not require always-on polling, unapproved background execution, hidden installation, or bypass of force-quit/denial restrictions.
- Stop collecting when explicit consent revoked or authorized sharing period ends. A device that has been force-quit, uninstalled, turned off or denied permission **may stop reporting indefinitely**.

---

### 6.1 Verified T-frame contents and implementation details

| Screen | Verified design content | Required interaction/state not proven by Figma |
|---|---|---|
| T01 Pair | QR panel, Scan Pairing Code, manual code alternative, “pairing identifies unit; location requested separately” | Authorized QR scan, short-lived one-time code, expiry/reuse errors, business/unit confirmation |
| T02 Consent | Operational purpose, user control, retention, affirmative acknowledgement, Continue to iOS Permission | Consent version and timestamp, permission request after explanation, decline/denied path, policy link |
| T03 Tracker Home | Rentro Tracker, unit ID, `Tracking active`, last-sent age, Always permission, battery-aware updates, Diagnostics/Privacy | Distinguish genuinely active vs disabled/stale, update age from timestamps; renter can review controls |
| T04 Diagnostics | Permission, background refresh, last measurement, last upload, network, app version | Distinguish source fix from upload ACK, explain delayed background behavior, user-initiated retry only |
| T05 Unpair | Stop tracking agreement warning and Unpair Device action | Revoke upload credentials/association; stop collection; review retention rules; confirmation/cancel |

Sample business names differ between design fixtures (e.g., `Kaye Rental` and `Papa Rental`). **Neither is a product default**: render the authenticated/paired business name from stored data. Prototype counters like “2 minutes ago” are sample data and must be computed from actual events.

### 6.2 Consent model and security guardrails

- Tracker pairing credential is installation-scoped and can only write location data for its associated unit. Never copy the admin user's Sign in with Apple credentials, Keychain session material, broad CloudKit permissions or unrelated business data to the rented device.
- Authorization/consent must be explicit, scoped and revocable; separate pairing from OS permission. Requests for background tracking require an independently justified capability and App Review/privacy assessment.
- iOS background updates are energy/OS dependent; don't promise continuous delivery. Failure, missing permission, app closure, network loss or no GPS signal may mean indefinite gaps.
- No direct Apple Find My GPS feed, account credential scraping, MDM, remote wipe/lock or circumvented iOS controls. If device recovery needed, open Apple's public Find My website externally.
- Location history retention must be disclosed, configurable and deletion/revocation tested. Treat coordinates as sensitive; log only safe metadata.

## 6B. Brand identity, launch and icon assets (new in v2)

### B01 — Wordmark master (design component, not app route)

- **Figma:** Light `58:4300`, Dark `58:4302`. Brand section `58:4299`.
- **Visual:** `Rentro` typography logo using **SF Pro Rounded Heavy** with tight tracking; teal in Light, mint/green in Dark. Use the actual reusable asset/treatment in Sign In, and optionally the first-run intro. Regular body/navigation stays system SF Pro.
- **Implementation:** The wordmark is a brand component or outlined/exported vector asset as needed for stable rendering and licensing, not an arbitrary new typeface; ensure localization/accessibility name is `Rentro`.
- **Avoid:** replacing every navigation title with the brand wordmark or stretching wordmark to full viewport width.

### B02 — Static OS launch (Figma `58:4312` / `58:4316`)

- **Purpose:** seamless system-controlled app launch, not an onboarding animation or mandatory splash screen. Figma shows a centered monogram for visual intent.
- **Native:** implement a **static, appearance-adaptive** LaunchScreen. Apple guidance says launch should be subdued and visually close to the first view, avoiding advertising/long messaging. If a logo causes visible flash or delay, use a simple matched background instead.
- **Test:** fast cold start, light/dark scheme, interrupted/authenticated session; no invented progress bar.

### B03 — Optional in-app Brand Intro (Figma `58:4320` / `58:4332`)

- **Figma Motion:** halo opacity, monogram `R` scale, wordmark scale, supporting tagline opacity; actual Figma prototype transitions approximately 0.35s static launch → intro, then 1.45s intro → Sign In (demo-only timings).
- **Native implementation:** optional motion after real startup for onboarding/first install; use SwiftUI `withAnimation`/phase animation as appropriate. Respect Reduce Motion by immediately showing static content; skip when authenticated, deep-linking, or returning to an active task. Never artificially block primary actions for a set time.
- **Acceptance:** no animation is required for successful auth routing. Repeated launches restore session and go directly to the appropriate destination.

### B04 — App icon resources (Figma `58:4342` / `58:4345`)

- **Artboard:** square 1024×1024 Light and Dark source asset; large centered rounded `R` monogram, teal/mint palette. The system applies final icon masking.
- **Implementation:** provide real Xcode Assets / Icon Composer exports and configure light/dark appearance. Validate edge cropping at tiny sizes, App Store preview and OS Home Screen variants.
- **Not represented in the 39 links:** clear/tinted icon appearances may be required/supported for the chosen toolchain and minimum platform. Add/verify exact variants during asset finalization; do **not** claim Figma already has complete tinted/clear source art.
- **Acceptance:** contrast, no baked rounded mask, no screenshot raster of the 390×844 splash used as icon.

### B05 — Wordmark use on Sign In

- Current Sign In frames `44:578` / `44:1289` have the reusable wordmark instance replacing the ordinary `Rentro` title.
- Do not show two visible overlapping titles. Supporting copy, native Sign in with Apple button and legal text remain accessible and vertically balanced. Email/password/Forgot Password UI is deprecated.

---

## 7. Technical architecture and project organization

### 7.1 Proposed stack
| Layer | Technology / rule |
|---|---|
| iOS | Current stable Xcode, Swift, SwiftUI, async/await, `NavigationStack`, `TabView` |
| Deployment | Choose an SDK/deployment baseline supporting required native behaviors (prefer **iOS 26+** for Liquid Glass, with iOS 27 design reference); verify support in the installed Xcode. |
| Authentication | **Sign in with Apple only** via `AuthenticationServices`; use `SignInWithAppleButton`; store only required session/account identifiers in Keychain. No email/password auth. |
| Primary persistence | **SwiftData local-first**. Business, rentals, customers, devices, payments, deposits, maintenance, alerts and settings are authoritative locally for MVP. |
| Sync | **CloudKit** as the Apple-native sync layer when multi-device sync is enabled. MVP must remain usable without CloudKit/network for normal local CRUD. |
| Team sharing | P1: CloudKit shared/public-record design or `CKSyncEngine`/CloudKit sharing as appropriate after a dedicated collaboration design review. Do not block MVP on team cloud sharing. |
| Maps | MapKit (`Map`, annotations/selection, viewport management) |
| Location | Core Location public APIs in the isolated Tracker target only, explicit-consent gated |
| Tracker transport | Apple-native Phase 2 design using CloudKit/CloudKit-backed transport where technically appropriate; if latency/operational needs cannot be met, document that limitation before introducing any non-Apple backend. |
| Notifications | `UNUserNotificationCenter`; local notifications for deterministic due/return reminders. Remote push is optional and only added if a future CloudKit/server-triggered workflow needs it. |
| Preferences | `AppStorage` / SwiftData settings where suitable; secrets never in UserDefaults |
| UI architecture | Feature-based MVVM or unidirectional state; model-container injection and testable services |
| Media | Local file storage first; CloudKit Assets only if device-condition photos are introduced and retention/privacy rules are defined |
| Observability | Structured privacy-sanitized logs; redact customer PII, precise coordinates, Apple auth tokens and identifiers |
| Tests | XCTest/Swift Testing, UI tests, SwiftData persistence tests, CloudKit integration tests where enabled, accessibility snapshots/checklist |

**Architecture principle:** Rentro is an Apple-native, local-first application. Normal rental operations must not depend on a third-party backend. Cloud features enhance synchronization; they do not become a prerequisite for basic booking, pickup, return, customer, device or payment workflows.

### 7.2 Suggested repository structure
```text
Rentro/
├── Rentro.xcodeproj or Rentro.xcworkspace
├── Apps/
│   ├── RentroAdmin/                 # owner/staff authenticated application
│   │   ├── App/
│   │   ├── Navigation/
│   │   ├── Features/
│   │   │   ├── Auth/
│   │   │   ├── Home/
│   │   │   ├── Rentals/
│   │   │   ├── Devices/
│   │   │   ├── Customers/
│   │   │   ├── Payments/
│   │   │   ├── FleetMap/
│   │   │   ├── Alerts/
│   │   │   ├── Reports/
│   │   │   └── Settings/
│   │   └── Resources/
│   └── RentroTracker/               # paired rental-device companion target
│       ├── App/
│       ├── Pairing/
│       ├── Permissions/
│       ├── Location/
│       └── Diagnostics/
├── Packages/
│   ├── RentroDesignSystem/
│   ├── RentroDomain/
│   ├── RentroPersistence/           # SwiftData models, migrations, repositories
│   ├── RentroCloudKit/              # optional sync / sharing integration
│   └── RentroTestSupport/
├── Tests/
│   ├── Unit/
│   ├── Integration/
│   └── UITests/
├── Docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── PRIVACY.md
│   └── RELEASE_CHECKLIST.md
└── README.md
```

**Rationale:** shared domain/design system/persistence packages keep the admin app native and testable, while the isolated Tracker target receives only the minimum device/pairing/location capabilities it needs and cannot read customer or finance data.

### 7.3 Domain models — Swift conceptual interfaces
```swift
// Names and shapes are illustrative; DTOs must match actual migrations.
enum RentalStatus: String, Codable {
    case reserved, active, completed, cancelled
}
enum DeviceLifecycleStatus: String, Codable {
    case enabled, maintenance, retired
}
enum LocationFreshness: Equatable {
    case recent, aging, stale, neverReported, permissionRequired
}
struct Money: Codable, Equatable {
    let amountIDR: Int64  // exact whole-rupiah amount; never floating point
}
struct RentalPeriod: Codable, Equatable {
    let pickupAt: Date
    let expectedReturnAt: Date
}
```
`overdue` is a derived condition, not a persistable `RentalStatus` member. Use `.system` fonts and semantic colors; the app should never set global `UIColor.systemBlue` as Rentro's tint.

---

## 8. SwiftData + CloudKit data model

### 8.1 SwiftData is the MVP source of truth
Use SwiftData as the authoritative data store for normal admin operations. The user must be able to create and manage customers, devices, rentals, payments, deposits, maintenance state and settings while offline. Do not add a network repository merely to mirror local CRUD.

Suggested `@Model` entities:

| Model | Essential responsibilities |
|---|---|
| `Business` | name, phone, timezone, currency, default pricing/policy settings |
| `AppUser` | Apple user identifier reference, local role, display metadata; never store Apple auth token in SwiftData |
| `Customer` | name, phone/email/address as required, notes, created/updated timestamps |
| `RentalDevice` | unit code, model, storage, color, lifecycle status, rates, sensitive identifiers where approved |
| `Rental` | booking code, customer/device relationships, pickup/return times, status, pricing snapshot, notes |
| `RentalEvent` | append-only operational audit events such as created, pickup, extended, returned, cancelled |
| `PaymentEntry` | amount in whole IDR, method, category, timestamp, reference; append-oriented ledger behavior |
| `DepositEntry` | held/refunded/withheld events and reason |
| `MaintenanceRecord` | device, issue, open/closed state, timestamps, notes |
| `AlertRecord` | in-app alert type, source entity, due/created/resolved state |
| `TrackerPairing` | paired device identity, consent state, install identifier, revocation state |
| `LocationSample` | tracker timestamp, received timestamp, lat/lon, accuracy, freshness metadata; retention limited |
| `NotificationPreference` | local notification preferences per alert type |

### 8.2 SwiftData rules
1. Use UUID identifiers and explicit timestamps. Store absolute times as `Date`; render them using the business timezone.
2. `RentalStatus` persists only lifecycle states such as `reserved`, `active`, `completed`, `cancelled`. **Overdue is derived**, never stored as a canonical status.
3. Monetary values use whole-rupiah integer representation or `Decimal`; never floating-point `Double` for accounting values.
4. Persist the pricing snapshot on the rental so later business-rate changes do not rewrite historical transactions.
5. Prevent overlapping reservations in the application/domain transaction before save. On CloudKit merge or multi-device sync conflict, revalidate booking intervals before treating a merged reservation as valid.
6. Payment and deposit history are append-oriented. Corrections should create reversing/correcting entries rather than silently overwriting financial history.
7. Destructive deletes should be uncommon. Prefer archive/retire/cancel states where auditability matters.
8. Build explicit SwiftData schema/migration versions before shipping breaking model changes.

### 8.3 Sign in with Apple + Keychain contract
- Use `ASAuthorizationAppleIDProvider` / `SignInWithAppleButton`.
- Store the stable Apple user identifier and minimum session state in Keychain, not SwiftData/UserDefaults.
- Treat `ASAuthorizationAppleIDProvider.CredentialState.revoked` or `.notFound` as signed out.
- Name/email returned by Apple may only be available on first authorization; persist user-approved profile values separately if needed.
- Do not request unnecessary scopes. Never log identity tokens or authorization codes.
- Sign out clears local app session state but does **not** revoke the user's Apple Account globally.

### 8.4 CloudKit synchronization
CloudKit is optional for MVP and becomes the Apple-native sync layer when the same owner uses multiple devices.

Rules:
- The app remains fully functional for local CRUD when CloudKit is unavailable.
- Surface sync state only where useful; do not show false “synced” success before CloudKit confirms delivery.
- Model conflict handling explicitly for mutable settings and rental records.
- Booking availability must be revalidated after receiving remote changes.
- Do not assume CloudKit synchronization is instantaneous; Fleet Map must display last-known timestamp/freshness rather than claiming continuous realtime location.
- If SwiftData automatic CloudKit sync cannot satisfy a future team-sharing or tracker requirement, use explicit CloudKit APIs / `CKSyncEngine` in the relevant isolated feature rather than replacing the whole app persistence layer.

### 8.5 Team collaboration (P1)
MVP may be owner-only/local-first. Multi-staff collaboration is a separate P1 capability because Sign in with Apple authenticates a person but does not itself provide business membership, role propagation or shared database semantics.

When enabled:
- Every staff member signs in with their own Apple ID.
- Business membership/role (`owner`, `admin`, `staff`) is represented in the shared CloudKit collaboration model.
- Sensitive customer/device/location data is shared only through the business's authorized CloudKit share/record strategy.
- Owner revocation must remove future shared access and clear locally cached protected data as appropriate.
- Verify CloudKit sharing behavior on separate Apple IDs and physical devices before calling the feature production-ready.

### 8.6 Tracker transport (P1 / experimental)
The Tracker target is intentionally isolated. Pairing and location upload must not grant access to customer, finance or general business records.

Apple-native target architecture:
1. Admin generates a short-lived pairing challenge.
2. Tracker claims the pairing and stores scoped pairing state securely.
3. After explicit consent and iOS location permission, tracker records best-effort Core Location samples.
4. Samples are uploaded through a restricted CloudKit design (or another Apple-native CloudKit mechanism chosen during implementation).
5. Admin consumes only authorized last-known samples/history with freshness/accuracy metadata.
6. Unpair/revoke prevents future accepted uploads.

**Important:** CloudKit is not a guaranteed realtime transport. Product language remains `Last updated …` / `Last known location`, not “live GPS”, unless measured behavior justifies a stronger claim.

---

## 9. Exact user workflows / expected behavior

### F01 — Book and hand over an iPhone
1. Staff opens Rentals → New; selects/creates customer.
2. Selects a device and valid pickup/return period. UI immediately previews conflicts.
3. Reviews calculated IDR fee, optional deposit and any initial payment.
4. Confirms. The local domain transaction validates availability, creates a `reserved` rental, assigns the code and records payment entries in SwiftData; CloudKit sync, when enabled, happens afterward.
5. On arrival, staff opens booking → Pickup; checks actual condition and confirms.
6. Status changes to `active`; availability updates; today widget, customer history and booking detail refresh.
**Failure:** if a conflict is detected at final validation, show alternative options and do not persist a partial rental.

### F02 — Extend an active rental
1. Open rental detail → Extend.
2. Change end time and read new quote, including any next-booking warning.
3. Confirm only after the domain layer revalidates the new interval against current local/merged bookings. Audit old/new terms and adjust local notification schedule.
**Failure:** overlapping later reservation prevents extension with a clear next step.

### F03 — Return and settle
1. Rental detail → Return.
2. Enter actual return and condition; app calculates late/damage amounts per saved policy, with overrides requiring reason.
3. Confirm return; record outstanding payment separately if needed.
4. Settle held deposit (refund/withhold with reason) as separate ledger entries.
5. Device becomes available (or maintenance), booking becomes completed.
**Failure:** payment gateway not applicable in P0; never pretend manual bank transfer was verified automatically.

### F04 — Open fleet map
1. Map tab shows latest accepted points (P1) and freshness summary.
2. Tap pin → selected-device sheet with last reported time and accuracy.
3. Tap Device Details → device page, or Find My → Apple web app.
**Failure:** if no coordinates or denied permission, show list with `No location received`, never fake a map pin.

### F05 — Pair and disclose tracker
1. Admin generates limited one-time code for a specific unit.
2. Rental-device companion receives code and displays business/consent disclosure.
3. User explicitly proceeds to Apple location permission. App starts only permitted reporting.
4. Backend validates, stores latest location, admin map displays last known position and age.
5. User revokes sharing or pairing expires/ends → reporting stops and admin sees state.
**Failure:** force-quit/offline/permission denied = stale/unknown, not silent bypass.

### F06 — Settings appearance
1. Settings → Appearance → choose System/Light/Dark.
2. All tabs, overlays, navigation text and status styles adapt immediately; teal remains selected accent.
3. Restart app; choice persists.

---

## 10. Standard states, copy and accessibility

### 10.1 Required empty/error copy (examples)
| Context | Preferred copy | Action |
|---|---|---|
| No devices | “No devices yet” / “Add your first rental iPhone to get started.” | Add Device |
| No rentals | “No rentals yet” / “Bookings you create will appear here.” | New Rental |
| Empty month | “No rental data for this period.” | Change Date |
| No customers | “No customers yet” | Add Customer |
| No map data | “No locations received yet” / “Pair a device and enable location sharing to show a last-known location.” | Pair Device |
| Stale location | “Last reported 2 hours ago — may no longer be current.” | Device Details |
| Permission denied | “Location sharing is off for this device.” | View Instructions |
| Filter returns none | “No matches” / “Try another search or filter.” | Clear Filters |
| No finance rows | “No payments recorded for this period.” | Change Dates |
| Offline | “You're offline. Showing saved information.” | Retry |
| Backend error | “Couldn't load data. Try again.” | Retry |
| Conflict | “This iPhone is already booked for these dates.” | Change Device/Time |

### 10.2 Accessibility and internationalization
- VoiceOver: accessible labels include device model + unit code + status + last location timestamp; don't announce unlabeled floating icons.
- Buttons are real controls, not tappable text-only decorations; keyboard focus and Switch Control should work.
- Respect Dynamic Type. Cards/chips may grow beyond fixed reference values when text size increases; do not clip customer name or status.
- Status communicated by text and icon, never color alone. Support increased contrast and reduced transparency.
- Times displayed explicitly with dates and business timezone; never show “today” ambiguously across timezones.
- Store strings in `String Catalog` / `Localizable.xcstrings`; English matches Figma, prepare `id-ID` translations. IDR formatted with Foundation `NumberFormatter` / modern FormatStyle.
- On first use of sensitive permissions, display native and contextual explanation, not deceptive dialogs.
- Accessibility identifier naming follows `rentro.{screen}.{control}` for test automation.

### 10.3 Offline behavior
- Cached pages may show old data with time annotation; transactions that require exclusive resource availability cannot be declared successful before server confirmation.
- For draft rental editing, keep local drafts protected; final `Confirm` requires network to enforce availability.
- Manual payment entry while offline can be a clearly labeled unsent draft; it must not alter authoritative ledger until server confirms.
- Tracker queues limited authorized events and uploads later, preserving original measured times.

---

## 11. Definition of Done / quality gates

### 11.1 Functional
- Every P0 screen renders with a real navigation path, no inert Save/Create/View all/Find My/Settings controls.
- Every create/edit/delete/confirm operation has a loading, success and error path; all destructive operations need confirmation.
- Rental flows work start-to-finish with seeded customer and device; audit event trail is accurate.
- Server rejects overlapping bookings even under parallel API calls; Time Zone and DST behavior tested where applicable.
- Payment totals, deposit liability and overdue charges reconcile in unit + integration tests.
- All P1 tracking maps truthfully indicate last-known and permission states.

### 11.2 UI / visual
- Compare each of the six **existing** screens to the corresponding Figma Light/Dark frame; use screenshots for iterative visual QA.
- New screens inherit tokenized teal cards and the exact same search, status and navigation language.
- Tab five says **Settings**, shows SF Symbol `gearshape` / `gearshape.fill` and is accessible as “Settings”.
- No default blue controls or Liquid Glass selected tint; official SF Symbols only.
- 4-point spacing system, except automatic system typography/layout or accessible growth; no awkward fixed-width capsule padding.
- Correct safe-area behavior with keyboard, Dynamic Island, compact devices and bottom tab bar.
- Unit/integration/UI tests cover Light/Dark and large type; VoiceOver check on core journeys.

### 11.3 Privacy/security
- Apple authentication material belongs in Keychain; never log identity tokens or authorization codes.
- CloudKit sharing/record permissions and local role checks are validated for owner, admin, staff, tracker and cross-business cases when collaboration is enabled.
- Consent is explicit, reviewable and revocable; no tracking before authorization and no covert workarounds.
- Retention, account/data deletion requests and audit trail documented; no location logs in analytics.
- Stale location never represented as fresh; “Find My” acts only as an external shortcut.

### 11.4 Performance/reliability test budget (targets, not guarantees)
- With 100 devices and a realistic network, fleet map initial cached display should be responsive and marker updates should not block scrolling; measure and profile in Instruments.
- Main list operations use pagination and indexed queries; loading UI indicates progress.
- Retry network requests with bounded backoff; idempotency prevents duplicate rents/payments.
- Measure companion GPS battery impact on physical rented iPhones before release; do not commit to fixed update intervals until tested.

### 11.5 Real-device test matrix
- Small and large iPhones; latest supported release; portrait, keyboard, large Dynamic Type.
- Auth expiry, user role revoked, fresh app install, resumed auth deep link.
- Two staff booking same device same time.
- Midnight and timezone boundaries; rental end at exact next booking start.
- Deposit refunded full/partial; partial payment and payment reversal.
- Location When In Use, denied, restricted, reduced accuracy, Always (only if justified), background, app killed, force-quit, phone restarted, offline/network restoration.
- iOS Settings change for permission; de-enrollment/revocation; stale updates and out-of-order coordinates.
- HIG test: tab remains navigational, modal forms respect top/bottom safe areas, screenshots visually match frames.

---

## 12. Build sequence for Claude Code (strict order)

### Phase 0 — Scaffold and tokenized UI [P0]
- Inspect repository and existing Xcode project; do not destroy user code.
- Set up `RentroAdmin`, reusable `RentroDesignSystem`, typed navigation and domain models.
- Establish semantic Light/Dark color assets using Figma names; root teal tint; SF Pro/SF Symbols; native tab bar with **Settings**.
- Implement all 6 existing visual screens with deterministic local fixtures **first**, mark fixtures dev-only; screenshot QA both themes.
- Implement the common reusable search field, status chips, cards, loading/empty/error UI.

### Phase 1 — Apple auth, SwiftData and core business workflow [P0]
- Implement Sign in with Apple using `AuthenticationServices` and Keychain-backed session state. Remove email/password/Forgot Password flows.
- Add SwiftData schema, versioned migration plan, repositories and deterministic test fixtures.
- Implement customers/devices CRUD, availability validation and conflict-safe rental creation locally.
- Implement new-rental steps, rental detail, pickup, extension, cancel and return.
- Implement payment/deposit ledger with financial tests, dashboard derived KPIs and local alerts.
- Implement Settings, business policy, appearance and notifications screens.
- Make offline/local operation the default; no third-party backend dependency for P0.

### Phase 2 — CloudKit sync + Tracker proof of concept [Experimental → P1]
- Enable/test CloudKit synchronization for the owner’s multi-device use case without breaking local-first operation.
- Introduce isolated companion target and shared domain/CloudKit package.
- Create pair/consent/permissions/status UIs and a restricted Apple-native pairing/location transport design.
- Pilot on **two actual iPhones** through movement, stationary periods, screen lock, foreground/background, interrupted connectivity and permission changes.
- Validate privacy notice and App Review suitability before wide rollout.
- Only then enable fleet live-updating last-known pins; preserve no-data/unknown states.

### Phase 3 — Operational maturity [P1]
- Multi-staff permissions, reports/exports, richer alerts, diagnostics, location history with retention, automated test hardening.
- Release readiness, privacy disclosure, monitoring, build/archive/TestFlight and App Store compliance.

### Deliverables after EACH phase
1. Compiling Xcode project / working target(s).
2. SwiftData schema/migration tests, and CloudKit integration checks when sync features are affected.
3. Unit tests and UI tests (or explicit statement of environment inability to run simulator, with commands).
4. Screenshots for Light/Dark of every changed visual route, matched against exact canonical Figma node IDs.
5. Change summary with files changed, implemented requirements/PRD IDs, known limitations, next tasks.
6. No fake production data and no claims of successful simulator/device build without executing it.

---

## 13. Acceptance test scenarios (minimum automation inventory)

| ID | Scenario | Expected outcome |
|---|---|---|
| AT-01 | Owner signs in with Apple and sees own business | Valid Apple credential restores the correct local/cloud business; protected data is not shown before credential state resolves |
| AT-02 | New business has 0 devices/rentals | Empty states with working Add Device/New Rental |
| AT-03 | Create valid rental | Exactly one reserved rental, quote snapshot and accurate availability |
| AT-04 | Booking conflict after local/CloudKit merge | Conflict is detected/revalidated; no silent double-booking and no partial rental state |
| AT-05 | Confirm pickup | Actual time stored, status active, device rented |
| AT-06 | Cross overdue threshold | Derived overdue shown; one deduped overdue alert |
| AT-07 | Return with late fee | Accurate invoice, device state updated, event logged |
| AT-08 | Refund security deposit | Liability decreases, revenue unaffected |
| AT-09 | Extend into next reservation | Rejected with next-rental collision |
| AT-10 | Cancel upcoming reservation | Slot released, history retained |
| AT-11 | Switch tab Home→Settings | Fifth tab Settings shows proper icon, no More UI |
| AT-12 | Appearance System→Dark→Light | All components and sheets change scheme; teal remains accent |
| AT-13 | Search no matches | “No matches” and Clear Filters function |
| AT-14 | Denied notifications | Alerts accessible inside app; OS Settings link works |
| AT-15 | Valid consented tracker upload | Latest device position updated with correct timestamp and accuracy |
| AT-16 | Location point measured 2 hours ago | Pin marked stale; no “live” language |
| AT-17 | Revoke permission | Ingest stops, admin sees permission/unknown state |
| AT-18 | Duplicate/out-of-order location event | Latest snapshot not rolled back |
| AT-19 | Tap Find My | Opens Apple website externally without sharing Apple credentials |
| AT-20 | Staff attempts owner-only shared-data edit | Collaboration/role layer denies the change; local UI hiding alone is not treated as authorization |
| AT-21 | Unshared Apple account attempts to access another business share | CloudKit sharing/record permissions do not expose the other business data |
| AT-22 | Unit with maintenance conflict | Can't be booked; helpful message |
| AT-23 | Large Text/VoiceOver | Labels accessible; critical actions not clipped |
| AT-24 | Offline create/confirm rental | Succeeds locally after conflict validation against available local data; sync state is honest and future remote conflicts are surfaced on merge |
| AT-25 | Manual payment double tap/retry | Exactly one idempotent ledger entry |
| AT-26 | Customer with duplicate name | Search disambiguates by contact, no silent merge |
| AT-27 | Settings timezone changed | Display shifts without mutating stored UTC moments |
| AT-28 | Dark Fleet Map with no reports | No fake pins, correct map/list empty state |
| AT-29 | Return deposit is withheld | Requires reason, audit trail, correct accounting |
| AT-30 | Logout | Protected data and session not visible after relaunch |

### Additional v2 acceptance scenarios (brand, HIG, tracker reference consistency)

| ID | Scenario | Expected outcome |
|---|---|---|
| AT-31 | Light/Dark Sign in with Apple | Wordmark appears once; native Sign in with Apple button is accessible; no email/password/Forgot Password controls |
| AT-32 | Returning signed-in owner relaunches | No forced 1.45s intro; prior role/route restored securely |
| AT-33 | Reduce Motion enabled | Optional intro motion skipped/reduced; auth and navigation unaffected |
| AT-34 | Native static launch | OS launch is static; no Motion timeline attempted in LaunchScreen |
| AT-35 | App icon source export | 1024×1024 asset(s), square before system mask, correct appearance selection |
| AT-36 | App Settings fifth tab | All routes/VoiceOver labels say Settings; no More tab or blue selected tint |
| AT-37 | Native navigation push/back | Standard SwiftUI back/toolbar behavior and correct parent destination; no drawn back text |
| AT-38 | Row/capsule alignment | Left/right values share optical baseline; no unintended vertical value wrapping; capsule content centered |
| AT-39 | Search long placeholder & clear | Search remains usable under Dynamic Type, keyboard and long localized strings |
| AT-40 | T01 code reuse/expiry | Rejected without pairing or access to business data; user can retry |
| AT-41 | T02 consent withheld | No location collected/uploaded, OS request not bypassed; tracker shows blocked state |
| AT-42 | T03 stale location | Tracker status reflects last ACK/measurement truthfully, not fake “active” |
| AT-43 | T04 measurement != upload | Both ages shown independently and upload failure surfaced |
| AT-44 | T05 unpair token replay | Old tracker token rejected; no future data accepted for revoked association |
| AT-45 | T-frame vs generic HIG variant | Dedicated T01–T05 visual chosen; no duplicate feature routes |
| AT-46 | Display sample company name | Real business name injected; `Kaye Rental` / `Papa Rental` only in preview fixture |
| AT-47 | Brand/System theme propagation | Launch/intro, wordmark, Settings, map, forms and icons use correct Light/Dark resources |
| AT-48 | Screen reference traceability | Every S/T/B route has Figma ID, functional tests and screenshot/QA result |
| AT-49 | Permission denial / app termination | User-visible degraded state; no claim of guaranteed background tracking |
| AT-50 | Figma snapshot drift | Code screenshots compared to targeted reference; issues tracked without changing production logic to fit sample content |

---

## 14. Explicit non-goals and prohibited shortcuts

**Not in scope:** MDM, ABM enrollment, remote lock/wipe, direct Apple Find My location integration, automated iCloud credential login, AirTag tracking, covert background surveillance, guaranteed always-live GPS, payment-gateway settlement, OCR ID/KTP storage, multi-company SaaS billing, fake GPS data in production.

**Do not:**
- Replace native icons the owner chose in Figma with emoji/Unicode text icons.
- Present Figma screenshots as an interactive working SwiftUI application.
- Create new bottom tabs for Customers or Payments.
- Rename Settings back to More.
- Invent tested Apple API abilities, reservation slots or background-location SLAs.
- Hardcode location coordinates in actual production map.
- Use uncontrolled `Double` for IDR amounts or serialize dates as ad-hoc display strings in SwiftData/CloudKit.
- Treat client-side validation or hidden buttons as security.
- Request Apple Account passwords for Find My.
- Turn denied or stale location into a “green online” success badge.

---

## 15. Open decisions and reasonable implementation defaults

These are not blockers; use defaults and isolate them as configurable values:

| Topic | Default for coding | Later owner override |
|---|---|---|
| Business timezone | `Asia/Makassar` in demo seed; editable in business profile | Yes |
| Language | English UI matching current Figma, future `id-ID` strings | Yes |
| Currency | IDR | Not in P0 |
| Rental unit | per calendar-independent 24-hour period, min 1 day | Yes |
| Overdue grace | 0 minutes initially unless configured | Yes |
| Pickup reminders | 24 hours before; in-app default | Yes |
| Return reminders | 2 hours before; in-app default | Yes |
| Location recent | ≤ 5 min | Future setting |
| Location stale | > 30 min | Future setting |
| Location history | latest only P0; historical retention default **7 days** in P1, after transparent notice | Yes, capped by policy |
| Target audience | First an individual rental business, future multi-tenant-capable architecture | Yes |
| Minimum iOS | iOS 26+ preferred for native Liquid Glass | Re-evaluate compatibility needs |
| Tracker architecture | Shared repository, distinct tracker target and admin target | Can revisit packaging |
| Photos | Device photo optional; private bucket | Yes |
| Payment | Manual cash/transfer/e-wallet bookkeeping | Gateway P2 |

**Owner-input needed before public release**, not before beginning code: final legal business entity/terms/privacy URLs, staff permission policy, fee/tax rules, location disclosure and retention review, real APNs credentials, real support contact, and Apple App Review positioning for companion app. Store them as config TODOs rather than inventing facts.

---

## 16. Reference URLs and known platform limits

- Canonical Figma page: https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-578
- Apple HIG overview: https://developer.apple.com/design/human-interface-guidelines
- Apple tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars
- Apple materials / Liquid Glass: https://developer.apple.com/design/human-interface-guidelines/materials
- Apple adapting to Liquid Glass: https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
- Core Location background updates: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- Core Location authorization: https://developer.apple.com/documentation/bundleresources/choosing-the-location-services-authorization-to-request
- Core Location efficient updates: https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently
- Required background location purpose string: https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationalwaysandwheninuseusagedescription
- Apple Find My user-facing external link: https://www.icloud.com/find

**Current implementation caveat:** Apple iOS may suspend, terminate, throttle or decline background location access, and users can revoke it. UI must make these states visible rather than treating tracking as a reliable theft-recovery guarantee. Consult current Apple docs, SDK annotations, App Review and Indonesian privacy/legal requirements at implementation/release time.

---

## 17. PRD completion checklist

- [x] Product vision, success measures and final tab names
- [x] Full function scope with P0/P1/P2
- [x] Verified verified canonical Figma screen IDs for the current Light/Dark flow
- [x] Required additional screen specifications, including **Settings**
- [x] Per-screen entry, UI/actions, validation and acceptance criteria
- [x] Explicit rental, booking conflict, return, payment/deposit rules
- [x] Consent-based companion tracking and Find My shortcut limitations
- [x] SwiftData entities, Sign in with Apple session contract, CloudKit sync boundaries and local-first architecture
- [x] Native UI/HIG, teal tokens, accessibility, empty/error/offline states
- [x] Tests and phased implementation plan for Claude Code
- [ ] Missing UI sub-states, e.g. Apple-sign-in error/revocation sheets, must be composed from the established Figma system
- [ ] Real Apple device tracking PoC — required before representing tracker as reliable
- [ ] Owner-specific legal/payment policies and release details — configure before launch

**End of PRD v2.0**



## Appendix A — Crosswalk of the 39 user-provided Figma references

These are literal Figma node IDs in the requested order. Some are component masters or sections, not app screens. A `More` in a *legacy component master name* is not permission to create a More tab.

| # | Node | What it represents | Type |
|---|---|---|---|
| 1 | [43:1530](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1530&m=dev) | KPI Icon · phone Light | Component · KPI |
| 2 | [44:4318](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4318&m=dev) | HIG Audit Summary | Audit board |
| 3 | [43:1556](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1556&m=dev) | KPI Icon · available Dark | Component · KPI |
| 4 | [43:1576](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1576&m=dev) | Navigation icon · legacy More Light | Component · deprecated label |
| 5 | [48:3305](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=48-3305&m=dev) | FLOW Dark (41 frames) | Design section |
| 6 | [43:1534](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1534&m=dev) | KPI Icon · rented Light | Component · KPI |
| 7 | [43:1546](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1546&m=dev) | KPI Icon · return Light | Component · KPI |
| 8 | [43:1549](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1549&m=dev) | KPI Icon · phone Dark | Component · KPI |
| 9 | [44:4182](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4182&m=dev) | Tracker Diagnostics Light | Screen · tracker |
| 10 | [43:1540](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1540&m=dev) | KPI Icon · warning Light | Component · KPI |
| 11 | [43:1553](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1553&m=dev) | KPI Icon · rented Dark | Component · KPI |
| 12 | [43:1537](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1537&m=dev) | KPI Icon · available Light | Component · KPI |
| 13 | [44:4225](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4225&m=dev) | Tracker Diagnostics Dark | Screen · tracker |
| 14 | [43:1559](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1559&m=dev) | KPI Icon · warning Dark | Component · KPI |
| 15 | [43:1570](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1570&m=dev) | Navigation icon · Rentals Light | Component · navigation |
| 16 | [43:1562](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1562&m=dev) | KPI Icon · pickup Dark | Component · KPI |
| 17 | [43:1565](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1565&m=dev) | KPI Icon · return Dark | Component · KPI |
| 18 | [43:1586](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1586&m=dev) | Navigation icon · legacy More Dark | Component · deprecated label |
| 19 | [43:1568](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1568&m=dev) | Navigation icon · Home Light | Component · navigation |
| 20 | [44:4150](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4150&m=dev) | Tracker Home Dark | Screen · tracker |
| 21 | [43:1584](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1584&m=dev) | Navigation icon · Map Dark | Component · navigation |
| 22 | [44:4052](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4052&m=dev) | Tracking Consent Light | Screen · tracker |
| 23 | [43:1572](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1572&m=dev) | Navigation icon · Devices Light | Component · navigation |
| 24 | [43:1574](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1574&m=dev) | Navigation icon · Map Light | Component · navigation |
| 25 | [43:1578](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1578&m=dev) | Navigation icon · Home Dark | Component · navigation |
| 26 | [43:1543](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1543&m=dev) | KPI Icon · pickup Light | Component · KPI |
| 27 | [58:4302](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=58-4302&m=dev) | Wordmark Dark | Component · brand |
| 28 | [43:1582](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1582&m=dev) | Navigation icon · Devices Dark | Component · navigation |
| 29 | [58:4300](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=58-4300&m=dev) | Wordmark Light | Component · brand |
| 30 | [43:1588](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1588&m=dev) | Search Field | Component · search |
| 31 | [43:1580](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=43-1580&m=dev) | Navigation icon · Rentals Dark | Component · navigation |
| 32 | [44:4268](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4268&m=dev) | Unpair Tracker Light | Screen · tracker |
| 33 | [44:4000](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4000&m=dev) | Pair Device Light | Screen · tracker |
| 34 | [44:4026](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4026&m=dev) | Pair Device Dark | Screen · tracker |
| 35 | [44:4085](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4085&m=dev) | Tracking Consent Dark | Screen · tracker |
| 36 | [44:4118](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4118&m=dev) | Tracker Home Light | Screen · tracker |
| 37 | [44:4293](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=44-4293&m=dev) | Unpair Tracker Dark | Screen · tracker |
| 38 | [48:3304](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=48-3304&m=dev) | FLOW Light (41 frames) | Design section |
| 39 | [58:4299](https://www.figma.com/design/CPVUgH5MmmOvlx3ArxEF94/Rentro?node-id=58-4299&m=dev) | Brand Identity & Launch | Design section · brand |

## Appendix B — Figma design fidelity & code handoff rules

1. Pull the exact current Figma nodes via Figma MCP and capture **screenshots** before implementing visual changes. Do not implement solely from node name summaries.
2. Prefer `FLOW · LIGHT / DARK` sections for main app; `T01–T05` dedicated frames for the companion tracker; `BRAND` section for assets. The two `New Rental · LEGACY REFERENCE` frames are **not** canonical wizard steps.
3. Generate token table from the Figma local variables: all 50 semantic colors; preserve separate Light/Dark modes. Convert them into named assets; no hard-coded `#0088FF`/system blue selection.
4. Reuse native Apple toolbar, back button and Liquid Glass appropriate to installed SDK rather than rasterizing or rebuilding the library's status bar/tab bar.
5. Use correct SF Symbols; manually chosen symbols take precedence over old Unicode pseudo glyphs. `Settings` replaces legacy `More` tab even where historical component master remains named `More`.
6. For each view: provide screenshot Light, screenshot Dark, preview of empty state, large Dynamic Type, device-safe insets, VoiceOver and at least one error/degraded state.
7. Validate route/back/toolbar behavior as functional UI, not just visually accurate Figma hotspots. The Figma prototype is a route reference, not the software.
8. Never use screenshot of an entire Figma screen as the SwiftUI UI. Extract/build layout/asset components; use native MapKit for real map, actual data for counts and prices.
9. Report unresolved design-to-code discrepancies with Figma node IDs and a concrete acceptance test.

## Appendix C — Provenance and implementation caveats (checked 25 October 2026)

- Apple Launch guidance: https://developer.apple.com/design/human-interface-guidelines/launching
- Apple app icons / appearance variants: https://developer.apple.com/design/human-interface-guidelines/app-icons/
- Apple Core Location background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- Apple efficient location updates: https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently
- Apple public Find My (external only): https://www.icloud.com/find
- Visual design authority: Rentro Figma page `43:578` (linked above).

**Not verified by the Figma audit:** real backend availability, current app repository build status, real Apple permission grant, TestFlight/App Review approval, accurate user location, or functioning payment collection. The PRD specifies these for engineering validation, not as completed outcomes.

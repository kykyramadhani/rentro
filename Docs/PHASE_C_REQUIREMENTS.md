# Phase C: what needs iCloud, a developer team, or real devices

Verified locally (simulator, in-process backend): pairing rules, consent gate, status truthfulness, upload queue, revoke.
Not verified until the items below exist: anything that crosses two devices or touches CloudKit.

## Needs an Apple developer team / iCloud container
- iCloud container shared by both apps, e.g. `iCloud.com.rentro.shared`.
- App IDs `com.rentro.admin` and `com.rentro.tracker` with iCloud (CloudKit) and Sign in with Apple.
- CloudKit schema deployed to Production in the CloudKit Dashboard before TestFlight.
- Entitlements: neither target has iCloud yet; `TrackerTransport` is `UnconfiguredTransport` in release builds, so pairing says "isn't available in this build yet".

## Needs real devices
- Two iPhones (admin and tracker), both signed in to iCloud.
- Background, locked-screen, force-quit, permission-revoked and offline behaviour; battery cost; the "Always" prompt.
- QR scanning (`DataScannerViewController` needs a camera; the simulator uses manual code entry).
- CloudKit sharing across two Apple IDs.

## Decisions (owner)
- **Pairing code lifetime: 1 minute** (was 10). The admin screen must show a countdown and a "new code" action.
- **All rental iPhones sign in with the same Apple ID.** This overrides PRD 4.8 ("must not rely on a shared Apple Account"); the owner accepted it.
  - It must be a **dedicated fleet Apple ID**, never the owner's personal one: anything that account syncs (Photos, Messages, Keychain, Notes) would be readable by every renter.
  - On the rental phones, turn off every iCloud sync except what the tracker needs, and wipe the phone between rentals.
  - With one identity on every phone, CloudKit cannot tell the phones apart. "This credential can only write unit X" is enforced by the app and by the admin app when it reads, not by CloudKit.
  - Intended route: the owner's Apple ID shares one CloudKit zone with the fleet Apple ID once (CKShare). Pairing a phone is then a short-lived claim record in that zone, claimed atomically (`ifServerRecordUnchanged`), with expiry judged by server timestamps, not the phone clock.
  - CloudKit has no server-side code, so the rules in `LoopbackServer` (reject after revoke, ignore invalid, never roll back the latest point) move to the admin app as the single reader.

## Open for owner
Terms/Privacy URLs, retention period review (7 days default), support contact, App Review wording for background location.

## First real-device session: switching CloudKit on
Code that exists: record layout and mapping (`Shared/CloudKitSchema.swift`, unit-tested offline), and `CloudKitOwnerGateway` / `CloudKitTrackerTransport` (`Shared/CloudKitGateways.swift`, **never run**). Both apps use them only when `CloudKitConfig.containerID` is set; it is `nil` today.

1. Create the iCloud container, register both App IDs with iCloud (CloudKit), add the iCloud entitlement to `Apps/RentroAdmin` and `Apps/RentroTracker`, set `CloudKitConfig.containerID`.
2. Run both apps once from Xcode on devices signed in to iCloud (admin: owner's ID; tracker phones: the fleet ID). Record types appear in the Development schema; check `PairingToken`, `Installation`, `LocationSample` and add queryable indexes for `Installation.deviceID`.
3. **Built but never run against iCloud (UNVERIFIED):**
   - Owner: Settings → Management → **Tracker Sync** (`FleetSharingView`). Creates the `Fleet` zone and a zone-wide `CKShare` (invite-only, `publicPermission = .none`, title "Rentro fleet") and presents `UICloudSharingController` with permissions limited to private + read/write. Shows its state: not set up / sign in to iCloud / not shared / invitation pending / shared (warns when the accepted Apple ID is read-only, because trackers must write).
   - Tracker: `CKSharingSupported` in its Info.plist, a scene delegate that receives the tapped share link and accepts it (`CloudKitFleetLink`), and a fleet-access check. The Pair screen says why pairing is unavailable (no container / not signed in to iCloud / owner has not shared yet) and disables scan and manual entry until the zone is visible.
   - Tested: the state logic, the honest states in both apps, and that an unconfigured build shows no share button. Not tested: the share itself, acceptance, `UICloudSharingController`, account status, zone visibility.
   - Things to watch on devices: the share link must be opened on a phone signed in to the **fleet** Apple ID; the owner must set the invitee to "Can make changes"; `UICloudSharingController` can need the share's root to be saved before presenting.
   - **Still not built:** admin syncs only when Map opens or Refresh is tapped (no background/foreground schedule); cloud-side deletion of `LocationSample` records older than 7 days (local history is pruned already).
4. Deploy the schema to Production before TestFlight.
5. Re-run the PRD matrix on two phones: AT-15 to AT-18, AT-40 to AT-44, plus background/force-quit/airplane-mode cases.

Known unknowns until then: iCloud sync latency (so "Last reported" can lag the phone), expiry accuracy of the 1-minute code under clock skew (judged with server timestamps by design), and whether App Review accepts the background-location justification.

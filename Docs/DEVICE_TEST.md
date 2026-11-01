# Testing on two real iPhones (iCloud on)

CloudKit is now ON in code: container `iCloud.com.rentro.shared`, entitlements in both apps (`Rentro.entitlements`, `RentroTracker.entitlements`), `CloudKitConfig.containerID` set.

## One-time setup (needs your Apple Developer account; I can't do this part)
1. Team JLQK39AS23 is set in `project.yml`. Always run `xcodegen generate` after pulling changes, or the installed app can miss its iCloud entitlement and crash at launch.
2. App IDs and the container `iCloud.com.rentro.shared` are already provisioned (signed build verified).
   - If `com.rentro.admin` / `com.rentro.tracker` are taken, change the bundle ids in `project.yml` and the container id in the entitlements + `CloudKitConfig`.
3. Real iPhones (Developer Mode on): install **RentroAdmin** on phone A (owner), **RentroTracker** on phone B (rental).
4. Phone A: iCloud signed in with the OWNER Apple ID. Phone B: iCloud signed in with the FLEET Apple ID (different account).

## Flow
1. A: Settings → Tracker Sync → Share with fleet Apple ID → send the invitation to the fleet Apple ID (Messages/AirDrop).
2. B: open the invitation link → tracker accepts the share.
3. A: Devices → a device → Pair Tracker → a code (valid 1 minute).
4. B: Pair Device → scan/enter code → accept terms → allow location → Send test location.
5. A: Map → pull refresh / reopen → the pin appears.

## Before first CloudKit use
- Development environment schema is created on first save; record types appear in CloudKit Dashboard automatically. Query fields (e.g. `recordName`, `unitCode`) may need a queryable index in the Dashboard if a fetch errors with "field not marked queryable".
- Unit/UI tests that assume "iCloud not configured" will now differ; they were not re-run for this change.
- Everything CloudKit/CKShare is untested on real hardware: expect to debug the first run.

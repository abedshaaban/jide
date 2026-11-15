# 记得 for iOS

SwiftUI + SwiftData, iOS 17+. The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` and is not committed.

## First-time setup

1. Xcode › Settings › Accounts › `+` › Apple ID. Sign in. A "Personal Team" appears.
2. `cp Local.xcconfig.example Local.xcconfig` and put your team ID in it. Find the ID with
   `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` (the `teamID` value), or in
   Xcode › target Jide › Signing & Capabilities after picking the team (then copy it from
   Build Settings › Development Team).
3. `cd ios && xcodegen generate && open Jide.xcodeproj`
4. Pick your iPhone as the run destination and press Run.
5. First install only: on the iPhone, Settings › General › VPN & Device Management › your Apple ID ›
   Trust. Also turn on Settings › Privacy & Security › Developer Mode if asked.

## Every 7 days

Free-account signatures expire after 7 days. Plug in the phone, open the project and press Run.
Same bundle ID (`com.abedshaaban.jide`), so all on-device data stays. Never delete the app.

Command line instead of Xcode:

```sh
cd ios && xcodegen generate
xcodebuild -project Jide.xcodeproj -scheme Jide -destination 'platform=iOS,name=<your iPhone>' \
  -allowProvisioningUpdates -derivedDataPath build build
xcrun devicectl device install app --device <UDID> build/Build/Products/Debug-iphoneos/Jide.app
```

## Mac app

The same target also builds as a Mac Catalyst app. It is signed to run locally, so it never expires
and does not count toward the three sideloaded apps.

```sh
cd ios && xcodegen generate
xcodebuild -project Jide.xcodeproj -scheme Jide -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build build
ditto build/Build/Products/Release-maccatalyst/Jide.app /Applications/Jide.app
```

Or in Xcode: pick `My Mac (Mac Catalyst)` as the run destination and press Run.

- Data is separate from the iPhone (no iCloud). Move it with Settings › Export backup / Import backup.
  It lives in `~/Library/Containers/com.abedshaaban.jide`.
- Install the premium Chinese voice on the Mac too: System Settings › Accessibility › Spoken Content ›
  System voice › Manage Voices.
- In a review: Space shows the answer, 1–4 rate it (Again, Hard, Good, Easy), Esc closes.

## Backup

Settings › Export backup writes one JSON file (see `shared/data/BACKUP_FORMAT.md`). Recordings are
also visible in Files › On My iPhone › 记得 › Recordings.

## Layout

- `Jide/Logic` — FSRS scheduler, pinyin, study queue, stats (no UI).
- `Jide/Models` — SwiftData models and bundled-data loading/seeding.
- `Jide/Services` — TTS, recording + pitch analysis, notifications, backup, settings.
- `Jide/Views` — screens.
- Data files come from `../shared/data` and are bundled as resources.

# Repository Guidelines

Swift 5+ client for BiliBili on Apple TV, targeting tvOS 16+. Dependencies use Swift Package Manager.

## Project Structure

- `BiliBiliGlobal/Module/`: screens for navigation, feeds, Anime, live streams, accounts, and DLNA.
- `BiliBiliGlobal/Component/`: reusable UI, feeds, video playback, danmaku, and player plugins.
- `BiliBiliGlobal/Request/`: networking, endpoint signing, cookies, and Protobuf models.
- `BiliBiliGlobal/Supporting Files/`: assets and launch storyboard.
- `DanmakuKit/`, `PocketSVG/`: vendored libraries. `fastlane/`: build automation.

## Build and Run

Open `BiliBiliGlobal.xcodeproj` in Xcode for development and debugging.

```bash
fastlane build_simulator   # Build for tvOS Simulator
fastlane build_unsign_ipa  # Build unsigned IPA for distribution
```

Physical Apple TV installations require a signed **Release** build unless debugging is explicitly requested. Replace `<UDID>` with a connected device ID:

```bash
xcrun devicectl list devices
xcodebuild -project BiliBiliGlobal.xcodeproj -scheme BiliBiliGlobal \
  -configuration Release -destination 'platform=tvOS,id=<UDID>' \
  -derivedDataPath /tmp/ATV-BilibiliGlobal-device -allowProvisioningUpdates build
xcrun devicectl device install app --device '<UDID>' \
  /tmp/ATV-BilibiliGlobal-device/Build/Products/Release-appletvos/BiliBiliGlobal.app
xcrun devicectl device process launch --device '<UDID>' \
  --terminate-existing com.etan.tv.BiliBiliGlobal
```

## Coding Conventions

Use four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` methods and properties. Match surrounding Swift style; no repository-wide formatter or linter is configured.

Reuse `BLButton.onPrimaryAction`, `BLMotionCollectionViewCell`, and `StandardVideoCollectionViewController`. Extend playback through `CommonPlayerPlugin`. Preserve native focus animations, saved tab order, and account-specific state.

## Validation

There is no automated test suite or coverage requirement. Build the Xcode project and manually exercise affected screens, focus navigation, and playback. For Anime changes, verify live API responses, combined filters/reset, pagination, schedule routing, and account switching.

## Integration Safeguards

- Keep Anime on Bilibili.com with shared cookies/access keys and the Android profile (`android_i`); do not apply `ApiRequest.sign` or mix Bilibili.tv IDs.
- Use overseas Anime home/catalog endpoints and API-provided filters. Honor `has_next`, season routes for unpublished episodes, and authoritative PGC metadata.
- Keep unsupported AVC Level 5.2 renditions disabled in quality menus and excluded from generated playlists; preserve compatible HEVC options.
- WebVTT must include `X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0`. Emit cues by start time without changing timestamps or overlaps.
- Keep credentials, captured API responses, APK research, and temporary scripts outside the repository.

## Commits and Pull Requests

Follow existing prefixes such as `feat:`, `fix:`, and `docs:` with a concise description. Keep changes focused. PRs should explain behavior changes, link relevant issues, report build/manual validation, and include screenshots for UI changes.

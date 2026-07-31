# MusicScreen

MusicScreen is a native macOS companion app and screen saver that render the current Apple Music track with the same shared SwiftUI `NowPlayingScreen`.

## Architecture

```text
Apple Music
    -> MusicScreen.app / AppleMusicProvider / NowPlayingMonitor
    -> atomic JSON metadata + separate artwork file
    -> MusicScreenSaver.saver / SharedCacheMonitor
    -> Shared/NowPlayingScreen
```

Only `MusicScreen.app` performs Apple Events automation. `MusicScreenSaver.saver` contains no Apple Music provider, `NSAppleScript`, `osascript`, or automation entitlement; it polls the read-only cache approximately once per second.

The cache is stored under the current user's home directory at:

```text
~/Library/Application Support/com.example.MusicScreen/NowPlayingCache/
    now-playing.json
    Artwork/artwork-<track-hash>.jpg (or .png)
```

The code derives the physical home URL from the current POSIX user account. This is necessary because Foundation's normal home-directory URL is redirected to Apple's host container inside `legacyScreenSaver`. No username or absolute home path is embedded. Metadata is a versioned `Codable` JSON document containing revision, track ID, title, artist, album, playback state, source, update time, and a relative artwork path. Artwork is stored separately and never Base64-encoded.

An App Group was considered first, but it is not a dependable transport for this legacy `.saver` shape: the bundle is dynamically loaded into Apple's screen-saver host, whose effective entitlements cannot include this project's App Group. The companion app therefore runs without App Sandbox and uses its app-specific Application Support directory. The saver host reads the same physical directory using public filesystem APIs. Distribution still requires appropriate Developer ID signing and notarization.

## Cache consistency and lifetime

- Artwork is atomically committed before its JSON reference.
- JSON is atomically replaced, so readers never observe a partial document.
- Artwork is written only when the track changes or its expected file is missing.
- The saver compares the JSON modification date and revision. Unchanged artwork for the same track/path is not decoded again.
- Missing or corrupt artwork produces the existing placeholder without crashing.
- Malformed JSON keeps the last successfully decoded track.
- `staleAfter` is 10 seconds. The last track is retained for a further `staleRetention` of 15 seconds, then the saver returns to its default empty screen.
- Quitting the companion app does not delete the cache.

These constants live in `Shared/Cache/NowPlayingCache.swift`.

## Screen saver implementation

`ScreenSaver.framework` remains the public macOS API for third-party programmatic screen savers in Xcode 26.6 and the macOS 26.5 SDK. The SDK framework and current Xcode Screen Saver project template are present and do not mark `ScreenSaverView` as deprecated. Apple does not publish a newer third-party extension point that replaces `.saver` bundles.

- [Apple Screen Saver framework documentation](https://developer.apple.com/documentation/screensaver)
- [Apple ScreenSaverView documentation](https://developer.apple.com/documentation/screensaver/screensaverview)

The system's `legacyScreenSaver.appex` hosts `.saver` bundles; it is an Apple component, not a target this project implements. The product does not use private frameworks or undocumented `ScreenSaverModule` APIs.

## Build and run

Requirements: macOS 14 or later and Xcode 26.6 (or a compatible Xcode with the macOS 14+ SDK). The project supports Apple Silicon and Intel.

Build the companion app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MusicScreen.xcodeproj -scheme MusicScreen \
  -configuration Debug -destination 'platform=macOS' build
```

Run `MusicScreen.app`, approve its Apple Music automation request, and leave it running while live screen-saver data is required. Its bottom-right status panel reports Apple Music connection, last refresh, cache write status, and whether screen-saver data is ready.

Build the screen saver:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MusicScreen.xcodeproj -scheme MusicScreenSaver \
  -configuration Debug -destination 'platform=macOS' build
```

Open the resulting `MusicScreenSaver.saver`, install it for the current user, then select it in **System Settings -> Wallpaper -> Screen Saver**. Preview and full-screen rendering both reuse `Shared/Views/NowPlayingScreen.swift`.

## Provider boundary

The cache writer accepts a provider-neutral `NowPlayingTrack`; it does not depend on `AppleMusicProvider`. A future Spotify provider can reuse the same writer and cache schema after the Apple Music path has been validated, without adding provider code to the saver.

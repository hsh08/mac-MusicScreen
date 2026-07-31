# MusicScreen

MusicScreen is a native macOS companion app and screen saver that render the current Apple Music or Spotify track with the same shared SwiftUI `NowPlayingScreen`.

## Architecture

```text
Apple Music or Spotify
    -> MusicScreen.app / ProviderCoordinator / NowPlayingMonitor
    -> atomic JSON metadata + separate artwork file
    -> MusicScreenSaver.saver / SharedCacheMonitor
    -> Shared/NowPlayingScreen
```

Only `MusicScreen.app` performs Apple Events automation and Spotify artwork downloads. `MusicScreenSaver.saver` contains no provider, `NSAppleScript`, `osascript`, OAuth, network code, or automation entitlement; it polls the read-only cache approximately once per second.

Spotify integration uses the installed Spotify app's public AppleScript dictionary. It reads each metadata property separately and uses the public HTTPS `artwork url`; the deprecated binary `artwork` property is not used. No Spotify Web API client, OAuth flow, client ID, client secret, token, private media framework, or undocumented API is included.

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

Run `MusicScreen.app`, approve its Apple Music and/or Spotify automation request, and leave it running while live screen-saver data is required. If access was denied, enable MusicScreen under **System Settings > Privacy & Security > Automation**. Its bottom-right status panel reports the active provider, last refresh, cache write status, and whether screen-saver data is ready.

The persisted **Music source** setting supports Auto, Apple Music, Spotify, and Demo. Auto prefers a playing provider, then the provider whose track or playback state changed most recently, then a paused provider, and finally the last successful display value. Spotify metadata remains visible while paused. Spotify artwork is fetched off the main actor with HTTPS, HTTP status, MIME type, timeout, image decoding, and 10 MB size checks; downloads and decoded data are reused in memory and stale track responses are discarded.

Build the screen saver:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MusicScreen.xcodeproj -scheme MusicScreenSaver \
  -configuration Debug -destination 'platform=macOS' build
```

Open the resulting `MusicScreenSaver.saver`, install it for the current user, then select it in **System Settings -> Wallpaper -> Screen Saver**. Preview and full-screen rendering both reuse `Shared/Views/NowPlayingScreen.swift`.

## Provider boundary

The cache writer accepts a provider-neutral `NowPlayingTrack`; it does not depend on `AppleMusicProvider` or `SpotifyProvider`. Both sources reuse the same JSON schema, artwork files, saver reader, and SwiftUI views. Provider-specific code is compiled only into the companion app.

## Tests

The `MusicScreenTests` target covers Spotify response parsing and missing values, artwork URL validation and stale response identity, Auto selection and Spotify-failure fallback, duplicate cache suppression, shared cache round trips/malformed retention, and monitor start/stop cancellation.

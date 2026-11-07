# Slipstream

A native SwiftUI Floatplane client for Mac, iPhone, and iPad. Browse subscribed creators, watch video and audio, read posts and comments, and follow live rooms with chat. This project is not affiliated with Floatplane Media.

## Build

Use Xcode 27.1 or later. Deployment targets are macOS 14 and iOS/iPadOS 17; newer APIs have runtime availability guards, but compiling the Duo hinge and control rail support requires the iOS 27.1 SDK. Mac Catalyst is disabled.

A clean checkout can build without an Apple account:

```sh
./scripts/build.sh macos --ad-hoc
./scripts/build.sh ios
swift test
```

The iOS command builds for Simulator and uses ad-hoc signing so Keychain works. It does not boot a simulator. `macos --unsigned` is also available for compile checks. Disposable Mac signatures can cause saved-session Keychain prompts after rebuilds.

For normal development, copy the local Xcode settings template:

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Set your bundle identifier, development team, and optionally a persistent Mac development certificate. `Config/Local.xcconfig` is ignored by Git and works in both Xcode and the scripts. Open `Slipstream.xcodeproj`, select **Slipstream** or **Slipstream-iOS**, and run. For a physical iOS build, use `./scripts/build.sh ios-device -allowProvisioningUpdates`.

The scripts also accept exported environment variables, or a trusted `.env.local` copied from [.env.example](.env.example). Explicit environment variables take precedence over `.env.local`; command-line Xcode build settings take precedence over both. Xcode does not read dotenv files itself.

```sh
SLIPSTREAM_BUNDLE_ID=com.yourcompany.Slipstream ./scripts/build.sh ios
BUILD_NUMBER=2 ./scripts/testflight.sh archive ios
./scripts/testflight.sh upload ios
```

See [configuration](docs/Configuration.md) for all overrides and [distribution](docs/TestFlight.md) for local and CI signing.

## Development

See [Contributing](CONTRIBUTING.md) for focused checks, PR requirements, and uploading before/after evidence. Agent guidance lives in [AGENTS.md](AGENTS.md).

`project.yml` is the source of truth for project structure. The generated Xcode project and package lockfile are committed so a checkout opens directly in Xcode. After changing the specification, install XcodeGen and run `xcodegen generate`.

The standalone Swift package tests the shared core with synthetic fixtures and URLProtocol. Tests do not log in, write real Keychain sessions, post comments, or send chat messages.

Choose **Try Demo** to browse bundled sample content without an account. The Mac app also accepts `--demo`. Demo posts do not play video. The icon is generated with `swift scripts/generate-icon.swift` using Core Graphics.

## Playback and sign-in

Sign-in opens Floatplane's HTTPS login page in a temporary `WKWebView`. Credentials stay on that website. The app verifies the resulting session against Floatplane, then stores only the session cookie and expiry in the device Keychain. Native requests use a private session. Sign-out deletes the saved app session; it does not sign out other browsers.

Mac uses native AVKit controls. iOS uses AVPlayer for on-demand content and Amazon IVS Player for live streams, with a custom glass control row, native AirPlay routing, and Picture in Picture. Fullscreen preserves the current player and playback position. Pinch to expand or return; double-tap an on-demand video's left or right half to seek 15 seconds. The timeline supports tapping and dragging. Narrow players move secondary controls into an overflow menu. iPad retains a collapsible sidebar, with a reveal button over video when hidden. On Duo, the sidebar starts hidden with no toggle button; swipe right from the leading edge when unfolded to show it over the grid, and swipe left on the sidebar to dismiss it.

Comments, reactions, downloads, and live chat use the service's API and subscription access decisions. The API is unofficial and can change. Watch-progress sync, notifications, comment editing/deletion, authored replies, and native image galleries are not implemented. Chat emotes currently render as still images.

Authenticated iPad playback, fullscreen transitions, quality changes, sidebar reveal, timeline seeking, and Picture in Picture have been exercised in Simulator. Live WAN playback, 160p/480p quality switching, and the inline menu have also been checked on a physical iPad. Lower live renditions freeze in the current iOS Simulator despite working on hardware. Physical-device AirPlay and iPhone Duo layouts still need runtime verification. macOS browsing, playback, saved-session relaunch, and a downloaded media file have been checked. Simulator and build checks do not establish physical-device behavior.

## CI and distribution

[CI](.github/workflows/ci.yml) runs core tests and an unsigned iOS Release build. PR jobs have a read-only token and no signing secrets. [TestFlight](.github/workflows/testflight.yml) is a separate manual workflow for an exact `main` commit, using the protected `testflight` environment and temporary signing credentials. It never signs PR artifacts. See [CI setup](docs/CI.md) for required variables, secrets, and branch restrictions.

Build output, archives, local configuration, credentials, and developer account notes are ignored. Personal Apple account details do not belong in source or generated project files.

## License and privacy

[MIT](LICENSE). The iOS live player includes the Amazon IVS binary SDK under its own terms. Dependency notices are bundled in [ThirdPartyNotices.txt](Slipstream/Resources/ThirdPartyNotices.txt). The [privacy policy](docs/PRIVACY.md) describes session storage, direct service requests, and feedback.

Implementation research consulted [Duocord Native](https://github.com/saphid/duocord-native), [DuoTwitch](https://github.com/saphid/duotwitch), [Hydravion Android TV](https://github.com/bmlzootown/Hydravion-AndroidTV), [Wasserflug tvOS](https://github.com/jamamp/Wasserflug-tvOS), [Hydravion Roku](https://github.com/bmlzootown/Hydravion), and [Hydravion tvOS](https://github.com/bmlzootown/Hydravion-tvOS). These clients are not vendored.

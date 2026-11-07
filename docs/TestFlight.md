# TestFlight distribution

## Local build

Configure `Config/Local.xcconfig` or exported build variables as described in [Configuration.md](Configuration.md). The bundle ID must be registered with your Apple team and match an App Store Connect app record. Sign into that team in Xcode Settings > Accounts, or supply the three App Store Connect API authentication variables.

```sh
BUILD_NUMBER=2 ./scripts/testflight.sh archive ios
./scripts/testflight.sh export ios
./scripts/testflight.sh upload ios
```

`archive` produces a signed Release archive. `export` creates local distribution files. `upload` exports and uploads the existing archive to App Store Connect. The latter two are alternatives; exporting separately is optional. Use `macos` instead of `ios` for the native Mac target.

Increase `BUILD_NUMBER` for every new upload. Keep `APP_VERSION` stable while testing the same upcoming release: for example, `0.1.0 (1)`, `0.1.0 (2)`, then `0.1.0 (3)`. Change the marketing version when starting a subsequent release. `APP_VERSION` optionally overrides that version. The archive command refuses the public placeholder bundle ID or a missing team. Distribution signing requires current Apple program membership, agreements, and provisioning access; a successful unsigned compile is not an uploadable build.

After upload, wait for processing in App Store Connect, answer encryption compliance from the actual implementation, then add the build to an internal tester group. A successful upload alone does not mean testers can install it. External distribution additionally requires beta review information and Beta App Review. These scripts do not submit an App Store release or invite new testers.

iOS live playback includes Amazon IVS Player, whose [SDK license](https://player.live-video.net/LICENSE.txt) identifies bundled OpenSSL. For the current dependency set, declare **standard encryption algorithms in addition to Apple's operating system**, rather than declaring OS-only encryption. The app does not implement proprietary encryption. Answer the France availability question according to the actual distribution plan; [Apple requires the French declaration only when distributing on the App Store in France](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/). Excluding France in that declaration must match App Store availability.

Reassess these answers when dependencies or distribution territories change. No export-compliance declaration is silently hardcoded in this repository.

## Review information

The welcome screen offers **Try Demo** without credentials. It shows bundled browsing fixtures; demo posts do not play video. Actual media, account actions, and live chat require an account with the appropriate Floatplane subscriptions. Demo Mode does not unlock subscribed content. Do not describe it as full access during review.

Provide review contact information, a published privacy policy, and an honest explanation of the real sign-in and subscription requirements in App Store Connect. Supply any arranged review credentials there, never in this repository. Check the archive's privacy report, dependency manifests, licensing, and service/content authorization before external distribution.

## Suggested test notes

- Sign in, relaunch, and sign out.
- Browse creators and channels, search, and paginate.
- Play video and audio; seek by tapping, dragging, or double-tapping.
- Change quality and speed; enter and leave fullscreen without losing the post.
- Test iPhone/iPad sizes, rotation, sidebar hide/reveal, PiP, and AirPlay.
- Use live playback and chat when a stream is available.
- Download media, cancel, then save or share a completed file.

Include device, OS, build number, and reproduction steps with feedback. Never include passwords or session cookies. Physical AirPlay, active live broadcasting, and physical-device behavior require verification beyond Simulator checks.

## CI

See [CI.md](CI.md). CI distribution uses its own environment credentials, not a developer's local settings or Keychain.

## Apple references

- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Provide TestFlight test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
- [Encryption export compliance](https://developer.apple.com/documentation/security/complying_with_encryption_export_regulations)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

# CarPlay video

Slipstream provides a video-only CarPlay scene on iOS 26.4 and later. Browse a subscribed creator's posts, select a post, then select an accessible video attachment. **More** replaces the current page with the next 20 posts. Text, audio, and image posts can appear in the feed but have no playable videos. Live streams, search, downloads, comments, reactions, and watch-progress sync are outside this scene's scope.

The scene shares the iPhone account model and restores its saved session once. Sign in or choose **Try Demo** on iPhone before browsing; CarPlay does not present credentials. **Refresh** reloads subscriptions. Account changes reset the CarPlay library and stop its player. Disconnecting cancels pending selections and releases the media item. Phone and CarPlay playback claim a shared player focus, pausing the previous player, including the phone’s IVS live player.

The scene uses an AVPlayer with cookie-bearing assets and a Now Playing session for play, pause, and seeking. Video rows request the system's `.video` presentation; CarPlay controls whether video can be shown and its fallback to audio. The app does not infer parked state. Only the video entitlement is requested, so an audio-only CarPlay system does not advertise this app.

Apple states that [CarPlay audio and video apps also work on HomeView](https://developer.apple.com/carplay/). HomeView playback is not yet verified. This integration is not a separate HomeView target or SDK.

## Signing and test setup

The iOS entitlement file includes `com.apple.developer.carplay-video`. [Request approval from Apple](https://developer.apple.com/contact/carplay/) for the app's existing identifier, then regenerate development and distribution profiles with the capability. Existing profiles without it cannot sign this revision for a device or TestFlight. Do not change the app identifier or remove Keychain access to work around provisioning failures. Mac signing is unaffected.

Build using Xcode 27.1 or later and the normal repository scripts. Simulator builds need no Apple account. Use the existing local bundle/session configuration when installing a worktree build; otherwise the public default identifier creates a separate app.

Download **Additional Tools for Xcode** from [Apple Developer Downloads](https://developer.apple.com/download/all/) and open **Hardware → CarPlay Simulator**. Apple's [WWDC26 session](https://developer.apple.com/videos/play/wwdc2026/212/) describes the video-capable configuration. Use **Standard Video Playback** and a compatible connected iPhone. [Xcode 27.2’s release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes) say Device Hub supports CarPlay only with a USB-connected physical device, not an iOS simulator. An older Xcode’s classic Simulator has **I/O → External Displays → CarPlay**, as described in [Apple’s simulator guide](https://developer.apple.com/documentation/carplay/using-the-carplay-simulator). This legacy path has not been verified for this integration. Keep the current Xcode selected for building and use only one booted device. An ordinary iPhone simulator launch alone does not establish that video routing works.

## Verification still required before release

- Capture the original CarPlay home screen without Slipstream, then the same screen with the new app, using demo content. Record creator → post → video → pause/resume.
- Connect with the app terminated to check session restoration; try a signed-out state, demo, an expired account, empty subscriptions, locked/text-only posts, multiple attachments, and delivery failures.
- Test **More** across several pages, Back during a request, rapid selections, sign-out during loading/playback, and disconnect/reconnect. Confirm no stale request starts playback or restores private content.
- Check remote play/pause/seek, replay at the end, playback progress, phone post playback switching, and phone live-stream coexistence.
- Verify video on a supported display, video-to-audio policy changes, AirPlay authentication, and a real HLS stream using an authorized account. Bundled local MP4 playback does not verify authenticated streaming or external routing.
- Exercise iPhone, iPad, and Duo playback after the shared session changes, plus the Mac app. Verify HomeView on hardware separately.

Keep the PR draft until CarPlay runtime evidence and entitlement/provisioning readiness are available. Build and core-test results cover compilation and media filtering, not this checklist.

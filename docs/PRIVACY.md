# Slipstream privacy policy

Draft for review — prepared November 6, 2026. This policy has not been published or given an effective date.

Slipstream is an independent, open source Floatplane client maintained by PixPMusic. It is not affiliated with Floatplane Media. Questions about Slipstream privacy can be sent to [feedback@pixp.cc](mailto:feedback@pixp.cc).

## Signing in

Slipstream opens Floatplane's HTTPS sign-in page in an embedded browser with a temporary, nonpersistent website data store. You enter your credentials on that website. Floatplane and any authentication or security providers used by its sign-in process handle those credentials and may process cookies, network information and verification data. If you choose a third-party sign-in option, that provider's privacy practices also apply.

Slipstream does not store your password or send it to PixPMusic. After sign-in, Slipstream reads Floatplane's session cookie, checks that it represents a signed-in account, and saves the cookie and its expiry in your device's Keychain. The cookie authorizes requests to Floatplane on your behalf. The temporary sign-in browser is discarded when the sign-in sheet closes.

## Using Floatplane

Slipstream communicates directly with Floatplane and the services that deliver its media, images and chat. Those services receive the information needed to respond to your requests, such as your IP address, authenticated session where required, requested content, and comments, reactions or chat messages you choose to submit. Comments and chat may be visible to other Floatplane users. These requests do not pass through a PixPMusic-operated server.

Floatplane and its providers control their own storage, retention and use of that information. Their privacy policies and terms apply to their services. Slipstream's open source license does not grant rights to Floatplane accounts or media.

## Data on your device

Slipstream stores your session in Keychain and holds account, subscription, feed and playback information as needed to operate the app. Images and media may be cached by the app or operating system. On Mac, downloads are saved to the location you choose. On iPhone and iPad, downloaded files are initially stored in the app's temporary directory and can be saved or shared using the system share sheet. Files saved or shared outside the app are controlled by you and the destination you select.

Signing out deletes Slipstream's saved local session. It does not delete downloaded files, comments or chat messages, close your Floatplane account, revoke sessions on Floatplane's servers, or sign you out of Safari. Manage your Floatplane account and server-side content through Floatplane. Do not rely on uninstalling the app alone to remove a Keychain session; sign out first.

## Analytics, advertising and feedback

Slipstream includes no developer-operated analytics, advertising SDK or telemetry backend. On iPhone and iPad, live playback uses Amazon IVS Player. Its bundled privacy manifest declares non-tracking collection of identifiers, playback interactions, performance data and diagnostics for analytics and app functionality. These reports go to Amazon’s playback service, not a PixPMusic backend. See [Amazon IVS](https://docs.aws.amazon.com/ivs/latest/LowLatencyUserGuide/player.html) and [AWS privacy](https://aws.amazon.com/privacy/) for that provider’s practices. PixPMusic does not receive a copy of your Floatplane session, browsing activity, comments or chat through a Slipstream backend. Third-party websites loaded during sign-in and services contacted by the app have their own practices; this statement does not describe their data collection.

Apple may process TestFlight installation information, diagnostics and feedback according to its own privacy practices and your settings. When you submit TestFlight feedback, Apple may make that feedback and associated diagnostics available to the developer. If you email us, we receive your email address, message and attachments and use them to respond and investigate the report. Do not send passwords or session cookies. Screenshots and logs can contain personal information; review them before sharing. Public GitHub issues and their attachments are visible to others.

## Changes and contact

We will update this policy when Slipstream's data handling changes and identify the effective date of the published revision. For questions, or to request deletion of feedback you sent directly to PixPMusic, contact [feedback@pixp.cc](mailto:feedback@pixp.cc). Requests concerning data held by Floatplane or Apple must be directed to the relevant service.

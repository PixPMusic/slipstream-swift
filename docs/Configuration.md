# Local configuration

The public project has a placeholder bundle ID and no Apple team, certificate fingerprint, account email, App Store record ID, or private machine paths. Both targets resolve their identity through `Config/App.xcconfig`.

## Xcode

Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig`. The ignored copy is loaded by both targets and all build configurations.

| Xcode setting | Purpose |
| --- | --- |
| `SLIPSTREAM_BUNDLE_ID` | Product bundle identifier on both platforms |
| `DEVELOPMENT_TEAM` | Apple developer team |
| `SLIPSTREAM_DEVELOPMENT_IDENTITY` | Persistent certificate name or SHA-1 for Mac Debug |
| `SLIPSTREAM_KEYCHAIN_SERVICE` | Optional existing Keychain service to preserve session storage |

A Keychain service defaults to the bundle ID plus `.session` and is embedded in the app's Info.plist. It is an identifier, not a credential. Changing either a bundle ID or service can require signing in again. Keep any legacy service override in local configuration or CI variables rather than hardcoding it in Swift.

## Shell scripts

The scripts optionally source a trusted `.env.local` outside CI. It is a shell file, so only use one you created or trust. Copy `.env.example` for the supported format. It is never loaded in GitHub Actions. Exported variables override dotenv defaults; explicit `xcodebuild` arguments override generated settings.

| Environment variable | Build setting or behavior |
| --- | --- |
| `SLIPSTREAM_BUNDLE_ID` | Bundle identifier |
| `APPLE_TEAM_ID` | `DEVELOPMENT_TEAM` |
| `APPLE_SIGNING_IDENTITY` | `CODE_SIGN_IDENTITY` |
| `SLIPSTREAM_KEYCHAIN_SERVICE` | Keychain service Info.plist entry |
| `APP_VERSION` | `MARKETING_VERSION` |
| `BUILD_NUMBER` | `CURRENT_PROJECT_VERSION` |
| `BUILD_JOBS` | Concurrent compiler jobs; defaults to 2 |
| `SLIPSTREAM_CONFIGURATION` | Local build configuration; defaults to Debug |
| `SLIPSTREAM_DERIVED_DATA_PATH` | Build cache directory |
| `SLIPSTREAM_ARCHIVE_PATH` | Distribution archive path |
| `SLIPSTREAM_EXPORT_PATH` | Export directory |
| `APP_STORE_CONNECT_KEY_PATH` | Path to a private App Store Connect API key |
| `APP_STORE_CONNECT_KEY_ID` | API key ID; set with key path and issuer |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer; set with key path and ID |
| `IOS_PROVISIONING_PROFILE` | Optional distribution profile UUID for manual CI signing |

Keep API key files outside the checkout. The scripts use Xcode's signed-in account when API authentication variables are absent. Supplying only part of the API authentication tuple fails before building.

Local signing settings and dotenv files are deliberately absent from Git. The project can still compile using its public defaults without any of them.

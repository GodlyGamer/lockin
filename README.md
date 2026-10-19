# Lock in

A personal iOS app for one user: habits with D / B / M marks and timed reminders, a goal creator that imports plans from Claude as JSON, and a calendar paired two-way with Apple Calendar. Dark only, built with the native Liquid Glass tab bar (iOS 26 SDK, SwiftUI, SwiftData, EventKit, UserNotifications). It is sideloaded on one iPhone with a free Apple ID.

`DESIGN.md` is the single source of truth for behaviour and look. `BUILD_PLAN.md` says who builds what.

## Repository layout

```
project.yml                  XcodeGen spec (the .xcodeproj is generated, never committed)
.github/workflows/build.yml  CI: CoreKit tests on Linux, unsigned IPA on macOS
Packages/CoreKit/            Pure Swift package: domain types, engines, service protocols, fakes, tests
App/Shared/                  Router, AppServices, routes, formatting helpers (contracts shared by every module)
App/Shell/                   LockInApp, RootTabView, OnboardingView, SettingsView
App/Services/Notifications/  LocalNotificationService (UserNotifications)
App/Services/Calendar/       EventKitCalendarService
App/Persistence/             SwiftData store, backup files, signing-profile reader
App/DesignSystem/            Colour tokens, type, components ("Night glass")
App/Features/                Habits, Today, Week, Goals, Calendar screens
App/Resources/               Info.plist and the asset catalog
```

The whole app is one Swift module (plus the CoreKit package), so type names must be unique across `App/`.

## How CI builds the unsigned IPA

`.github/workflows/build.yml` runs on every push to `main` and can be started by hand (Actions tab, "build", Run workflow).

- **`core-tests`** (Ubuntu, `swift:6.1-noble`): `swift test --package-path Packages/CoreKit`.
- **`ios-build`** (`macos-26`): checks Xcode is 26 or later, installs XcodeGen, runs `xcodegen generate`, then `xcodebuild archive` for `generic/platform=iOS` with code signing switched off, zips `LockIn.app` into `Payload/` and uploads **`LockIn.ipa`** as an artifact. The full compiler log is uploaded as `xcodebuild-log` (also when the build fails).

To get the IPA: open the finished run on GitHub, download the `LockIn.ipa` artifact (a zip containing `LockIn.ipa`) and unzip it.

## Installing with Sideloadly (Windows)

1. Install Sideloadly and plug in the iPhone.
2. Drag `LockIn.ipa` into Sideloadly and sign in with your Apple ID.
3. **Use the same Apple ID every time.** The bundle ID is `com.youssoufdiallo.lockin`; if either changes, iOS treats it as a new app with an empty data container.
4. Leave Sideloadly's "change bundle ID" style option **off**.
5. Install over the existing app. Your data stays.
6. A free Apple ID signing lasts 7 days. Settings shows when the app expires, and the app warns you 48 hours before. Re-sign by repeating the steps above.

Turn on Developer Mode on the iPhone (Settings, Privacy and Security) the first time, and trust the developer profile (Settings, General, VPN and Device Management).

## Running the CoreKit tests

CoreKit has no UIKit, SwiftData, EventKit or UserNotifications dependency, so it builds and tests anywhere Swift 6.1 runs:

```
swift test --package-path Packages/CoreKit
```

On Windows, run that inside WSL with a Swift 6.1 toolchain (see `BUILD_PLAN.md` for the exact command, including the flags Ubuntu 26.04 needs). The iOS code can only be compiled by the `ios-build` job, because there is no Xcode on Windows.

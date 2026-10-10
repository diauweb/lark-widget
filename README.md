# Feishu Calendar Menu Bar App

Native macOS SwiftUI menu bar app for a focused view of a Feishu calendar. An independent project, unaffiliated with Feishu or Lark.

## Features and requirements

- Week and day views with continuous event placement, overlapping events, all-day events, and locations.
- Semester week numbers, calendar selection, automatic token refresh, and optional launch at login.
- macOS 14 or newer to run; Xcode 26 or newer to build the Icon Composer app icon.
- Your own Feishu OAuth app credentials and access to a Feishu calendar. Authentication currently uses Feishu's China endpoints; international Lark sign-in is not implemented.

The 13 class periods from 08:30 through 21:50 are currently defined in source. Edit `ClassBlock.all` in `LarkWidget/LarkCalendarMenuBarView.swift` to adapt the timetable to another school.

## Setup

1. Configure your own app in the Feishu developer console. Register `http://localhost:53291/oauth/callback` as the redirect URI and enable the scopes requested by this app: `calendar:calendar:readonly` and `offline_access`. Ensure your account is allowed to authorize it.
2. Open `LarkWidget.xcodeproj` in Xcode 26 or newer. In **Signing & Capabilities**, select your own development team. For a separately distributed fork, also choose a unique bundle identifier; `Info.plist` follows the target's setting.
3. Select the shared **LarkWidget** scheme and run the app. Click the calendar icon in the macOS menu bar.
4. Open Settings, enter your Feishu app ID and app secret, then choose **Sign in with Feishu**. After authorization, select one of the calendars loaded from Feishu.

The app is a regular sandboxed menu bar application. The access token, refresh token, and app secret are stored in macOS Keychain and are never rendered in the agenda UI.

Each user supplies their own credentials at runtime. Do not embed a shared app secret in source or a distributed binary. The default bundle and Keychain service identifiers are retained for compatibility with existing installations. A separately distributed fork should choose its own Keychain service in `KeychainTokenStore` as well.

## Build and check

Run the offline regression suites and an unsigned Release build:

```sh
bash scripts/check.sh
```

The script uses a temporary build directory and deletes it on exit. It honors `DEVELOPER_DIR`, falling back to `/Applications/Xcode.app/Contents/Developer` when available. The checks use fixtures and do not access Feishu or Keychain. They do not verify live sign-in or menu bar rendering. These are standalone runners, not an XCTest target, so use this script instead of `xcodebuild test`.

For an unsigned build only:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project LarkWidget.xcodeproj -scheme LarkWidget \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The app is produced at `build/DerivedData/Build/Products/Release/LarkWidget.app`. Distribution signing and notarization require your own Apple credentials.

## Application icon

`LarkWidget/AppIcon.icon` is the native Icon Composer source, included in the app target's Resources and selected as `AppIcon` in both Debug and Release. Open it in Icon Composer to edit its three vector groups: Calendar, Bindings, and Schedule. The SVG artwork uses a 1024 × 1024 canvas in sRGB, with centered foreground content, an opaque background defined in Composer, and no baked-in outer mask, shadows, or highlights. Composer supplies the materials and the system applies the final icon shape.

The source includes dark appearance fills for the page and bindings, and automatic monochrome rendering for clear and tinted appearances. Xcode compiles the vector groups and appearance stacks into `Assets.car` and generates the fallback `AppIcon.icns` for the app's macOS 14 minimum deployment target. There is no separate bitmap icon asset set in the target. `Design/OriginalConcept` preserves the initial flattened concept; it is not used by the app. These choices follow [Apple's app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) and [Icon Composer workflow](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

The client uses Feishu's calendar list and calendar event `instance_view` endpoints at https://open.feishu.cn. The menu bar panel opens as a week class schedule by default, with Monday-to-Sunday navigation, a single-day view, and the 13 configured class periods from 08:30 through 21:50. It requests a seven-day window for the visible week and positions events on a continuous time scale, so events can span gaps and multiple periods.

## Automatic startup

In Settings, turn on **Launch at login** under **Startup** to open Feishu Calendar automatically when you log in to macOS. Turn it off to remove the login item. Changes apply immediately, without clicking Save. The toggle reflects macOS's registration state, including changes made in System Settings. If approval is required, click **Open Login Items Settings** and allow the app there. Automatic startup is only registered when you enable the toggle.

## School weeks

In Settings, choose **Semester start** under **School week** and click **Save semester start**. The date is saved locally. The Monday–Sunday week containing that date is Week 1; the week number follows the date displayed in both Week and Day views. Earlier weeks display “Before semester.”

## Token expiry

User access tokens expire. The app uses Feishu's authorization-code OAuth flow with `offline_access`, stores the app secret and token set in macOS Keychain, and refreshes the access token before expiry. Feishu rotates refresh tokens, so each returned refresh token replaces the previous one in Keychain.

This app uses a local loopback callback for OAuth. The app opens `https://accounts.feishu.cn/open-apis/authen/v1/authorize` with `client_id`, `response_type=code`, the registered redirect URI, the requested scopes, and a CSRF `state`. It receives the one-time callback through a listener restricted to the loopback interface, then exchanges the code at `POST https://open.feishu.cn/open-apis/authen/v2/oauth/token`. The client decodes a flat JSON object containing `code`, `access_token`, `expires_in`, and the optional `refresh_token` and `refresh_token_expires_in`. Never commit the app secret or tokens.

## Recurring events and cancellations

The calendar view endpoint expands recurring series into occurrences for the requested range, including moved or edited exceptions. The ordinary events list returns series definitions and must not be used directly as the displayed week. The app excludes cancelled entries, identifies each occurrence by `event_id`, start time, and end time, and removes exact duplicates before rendering. Timed occurrences are positioned by their actual start and end times; all-day occurrences appear in a separate all-day band. Only the calendar selected in Settings is displayed; Feishu's desktop app can overlay several calendars.

The menu-bar panel keeps its fixed size (900 × 620 points for Week, 400 × 620 for Day). After opening or changing size, it moves inside the current display's usable area with an 8-point margin, rather than shrinking. If the display itself is smaller than the panel, its top-left controls remain reachable, but the entire panel cannot fit.

## Regression checks

Run the fixture-based client checks without accessing Feishu or Keychain:

```sh
swiftc -parse-as-library LarkWidget/LarkCalendarModels.swift LarkWidget/LarkCalendarClient.swift LarkWidgetTests/CalendarClientTests.swift -o /tmp/lark-calendar-client-tests
/tmp/lark-calendar-client-tests
```

Check window placement, including the left-edge overflow and offset displays:

```sh
swiftc -parse-as-library LarkWidget/MenuBarWindowPositioner.swift LarkWidgetTests/MenuBarWindowPlacementTests.swift -o /tmp/lark-window-placement-tests
/tmp/lark-window-placement-tests
```

## Contributing and privacy

See [CONTRIBUTING.md](CONTRIBUTING.md) for project structure and validation. See [SECURITY.md](SECURITY.md) for credential handling and reporting security issues. Keep real calendar data, OAuth callbacks, credentials, signing files, and Xcode user state out of commits and issue attachments.

## License

[MIT](LICENSE). The repository includes the original icon concept and its generation prompt in `Design/OriginalConcept`; the active icon source is `LarkWidget/AppIcon.icon`.

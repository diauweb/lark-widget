# Feishu Calendar

Feishu Calendar is a macOS menu bar app that shows one Feishu calendar.
This project is independent of Feishu and Lark.

## Features

- Week and Day views
- Event times, locations, and overlapping events
- All-day events and recurring events
- School week numbers
- Automatic token refresh
- Optional start at login

## Requirements

- macOS 14 or later
- Xcode 26 or later to build the app
- Your own Feishu app ID and app secret
- A Feishu account with access to a calendar

The app uses Feishu services in China.
The app does not support international Lark sign-in.

## Setup

### Configure Feishu

1. Create an app in the Feishu developer console.
2. Add `http://localhost:53291/oauth/callback` as an authorized redirect URI.
3. Enable the `calendar:calendar:readonly` scope.
4. Enable the `offline_access` scope.
5. Make sure that your account can authorize the Feishu app.

### Build and start the app

1. Open `LarkWidget.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your development team.
3. Select the **LarkWidget** scheme.
4. Start the app from Xcode.
5. Click the calendar icon in the macOS menu bar.

### Sign in

1. Open **Settings**.
2. Enter your Feishu app ID in **App ID**.
3. Enter your app secret in **App secret**.
4. Click **Sign in with Feishu**.
5. Complete authorization in the browser.
6. Select a calendar in **Calendar**.

## Start at login

1. Open **Settings**.
2. Set **Launch at login** to on.
3. If macOS requires approval, click **Open Login Items Settings**.
4. Approve the app in macOS settings.

The change takes effect immediately.
To stop automatic startup, set **Launch at login** to off.

## School weeks

1. Open **Settings**.
2. Select a date in **Semester start**.
3. Click **Save semester start**.

The week starts on Monday and ends on Sunday.
The week that contains the selected date is Week 1.
Dates before that week show “Before semester.”
The timetable has 13 fixed class periods from 08:30 to 21:50.
See [CONTRIBUTING.md](CONTRIBUTING.md) to change these periods.

## Check the project

Run this command from the project directory:

```sh
bash scripts/check.sh
```

The script runs tests with sample data and makes an unsigned Release build.
The tests do not connect to Feishu or access Keychain.
The script does not start the app or check its appearance.

## Privacy

The app stores the app secret and tokens in macOS Keychain.
Each user supplies their own credentials.
Do not put credentials or personal calendar data in Git commits or public issues.
See [SECURITY.md](SECURITY.md) for storage details and security reports.

## Contribute

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions and checks.

## License

This project uses the [MIT license](LICENSE).

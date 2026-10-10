# Security and privacy

This app reads the selected Feishu calendar using user-supplied OAuth credentials. It requests `calendar:calendar:readonly` and `offline_access`, and uses a loopback-only HTTP listener during sign-in with a CSRF state check. The sandbox permits outbound API requests and the inbound local callback.

The app secret, access token, and refresh token are stored in macOS Keychain. App ID, selected calendar ID/color, API base URL, semester start, and token expiry dates are stored in local UserDefaults. Calendar events are held in memory. There is no analytics or crash-reporting SDK in the project.

Sign out deletes the access and refresh tokens and clears the in-memory calendar data. It retains the app secret and configuration for later sign-in. Never package a shared OAuth secret in the application; users configure their own Feishu apps.

## Reporting a vulnerability

Use the repository's private vulnerability reporting feature if it is enabled on GitHub. Otherwise, open an issue asking the maintainer for a private reporting channel, without exploit details or sensitive data. Do not include tokens, secrets, authorization codes, personal calendar data, Keychain exports, or signing files in a public report.

If credentials were exposed, revoke or rotate them in Feishu. Removing a file from the latest commit does not remove it from Git history.

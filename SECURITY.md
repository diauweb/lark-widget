# Security and privacy

## Calendar access

The app reads the selected Feishu calendar with the credentials that you supply.
It requests two OAuth scopes:

- `calendar:calendar:readonly`: calendar read access
- `offline_access`: access for token refresh

During sign-in, the app receives the browser callback through a local HTTP listener.
The listener accepts connections only through the loopback interface.
The app checks the OAuth state value before it accepts the authorization code.
The app sandbox permits outgoing network requests and the local callback connection.

## Local storage

The app stores these values in macOS Keychain:

- App secret
- Access token
- Refresh token

The app stores these settings in local UserDefaults:

- App ID
- Selected calendar ID and color
- API base URL
- Semester start date
- Token expiration dates

The app keeps calendar events in memory.
The project has no analytics or crash reporting SDK.

## Sign out

To sign out, click **Sign out** in **Settings**.
The app deletes the access and refresh tokens.
It also clears the calendar data from memory.
It keeps the app secret and saved settings for later sign-in.

Each user must configure their own Feishu app.
Do not put a shared app secret in source code or a distributed app.

## Report a security problem

If GitHub private vulnerability reporting is available, use it to report the problem.
Otherwise, open a public issue to request a private contact method.
Do not include exploit details in that public issue.

Do not include these items in public reports or attachments:

- Tokens or app secrets
- Authorization codes or OAuth callback URLs that contain codes
- Personal calendar data
- Keychain exports
- Apple signing files

If you expose credentials, revoke or replace them in Feishu.
If you delete a file from the latest commit, the file stays in Git history.

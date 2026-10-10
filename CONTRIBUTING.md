# Contributing

Build with Xcode 26 or newer on macOS. Start with the setup instructions in [README.md](README.md); each developer uses their own signing team and Feishu app credentials.

## Project structure

- `LarkWidget/`: SwiftUI app, calendar client/models, OAuth, Keychain storage, and Icon Composer source.
- `LarkWidgetTests/`: standalone fixture and window-placement regression runners.
- `Design/`: icon previews and original concept provenance; not compiled into the app.
- `scripts/check.sh`: offline regression checks and unsigned Release build.

## Validation

Run `bash scripts/check.sh` before submitting a change. Use synthetic calendar fixtures for client tests. For UI changes, also inspect the running menu bar panel in Week and Day views; compile success and geometry checks alone do not verify the rendered UI. For OAuth changes, describe any manual sign-in/refresh checks separately from offline tests.

Explain the behavior changed and the checks performed in your pull request. Avoid unrelated formatting or generated-file changes. Do not include real event titles, calendar identifiers, tokens, app secrets, callback URLs containing authorization codes, or signing credentials. Crop or redact screenshots of personal calendars.

Keep signing-team settings local. The shared scheme is committed; Xcode `xcuserdata` and build outputs are ignored. Contributions are made under the project's [MIT license](LICENSE).

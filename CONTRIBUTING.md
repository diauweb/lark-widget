# Contributing

Use Xcode 26 or later on macOS.
See [README.md](README.md) for setup instructions.
Use your own development team and Feishu app credentials.

## Project files

- `LarkWidget/`: app source and resources
- `LarkWidgetTests/`: tests for the calendar client and window position
- `Design/`: icon previews and the original design prompt
- `scripts/check.sh`: test and build script

The app does not use the files in `Design/` at runtime.

## Build and test

Run this command from the project directory:

```sh
bash scripts/check.sh
```

The script does these steps:

1. Compile the calendar client tests.
2. Run the calendar client tests.
3. Compile the window position tests.
4. Run the window position tests.
5. Build the app in Release mode with code signing disabled.

The script stops if a step fails.
It deletes its temporary build directory when it stops.
The tests use sample data instead of live Feishu requests.

The script uses `DEVELOPER_DIR` if you set it.
Otherwise, it uses `/Applications/Xcode.app/Contents/Developer` if that directory exists.
The tests are separate programs.
They are not XCTest targets.
Use this script to run them.

For an unsigned build only, run this command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project LarkWidget.xcodeproj -scheme LarkWidget \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The output is `build/DerivedData/Build/Products/Release/LarkWidget.app`.
To sign and notarize the app for distribution, use your own Apple credentials.

## Change the timetable

Edit `ClassBlock.all` in `LarkWidget/LarkCalendarMenuBarView.swift` to change the class periods.
Events use their actual start and end times.
The class periods are visual guides.

## Distribute a fork

The default bundle identifier and Keychain service identifier support existing installations.
For a separately distributed fork, select a unique bundle identifier in Xcode.
Set a unique Keychain service identifier in `KeychainTokenStore` in `LarkWidget/LarkCalendarStore.swift`.
The `Info.plist` file uses the bundle identifier from the target settings.

Do not put your development team in the shared project settings.
The repository includes a shared Xcode scheme.
The `.gitignore` file excludes Xcode user settings and build outputs.

## Check a change

1. Run `bash scripts/check.sh`.
2. For a change to the user interface, inspect the app in Week and Day views.
3. For an OAuth change, test sign-in and token refresh with your own Feishu app.
4. Describe the change and the test results in your pull request.

A successful build does not show that the user interface is correct.
Report manual test results separately from tests that use sample data.
Use sample calendar data in new tests.
Keep changes limited to the purpose of the pull request.

Do not include credentials, personal calendar data, or authorization codes in commits or issue attachments.
Before you attach a screenshot, remove personal calendar data from the image.
See [SECURITY.md](SECURITY.md) for security reports.

Contributions use the project's [MIT license](LICENSE).

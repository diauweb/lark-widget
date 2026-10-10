#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Respect a caller-selected Xcode; fall back when only Command Line Tools is active.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

check_dir=$(mktemp -d "${TMPDIR:-/tmp}/lark-widget-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT

xcrun swiftc -parse-as-library \
    -module-cache-path "$check_dir/ModuleCache" \
    LarkWidget/LarkCalendarModels.swift \
    LarkWidget/LarkCalendarClient.swift \
    LarkWidgetTests/CalendarClientTests.swift \
    -o "$check_dir/calendar-client-tests"
"$check_dir/calendar-client-tests"

xcrun swiftc -parse-as-library \
    -module-cache-path "$check_dir/ModuleCache" \
    LarkWidget/MenuBarWindowPositioner.swift \
    LarkWidgetTests/MenuBarWindowPlacementTests.swift \
    -o "$check_dir/window-placement-tests"
"$check_dir/window-placement-tests"

xcodebuild -project LarkWidget.xcodeproj -scheme LarkWidget \
    -configuration Release -destination 'platform=macOS' \
    -derivedDataPath "$check_dir/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build

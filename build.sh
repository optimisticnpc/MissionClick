#!/bin/zsh
set -eu
TASK_ROOT="${0:A:h}"
TASK_APP="$TASK_ROOT/MissionClick.app"
TASK_CACHE="$TASK_ROOT/.build/swift-module-cache"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_CACHE"
xcrun swiftc -swift-version 5 -O -module-cache-path "$TASK_CACHE" \
  -framework AppKit -framework ApplicationServices -framework ServiceManagement \
  "$TASK_ROOT/Source/WindowTarget.swift" "$TASK_ROOT/Source/main.swift" \
  -o "$TASK_APP/Contents/MacOS/MissionClick"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.jtan.MissionClick</string>
<key>CFBundleName</key><string>MissionClick</string>
<key>CFBundleDisplayName</key><string>MissionClick</string>
<key>CFBundleExecutable</key><string>MissionClick</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.jtan.MissionClick "$TASK_APP"
echo "Built $TASK_APP"

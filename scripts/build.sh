#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Summary Notes.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
read -r -a architectures <<< "${BUILD_ARCHS:-$(uname -m)}"
binaries=()
for architecture in "${architectures[@]}"; do
    case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac
    binary="$PWD/.build/SummaryNotes-$architecture"
    xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" -framework AppKit Sources/Core.swift Sources/main.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/SummaryNotes"
cp Resources/SummaryPrompt.txt Resources/Summary.schema.json "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/Icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Summary Notes</string>
<key>CFBundleDisplayName</key><string>Summary Notes</string>
<key>CFBundleIdentifier</key><string>me.nieder.summary-notes</string>
<key>CFBundleExecutable</key><string>SummaryNotes</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 John Niedermeyer. MIT License.</string>
</dict></plist>
PLIST
if [[ "${SIGNING_IDENTITY:--}" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"

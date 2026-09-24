#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Note Ferry.app"
./scripts/fetch-sparkle.sh
SPARKLE_ROOT="$PWD/.build/sparkle/2.10.0"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" .build/module-cache
read -r -a architectures <<< "${BUILD_ARCHS:-$(uname -m)}"
binaries=()
for architecture in "${architectures[@]}"; do
    case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac
    binary="$PWD/.build/SummaryNotes-$architecture"
    xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" -framework AppKit -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/Core.swift Sources/MarkdownFormatter.swift Sources/LocalSummarizer.swift Sources/main.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/SummaryNotes"
cp Resources/SummaryPrompt.txt Resources/Summary.schema.json "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/Sparkle.LICENSE "$APP/Contents/Resources/Sparkle.LICENSE"
ditto "$SPARKLE_ROOT/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/Icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Note Ferry</string>
<key>CFBundleDisplayName</key><string>Note Ferry</string>
<key>CFBundleIdentifier</key><string>me.nieder.summary-notes</string>
<key>CFBundleExecutable</key><string>SummaryNotes</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/niederme/note-ferry/main/appcast.xml</string>
<key>SUPublicEDKey</key><string>jk/qFiY8Sq8W1xua3ngXYGMbHjKkGuUCXVMQECxi68o=</string>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 John Niedermeyer. MIT License.</string>
</dict></plist>
PLIST
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SIGN_ARGS=(--force --options runtime --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"

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
    binary="$PWD/.build/NoteFerry-$architecture"
    xcrun swiftc -swift-version 5 -O -target "$architecture-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" -framework AppKit -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/Core.swift Sources/MarkdownFormatter.swift Sources/LocalSummarizer.swift Sources/ProviderSettings.swift Sources/SettingsWindow.swift Sources/ClaudeRunner.swift Sources/main.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/Note Ferry"
cp Resources/SummaryPrompt.txt Resources/Summary.schema.json "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/Sparkle.LICENSE "$APP/Contents/Resources/Sparkle.LICENSE"
ditto "$SPARKLE_ROOT/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
xcrun swift -module-cache-path "$PWD/.build/module-cache" scripts/Icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
# Hardened runtime requires a common Developer ID team for the app and Sparkle.
# Local ad-hoc builds have no team ID, so leave it off; releases still need it.
if [[ "$SIGNING_IDENTITY" != "-" ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"

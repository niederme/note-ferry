#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/fetch-sparkle.sh
mkdir -p .build/design-ui .build/module-cache
python3 - <<'PY'
from pathlib import Path
source = Path('Sources/main.swift').read_text().split('let app = NSApplication.shared\n')[0]
source = source.replace('SPUStandardUpdaterController(startingUpdater: true', 'SPUStandardUpdaterController(startingUpdater: false')
Path('.build/design-ui/main.swift').write_text(source + Path('Tests/DesignUITests.swift').read_text())
PY
APP="$PWD/.build/design-ui/DesignChecks.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>me.nieder.note-ferry.design-checks</string><key>CFBundleExecutable</key><string>DesignChecks</string><key>CFBundleName</key><string>Note Ferry Design Checks</string></dict></plist>
PLIST
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" -framework AppKit -F .build/sparkle/2.10.0 -framework Sparkle -Xlinker -rpath -Xlinker "$PWD/.build/sparkle/2.10.0" Sources/Interview.swift Sources/Core.swift Sources/CodexDiscovery.swift Sources/MarkdownFormatter.swift Sources/LocalSummarizer.swift Sources/ProviderSettings.swift Sources/SettingsWindow.swift Sources/ClaudeRunner.swift Sources/InterviewWindow.swift .build/design-ui/main.swift -o "$APP/Contents/MacOS/DesignChecks"
"$APP/Contents/MacOS/DesignChecks"

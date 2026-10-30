#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" -framework AppKit Sources/Interview.swift Sources/InterviewWindow.swift Sources/Core.swift Sources/CodexDiscovery.swift Sources/MarkdownFormatter.swift Sources/LocalSummarizer.swift Sources/ProviderSettings.swift Sources/ClaudeRunner.swift Tests/InterviewUITests.swift -o .build/interview-ui-tests
./.build/interview-ui-tests

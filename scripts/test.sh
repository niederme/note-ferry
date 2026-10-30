#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -module-cache-path "$PWD/.build/module-cache" -framework AppKit Sources/Interview.swift Sources/Core.swift Sources/CodexDiscovery.swift Sources/MarkdownFormatter.swift Sources/LocalSummarizer.swift Sources/ProviderSettings.swift Sources/ClaudeRunner.swift Tests/InterviewTests.swift Tests/CoreTests.swift Tests/CodexDiscoveryTests.swift -o .build/core-tests
./.build/core-tests

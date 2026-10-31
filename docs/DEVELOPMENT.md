# Development

[Back to Note Ferry](../README.md) · [User guide](USER_GUIDE.md) · [Roadmap](../ROADMAP.md)

Build, test, and contribute to Note Ferry. See the [download instructions](../README.md#download) for release availability.

## Requirements

- macOS 14 or later. Runtime testing so far has been on Apple silicon with macOS 27.
- Xcode with the macOS 27 or later SDK, even when building for macOS 14. The source includes an optional Apple Foundation Models path behind a runtime availability check.
- For Codex summaries, a signed-in Codex CLI supporting `exec`, `--ephemeral`, `--ignore-user-config`, and `--output-schema`. Local formatting, Apple Intelligence, and Claude do not require Codex.

The app uses AppKit and bundles Sparkle 2.10 for updates. The build downloads Sparkle on first use and checks its pinned SHA-256. Sparkle’s license is in `Resources/Sparkle.LICENSE` and included in the app. Codex is an external runtime dependency and is not bundled.

## Install from source

Clone this repository and enter its directory:

```sh
git clone https://github.com/niederme/note-ferry.git
cd note-ferry
```

To use **Summarize & format** with Codex selected, make sure Codex CLI is installed and signed in. **Format only**, Apple Intelligence, and Claude do not use Codex:

```sh
codex --version
codex login
```

See the [official Codex documentation](https://developers.openai.com/codex/) for installation and account setup. For development alongside an open Note Ferry session, use the [separate preview build](#preview-without-a-model-call) instead of installing over it. To install:

```sh
make install
```

This installs `~/Applications/Note Ferry.app` and registers it with Launch Services. An existing Note Ferry installation is preserved under `~/Applications/Note Ferry backups/` in a dated folder.

Spotlight indexing may take a little time. Open the app directly from your home folder’s Applications directory if needed. Raycast may need its application list refreshed. No Service, Shortcut, or keyboard shortcut setup is required.

On first launch, **Choose a summarizer** opens over the main window. Apple Intelligence is the initial default on a new install; if it is unavailable, choose Codex or Claude to summarize. **Done** completes onboarding. The same controls remain available in **Note Ferry → Settings…**, and the picker beside **Summarize & format** changes the provider for the current text without changing your default. **Format only** never calls a model.

For Claude key and workspace setup, see the [user guide](USER_GUIDE.md#claude). The verifier checks access without sending a transcript; a format check alone does not prove the key will work. Do not put a real API key in source files, issues, or test fixtures.

Source builds target your Mac’s architecture and are ad-hoc signed for local use. The first build downloads the pinned Sparkle distribution. A release download must be separately signed and notarized before publication. Source builds point to the official Note Ferry update feed.

### Codex account and usage

The app reuses your Codex CLI login. With a ChatGPT login, you do not need a separate API key in Note Ferry. Requests consume your Codex account allowance and remain subject to its limits and terms.

Codex discovery checks absolute entries in the app's inherited `PATH`, `~/.local/bin`, `~/.npm-global/bin`, `~/.npm/bin`, Homebrew/system locations, installed nvm versions, and the standard Codex app bundle location. nvm discovery checks `NVM_DIR`, `~/.nvm`, and `$XDG_CONFIG_HOME/nvm` (or `~/.config/nvm`). Without a PATH selection it tries nvm versions newest first, choosing the first usable Codex. The launcher keeps the discovered runtime directories in its child PATH, including the matching npm prefix for symlinked launchers, and reports a missing Node.js runtime separately.

Discovery reads the filesystem only: it does not run shell startup files, load nvm aliases, or read npm configuration. Relative and empty PATH entries are ignored. For a custom npm prefix or nvm root outside these locations, its bin directory must be in the app's inherited PATH (or its root in `NVM_DIR`); Finder does not inherit Terminal-only shell configuration. Executable paths are not currently configurable in the app.

Note Ferry lets Codex choose its built-in default model unless you enter a model ID in **Note Ferry → Settings… → Codex model**. Enterprise accounts can enter a model available to their workspace instead of relying on a fixed model name. Clear the field to restore the CLI default. The choice is stored in Note Ferry preferences; it does not change your Codex account or CLI configuration. Note Ferry passes no fixed reasoning-effort setting. If a model is unavailable, the request fails with a Settings instruction, without silently switching models or providers.

The runner keeps `--ignore-user-config`: it does not inherit your Terminal model preference, custom tools, hooks, or integrations. See the [official CLI reference](https://developers.openai.com/codex/developer-commands) for the model override and config-isolation flags. Version 2.0 also offers on-device Apple Intelligence on supported Macs running macOS 26 or later, plus Claude through a separately billed Anthropic API key stored in the app's Keychain item. A first-run chooser, Settings default, and per-transcript picker select the provider. No provider silently falls back to another.

## Build in Xcode

Open [`Note Ferry.xcodeproj`](../Note%20Ferry.xcodeproj), select the **Note Ferry** scheme and **My Mac**, then press **⌘R** to build and run the app. **⌘B** builds without opening it. This is a normal Xcode app target; its Debug product is in Xcode’s DerivedData and does not replace the app in `~/Applications`. The first build downloads the pinned Sparkle framework.

The Xcode project is checked in. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is only needed if you change `project.yml` and want to regenerate the project with `xcodegen generate`. The command-line release build and the Xcode target share `Resources/Info.plist`, source files, and bundled resources. The vector icon source is `Resources/AppIcon.svg`; when it changes, regenerate the checked-in `Resources/AppIcon.icns` for Xcode with:

```sh
xcrun swift scripts/Icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
```

## Build and test

```sh
make build     # Rebuild build/Note Ferry.app; use BUILD_APP_PATH below if it is running
make test      # Run the automated checks
./scripts/test-interview-ui.sh  # Exercise the interview sheet with synthetic model responses
make install   # Build and install in ~/Applications
```

The build script replaces its target bundle. If that app is running or contains a session you want to keep, set a separate absolute `BUILD_APP_PATH` as shown below. `make install` uses the default `build/Note Ferry.app` path; do not combine it with a custom `BUILD_APP_PATH`.

The default ad-hoc `make build` marks the local app as **Development** in its window title and About panel while retaining the base version number. Developer ID release builds do not receive this label.

| Path | Purpose |
| --- | --- |
| `Sources/main.swift` | AppKit interface and clipboard workflow |
| `Sources/MarkdownFormatter.swift` | Local Markdown parsing and Notes-friendly rich text |
| `Sources/Core.swift` | Summary model, renderer, clipboard helpers, and Codex runner |
| `Sources/CodexDiscovery.swift` | Codex and Node runtime discovery for GUI launches |
| `Sources/LocalSummarizer.swift` | On-device Apple Intelligence summarizer and text chunking |
| `Sources/ClaudeRunner.swift` | Anthropic Messages API request, response validation, and cancellation |
| `Sources/ProviderSettings.swift` | Default provider and Claude API key in macOS Keychain |
| `Sources/SettingsWindow.swift` | First-run provider chooser and Settings |
| `Sources/Interview.swift` | Interview contracts, validation, answer budgets, and token aggregation |
| `Sources/InterviewWindow.swift` | Interview sheet, controls, keyboard navigation, and request lifecycle |
| `Resources/Interview.schema.json` | Structured interview-output contract |
| `Resources/SummaryPrompt.txt` | Instructions for detailed, source-faithful summaries |
| `Resources/Summary.schema.json` | Structured model-output contract |
| `Resources/AppIcon.svg` | Approved vector icon, with outlined lettering |
| `Resources/AppIcon.icns` | Generated icon bundled by Xcode |
| `Resources/Info.plist` | Shared bundle identity and update settings |
| `Resources/Sparkle.LICENSE` | License for the bundled updater |
| `scripts/fetch-sparkle.sh` | Fetch and verify the pinned Sparkle distribution |
| `Tests/` | Synthetic fixture and automated checks |
| `scripts/` | Build, installation, test, and icon-generation tools |

The model supplies structured content. The app owns typography, lists, spacing, and clipboard handling, so these do not depend on how the model formats Markdown. The on-device path accepts up to 100 KB, uses fresh sessions for roughly 4,000-character portions, and consolidates takeaways separately. It can take longer and may be less detailed than Codex. Model availability depends on macOS, hardware, Apple Intelligence settings, and model readiness.

### Build the interview without replacing a running app

```sh
BUILD_APP_PATH="$PWD/.build/interview-preview/Note Ferry.app" make build
```

The interview uses `Sources/Interview.swift` for the request contract, stable question/answer state, validation, and token aggregation, and `Sources/InterviewWindow.swift` for its session-only sheet. `Resources/Interview.schema.json` is bundled by both build paths. Backend tests cover opt-out persistence, multiple rounds, unanswered questions, source provenance, invalid excerpts, provider payloads, cancellation, and usage totals. The UI harness uses a mock Codex executable, makes no real model calls, and does not copy or paste. Command-line `--summarize-file` exports remain non-interactive and bypass the interview.

### Preview without a model call

Use a separate preview bundle and launch a new instance so an existing session can stay open:

```sh
BUILD_APP_PATH="$PWD/.build/docs-preview/Note Ferry.app" make build
open -n "$PWD/.build/docs-preview/Note Ferry.app" --args --preview "$PWD/Tests/fixture.json"
```

This opens a synthetic preview without changing your clipboard. **Copy summary** explicitly copies the result. Close only the preview when finished. If this preview bundle is already running, use a different output path before rebuilding. Separate instances still share app preferences and Keychain identity.

### Format Markdown without a model or clipboard change

```sh
'build/Note Ferry.app/Contents/MacOS/Note Ferry' \
  --format-file Tests/format-fixture.md "$PWD/local-output/formatted"
```

This writes `formatted.rtf` and `formatted.txt`. No model is called. Blank input and input over 400,000 UTF-8 bytes are rejected; the transcript minimum length does not apply. Exports remain on disk after the app exits. Exporting to the same folder again replaces files with the same names.

The local formatter uses Apple's inline Markdown parser plus block handling for ATX and setext headings, paragraphs, lists, checklists, nested quotes, thematic dividers, fenced code, and indented code. A standalone bold line becomes a section heading. The `codex-prompt` blocks exported by ChatGPT Meetings become spaced native action-item bullets; their clickable behavior does not carry over to Notes. It recognizes whole-answer chat code fences containing clear Markdown structure, including mislabeled `vbnet` fences and longer outer fences wrapping headings and action blocks.

Markdown tables become `NSTextTable` grids with bold headers, column alignment, proportional widths, wrapped cells, and borders. Escaped pipes and empty cells are preserved; extra cells in ragged rows expand the grid rather than dropping content. Table results include both RTF and HTML clipboard representations, plus a tab-separated plain-text fallback. Destination apps determine whether pasted tables become their own editable table objects. Checklist states use visible checkbox symbols, not native Notes checklist objects. Image descriptions become links without downloading the image. Inline `<br>` tags become soft line breaks; code remains literal.

After building the separate preview bundle above, preview the mixed-pattern fixture without changing the clipboard or calling a model:

```sh
open -n "$PWD/.build/docs-preview/Note Ferry.app" --args --preview-markdown "$PWD/Tests/markdown-patterns.md"
```

Other raw HTML and Markdown extensions outside these patterns remain text; the formatter does not execute or load them.

The table-capable preview displays list markers separately from the underlying note content. Copying a selection maps its range back to the original rich text, preserving native lists and table cells without exporting the preview's marker characters, tabs, or screen-only paragraph styles. The automatic clipboard output and Copy formatted text button use the original rich text directly.

### Test a real transcript without changing the clipboard

```sh
'build/Note Ferry.app/Contents/MacOS/Note Ferry' \
  --summarize-file /absolute/path/to/transcript.md "$PWD/local-output/example"
```

This sends the source to Codex and saves `summary.json`, `summary.rtf`, and `summary.txt` in the chosen folder. Exports remain on disk after the app exits. Exporting to the same folder again replaces files with the same names. The suggested `local-output/` directory is excluded from Git.

### Verification

The automated checks cover local Markdown conversion, inline emphasis and links, ordered and nested lists, literal code, whole-answer fences, short text, RTF round trips, native lists, bold headings, soft returns, section spacing, Unicode, plain-text fallback, clipboard conflicts and restoration, input validation, invalid model responses, authentication failures, cancellation, and timeout.

Use `NF_TEST_SKIP_KEYCHAIN=1 make test` to skip the isolated Keychain availability check when Keychain access is out of scope. Codex discovery regression tests use temporary synthetic installations and a mock Node launcher; they make no model calls and do not run shell startup files.

Clipboard tests use a separate named pasteboard, leaving the regular clipboard alone. They require access to the macOS pasteboard service and may fail in a restrictive execution sandbox.

For manual acceptance, copy the synthetic example and paste it into a note you choose. Check headings, single bullet markers, spacing between items and sections, and native list editing. Destination-app behavior needs visual verification in addition to automated checks.

### Release builds

Xcode's **Archive** action uses the Release configuration, which enables Hardened Runtime and automatic Apple Development signing for the release owner's team (`289GY9L343`). Debug keeps local ad-hoc signing without a team. Fork maintainers must select their own team for Release archives. After pulling an archive-settings fix, create a new archive; an existing archive does not pick up changed settings. For distribution, export with Developer ID signing and notarization on the Mac with the release credentials. A successful local or development-signed build does not confirm notarization readiness.

Build both architectures with a Developer ID Application identity installed in your Keychain:

```sh
BUILD_APP_PATH="$PWD/.build/release/Note Ferry.app" \
  BUILD_ARCHS='arm64 x86_64' \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  ./scripts/build.sh
```

The build targets macOS 14, embeds Sparkle with symlinks preserved, signs its helpers and framework before the host app, enables the hardened runtime for Developer ID signing, requests secure timestamps, and verifies the signature. Submit a ZIP of the app using `xcrun notarytool` with a configured authentication method, such as a Keychain profile or App Store Connect API key. Once Apple accepts it, review the notarization log, staple the ticket to the app with `xcrun stapler`, and verify with both `stapler validate` and `spctl --assess --type execute`. Create the final download ZIP **after** stapling, and generate its SHA-256 checksum.

Sparkle uses the public EdDSA key in the app’s Info.plist. The matching private key is in the release owner’s login Keychain under the `note-ferry` account; never export or commit it. For each new release, increment `CFBundleVersion`, sign and notarize the app, upload the final ZIP to GitHub Releases, then generate the appcast with the pinned Sparkle tools and the final ZIP. Include the release notes in the appcast, verify its signature, and publish the appcast to the `main` branch only after the ZIP is reachable. The `SUFeedURL` in the app points at the raw `main` version of `appcast.xml`. New builds require an EdDSA-signed archive and feed because verification before extraction and signed-feed checks are enabled. Keep the appcast update process in the release PR so reviewers can check the exact URL, version, and signature.

Version 1.0 did not include Sparkle. Those users must manually install a current release once; subsequent updates can use the app menu. A source build also points to the official feed, so fork maintainers should change the URL and public key to their own before distributing their app. Never commit signing keys or notarization credentials.

## Rendering for Apple Notes

Rich text that looks well spaced elsewhere can paste densely into Notes. Note Ferry encodes spacing directly into the text:

| Between | Formatting |
| --- | --- |
| Bullet items | A soft return inside the preceding item, producing a blank line without an empty bullet |
| Sections | Two empty paragraphs before the heading |
| Heading and content | One empty paragraph after the heading |

Headings and labels are bold. Bullets use native list metadata rather than decorative characters. The clipboard also includes a plain-text fallback with equivalent spacing.

## Contributing

Bug reports, formatting improvements, and compatibility reports are welcome. Include your macOS version, selected summarizer, and a small synthetic example that reproduces the issue.

Please do not include private transcripts, real meeting summaries, credentials, or screenshots containing personal information in issues or pull requests. Keep generated output in `local-output/` and run `make test` for changes to the renderer, clipboard handling, or backend.

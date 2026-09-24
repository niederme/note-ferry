# Development

[Back to Note Ferry](../README.md) · [Roadmap](../ROADMAP.md)

Build, test, and contribute to Note Ferry. See the [download instructions](../README.md#download) for release availability.

## Requirements

- macOS 14 or later. Runtime testing so far has been on Apple silicon with macOS 27.
- Xcode with the macOS 26 or later SDK, even when building for macOS 14. The source includes an optional Apple Foundation Models path behind a runtime availability check.
- Codex CLI supporting `exec`, `--ephemeral`, `--ignore-user-config`, and `--output-schema`, signed in for live summarization.

The app uses AppKit and bundles Sparkle 2.10 for updates. The build downloads Sparkle on first use and checks its pinned SHA-256. Sparkle’s license is in `Resources/Sparkle.LICENSE` and included in the app. Codex is an external runtime dependency and is not bundled.

## Install from source

Clone this repository and enter its directory:

```sh
git clone https://github.com/niederme/note-ferry.git
cd note-ferry
```

For **Summarize with Codex** (called **Summarize & format** in the 1.1 release), make sure Codex CLI is installed and signed in. **Format only** and **Summarize on Mac** do not use Codex:

```sh
codex --version
codex login
```

See the [official Codex documentation](https://developers.openai.com/codex/) for installation and account setup. Then build and install:

```sh
make install
```

This installs `~/Applications/Note Ferry.app` and registers it with Launch Services. An existing Note Ferry installation is preserved under `~/Applications/Note Ferry backups/` in a dated folder.

Spotlight indexing may take a little time. Open the app directly from your home folder’s Applications directory if needed. Raycast may need its application list refreshed. No Service, Shortcut, or keyboard shortcut setup is required.

Source builds target your Mac’s architecture and are ad-hoc signed for local use. The first build downloads the pinned Sparkle distribution. A release download must be separately signed and notarized before publication. Source builds point to the official Note Ferry update feed.

### Codex account and usage

The app reuses your Codex CLI login. With a ChatGPT login, you do not need a separate API key in Note Ferry. Requests consume your Codex account allowance and remain subject to its limits and terms.

Codex is discovered in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or the standard Codex app bundle location. Other installation paths are not currently configurable in the app.

Note Ferry uses the CLI’s default model with medium reasoning effort. It deliberately ignores user configuration rather than inheriting custom tools, integrations, or model preferences. A source-branch prototype also offers **Summarize on Mac** through Apple Intelligence on supported Macs running macOS 26 or later; it never falls back to Codex without an explicit click. Other model providers are not implemented.

## Build in Xcode

Open [`Note Ferry.xcodeproj`](../Note%20Ferry.xcodeproj), select the **Note Ferry** scheme and **My Mac**, then choose **Product → Build** (**⌘B**). Xcode runs the same tested `scripts/build.sh` used by `make build`; the finished app is `build/Note Ferry.app` in this repository, not in DerivedData. Open that app from Finder to run it. The Xcode scheme is a build target, so **Product → Run** is not configured.

The Xcode project is checked in. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is only needed if you change `project.yml` and want to regenerate the project with `xcodegen generate`.

## Build and test

```sh
make build     # Build build/Note Ferry.app
make test      # Run the automated checks
make install   # Build and install in ~/Applications
```

| Path | Purpose |
| --- | --- |
| `Sources/main.swift` | AppKit interface and clipboard workflow |
| `Sources/MarkdownFormatter.swift` | Local Markdown parsing and Notes-friendly rich text |
| `Sources/Core.swift` | Summary model, renderer, clipboard helpers, and Codex runner |
| `Sources/LocalSummarizer.swift` | Optional on-device Apple Intelligence summarizer and text chunking |
| `Resources/SummaryPrompt.txt` | Instructions for detailed, source-faithful summaries |
| `Resources/Summary.schema.json` | Structured model-output contract |
| `Resources/AppIcon.svg` | Approved vector icon, with outlined lettering |
| `Resources/Sparkle.LICENSE` | License for the bundled updater |
| `scripts/fetch-sparkle.sh` | Fetch and verify the pinned Sparkle distribution |
| `Tests/` | Synthetic fixture and automated checks |
| `scripts/` | Build, installation, test, and icon-generation tools |

The model supplies structured content. The app owns typography, lists, spacing, and clipboard handling, so these do not depend on how the model formats Markdown. The local prototype accepts up to 100 KB, uses fresh sessions for roughly 4,000-character portions, and consolidates takeaways separately. It can take longer and may be less detailed than Codex. Model availability depends on macOS, hardware, Apple Intelligence settings, and model readiness.

### Preview without a model call

Quit any running copy of Note Ferry first, then launch the synthetic example:

```sh
open 'build/Note Ferry.app' --args --preview "$PWD/Tests/fixture.json"
```

This opens a preview without changing your clipboard. **Copy summary** explicitly copies the result.

### Format Markdown without a model or clipboard change

```sh
'build/Note Ferry.app/Contents/MacOS/Note Ferry' \
  --format-file Tests/format-fixture.md "$PWD/local-output/formatted"
```

This writes `formatted.rtf` and `formatted.txt`. No model is called. Blank input and input over 400,000 UTF-8 bytes are rejected; the transcript minimum length does not apply. These explicit exports persist until you delete them.

The local formatter uses Apple's inline Markdown parser plus block handling for headings, paragraphs, lists, quotes, fenced code, and indented code. A standalone bold line becomes a section heading. It recognizes whole-answer chat code fences containing clear Markdown structure, including mislabeled `vbnet` fences. Markdown syntax is removed while the wording is retained. Native tables and downloaded images are outside its scope.

### Test a real transcript without changing the clipboard

```sh
'build/Note Ferry.app/Contents/MacOS/Note Ferry' \
  --summarize-file /absolute/path/to/transcript.md "$PWD/local-output/example"
```

This sends the source to Codex and saves `summary.json`, `summary.rtf`, and `summary.txt` in the chosen folder. These explicit exports persist until you delete them. The suggested `local-output/` directory is excluded from Git.

### Verification

The automated checks cover local Markdown conversion, inline emphasis and links, ordered and nested lists, literal code, whole-answer fences, short text, RTF round trips, native lists, bold headings, soft returns, section spacing, Unicode, plain-text fallback, clipboard conflicts and restoration, input validation, invalid model responses, authentication failures, cancellation, and timeout.

Clipboard tests use a separate named pasteboard, leaving the regular clipboard alone. They require access to the macOS pasteboard service and may fail in a restrictive execution sandbox.

For manual acceptance, copy the synthetic example and paste it into a note you choose. Check headings, single bullet markers, spacing between items and sections, and native list editing. Destination-app behavior needs visual verification in addition to automated checks.

### Release builds

Build both architectures with a Developer ID Application identity installed in your Keychain:

```sh
BUILD_ARCHS='arm64 x86_64' \
  SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  ./scripts/build.sh
```

The build targets macOS 14, embeds Sparkle with symlinks preserved, signs its helpers and framework before the host app, enables the hardened runtime for Developer ID signing, requests secure timestamps, and verifies the signature. Submit a ZIP of the app using `xcrun notarytool` with credentials saved in Keychain. Once Apple accepts it, review the notarization log, staple the ticket to the app with `xcrun stapler`, and verify with both `stapler validate` and `spctl --assess --type execute`. Create the final download ZIP **after** stapling, and generate its SHA-256 checksum.

Sparkle uses the public EdDSA key in the app’s Info.plist. The matching private key is in the release owner’s login Keychain under the `note-ferry` account; never export or commit it. For each new release, increment `CFBundleVersion`, sign and notarize the app, upload the final ZIP to GitHub Releases, then generate the appcast with the pinned Sparkle tools and the final ZIP. Include the release notes in the appcast, verify its signature, and publish the appcast to the `main` branch only after the ZIP is reachable. The `SUFeedURL` in the app points at the raw `main` version of `appcast.xml`. New builds require an EdDSA-signed archive and feed because verification before extraction and signed-feed checks are enabled. Keep the appcast update process in the release PR so reviewers can check the exact URL, version, and signature.

Version 1.0 did not include Sparkle. Users must install 1.1 manually once; subsequent updates can use the app menu. A source build also points to the official feed, so fork maintainers should change the URL and public key to their own before distributing their app. Never commit signing keys or notarization credentials.

## Rendering for Apple Notes

Rich text that looks well spaced elsewhere can paste densely into Notes. Note Ferry encodes spacing directly into the text:

| Between | Formatting |
| --- | --- |
| Bullet items | A soft return inside the preceding item, producing a blank line without an empty bullet |
| Sections | Two empty paragraphs before the heading |
| Heading and content | One empty paragraph after the heading |

Headings and labels are bold. Bullets use native list metadata rather than decorative characters. The clipboard also includes a plain-text fallback with equivalent spacing.

## Contributing

Bug reports, formatting improvements, and compatibility reports are welcome. Include your macOS and Codex CLI versions and a small synthetic example that reproduces the issue.

Please do not include private transcripts, real meeting summaries, credentials, or screenshots containing personal information in issues or pull requests. Keep generated output in `local-output/` and run `make test` for changes to the renderer, clipboard handling, or backend.

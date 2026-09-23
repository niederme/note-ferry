# Development

[Back to Summary Notes](../README.md) · [Roadmap](../ROADMAP.md)

Build, test, and contribute to Summary Notes. For the ready-to-use app, see the [download instructions](../README.md#download).

## Requirements

- macOS 14 or later. Runtime testing so far has been on Apple silicon with macOS 27.
- A recent Xcode or Xcode Command Line Tools installation providing Swift and the macOS SDK.
- Codex CLI supporting `exec`, `--ephemeral`, `--ignore-user-config`, and `--output-schema`, signed in for live summarization.

There are no third-party Swift or Python library dependencies. The app uses AppKit. Codex is an external runtime dependency and is not bundled.

## Install from source

Clone this repository and enter its directory:

```sh
git clone https://github.com/niederme/summary-notes.git
cd summary-notes
```

For **Summarize & format**, make sure Codex CLI is installed and signed in. **Format only** does not use Codex:

```sh
codex --version
codex login
```

See the [official Codex documentation](https://developers.openai.com/codex/) for installation and account setup. Then build and install:

```sh
make install
```

This installs `~/Applications/Summary Notes.app` and registers it with Launch Services. An existing installation is preserved under `~/Applications/Summary Notes backups/` in a dated folder.

Spotlight indexing may take a little time. Open the app directly from your home folder’s Applications directory if needed. Raycast may need its application list refreshed. No Service, Shortcut, or keyboard shortcut setup is required.

Source builds target your Mac’s architecture and are ad-hoc signed for local use. The downloadable release is separately signed and notarized.

### Codex account and usage

The app reuses your Codex CLI login. With a ChatGPT login, you do not need a separate API key in Summary Notes. Requests consume your Codex account allowance and remain subject to its limits and terms.

Codex is discovered in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or the standard Codex app bundle location. Other installation paths are not currently configurable in the app.

Summary Notes uses the CLI’s default model with medium reasoning effort. It deliberately ignores user configuration rather than inheriting custom tools, integrations, or model preferences. Apple Intelligence and other model providers are not implemented.

## Build and test

```sh
make build     # Build build/Summary Notes.app
make test      # Run the automated checks
make install   # Build and install in ~/Applications
```

| Path | Purpose |
| --- | --- |
| `Sources/main.swift` | AppKit interface and clipboard workflow |
| `Sources/MarkdownFormatter.swift` | Local Markdown parsing and Notes-friendly rich text |
| `Sources/Core.swift` | Summary model, renderer, clipboard helpers, and Codex runner |
| `Resources/SummaryPrompt.txt` | Instructions for detailed, source-faithful summaries |
| `Resources/Summary.schema.json` | Structured model-output contract |
| `Tests/` | Synthetic fixture and automated checks |
| `scripts/` | Build, installation, test, and icon-generation tools |

The model supplies structured content. The app owns typography, lists, spacing, and clipboard handling, so these do not depend on how the model formats Markdown.

### Preview without a model call

Quit any running copy of Summary Notes first, then launch the synthetic example:

```sh
open 'build/Summary Notes.app' --args --preview "$PWD/Tests/fixture.json"
```

This opens a preview without changing your clipboard. **Copy summary** explicitly copies the result.

### Format Markdown without a model or clipboard change

```sh
'build/Summary Notes.app/Contents/MacOS/SummaryNotes' \
  --format-file Tests/format-fixture.md "$PWD/local-output/formatted"
```

This writes `formatted.rtf` and `formatted.txt`. No model is called. Blank input and input over 400,000 UTF-8 bytes are rejected; the transcript minimum length does not apply. These explicit exports persist until you delete them.

The local formatter uses Apple's inline Markdown parser plus block handling for headings, paragraphs, lists, quotes, fenced code, and indented code. A standalone bold line becomes a section heading. It recognizes whole-answer chat code fences containing clear Markdown structure, including mislabeled `vbnet` fences. Markdown syntax is removed while the wording is retained. Native tables and downloaded images are outside its scope.

### Test a real transcript without changing the clipboard

```sh
'build/Summary Notes.app/Contents/MacOS/SummaryNotes' \
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

The build explicitly targets macOS 14, enables the hardened runtime for Developer ID signing, requests a secure timestamp, and verifies the signature. Submit a ZIP of the app using `xcrun notarytool` with credentials saved in Keychain. Once Apple accepts it, review the notarization log, staple the ticket to the app with `xcrun stapler`, and verify with both `stapler validate` and `spctl --assess --type execute`. Create the final download ZIP **after** stapling, and generate its SHA-256 checksum. Never commit signing keys or notarization credentials.

## Rendering for Apple Notes

Rich text that looks well spaced elsewhere can paste densely into Notes. Summary Notes encodes spacing directly into the text:

| Between | Formatting |
| --- | --- |
| Bullet items | A soft return inside the preceding item, producing a blank line without an empty bullet |
| Sections | Two empty paragraphs before the heading |
| Heading and content | One empty paragraph after the heading |

Headings and labels are bold. Bullets use native list metadata rather than decorative characters. The clipboard also includes a plain-text fallback with equivalent spacing.

## Contributing

Bug reports, formatting improvements, and compatibility reports are welcome. Include your macOS and Codex CLI versions and a small synthetic example that reproduces the issue.

Please do not include private transcripts, real meeting summaries, credentials, or screenshots containing personal information in issues or pull requests. Keep generated output in `local-output/` and run `make test` for changes to the renderer, clipboard handling, or backend.

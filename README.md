<img src="docs/images/app-icon.png" width="96" height="96" alt="Summary Notes app icon">

# Summary Notes

**Copy a transcript. Launch the app. Paste readable notes into Apple Notes.**

Summary Notes is a small native macOS app that turns a raw call transcript into a detailed, scannable summary and puts the result on your clipboard as rich text. It accepts plain text or Markdown copied from Nook, Granola, or another transcription app.

You choose where to paste. Summary Notes never creates or edits an Apple Note.

<img src="docs/images/app.jpg" width="760" alt="Summary Notes showing a fictional website launch meeting, with spaced bullet points, key takeaways, action items, and a Copy summary button">

*A sample summary with takeaways, action items, and formatting ready for Apple Notes.*

## How it works

1. **Copy** the full transcript.
2. **Launch Summary Notes** from Spotlight, Raycast, or Applications. Summarization starts automatically.
3. Wait for **Ready to paste**, then press **⌘V** in Apple Notes.

The app shows progress while Codex processes the transcript, then displays a formatted preview. Use normal Paste, not Paste and Match Style, which removes formatting.

## What you get

- Key takeaways and clearly separated action items.
- Detailed topic sections with bold labels and native bullets.
- Relevant open questions and transcription uncertainties.
- Real blank lines that do not depend on paragraph-margin styling.
- A preview, cancellation, retry, and restoration of the original clipboard.

The summary instructions prioritize the actual transcript over any automatic summary included in the export. They address duplicated speech, unreliable speaker labels, conflicting names, and the difference between a suggestion and a commitment. Model output can still contain errors, so review consequential details.

### Spacing for Apple Notes

Rich text that looks well spaced elsewhere can paste densely into Notes. Summary Notes encodes spacing directly into the text:

| Between | Formatting |
| --- | --- |
| Bullet items | A soft return inside the preceding item, producing a blank line without an empty bullet |
| Sections | Two empty paragraphs before the heading |
| Heading and content | One empty paragraph after the heading |

Headings and labels are bold. Bullets use native list metadata rather than decorative characters. The clipboard also includes a plain-text fallback with equivalent spacing.

## Requirements

- **macOS:** the app targets macOS 14 or later; testing so far has been on macOS 27. Older supported versions still need verification.
- **Build tools:** a recent Xcode or Xcode Command Line Tools installation providing Swift and the macOS SDK.
- **Codex CLI:** a version supporting `exec`, `--ephemeral`, `--ignore-user-config`, and `--output-schema`, signed in with an account that can use Codex.
- **Internet access** for summarization.

There are no third-party Swift or Python library dependencies. The build uses AppKit and macOS command-line tools. Codex is an external runtime dependency and is not bundled with the app.

## Install from source

Clone this repository and enter its directory:

```sh
git clone https://github.com/niederme/summary-notes.git
cd summary-notes
```

Make sure Codex CLI is installed and signed in:

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

The build targets your Mac’s architecture and is ad-hoc signed for local use. This repository does not currently provide a notarized download or universal binary.

### Codex account and usage

The app reuses your Codex CLI login. With a ChatGPT login, you do not need a separate API key in Summary Notes. Requests consume your Codex account allowance and remain subject to its limits and terms.

Codex is discovered in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or the standard Codex app bundle location. Other installation paths are not currently configurable in the app.

Summary Notes uses the CLI’s default model with medium reasoning effort. It deliberately ignores user configuration rather than inheriting custom tools, integrations, or model preferences. Apple Intelligence and other model providers are not implemented.

## Clipboard behavior and recovery

| Situation | What happens |
| --- | --- |
| Summary succeeds | Rich text replaces the original clipboard and appears in the preview. |
| You copy something while it runs | Your newer clipboard stays intact. Use **Copy summary** when ready. |
| Request fails or is cancelled | The clipboard stays intact. **Retry transcript** uses the original source. |
| You choose **Restore transcript** | The original clipboard contents and formats return, provided the clipboard has not changed since the summary was copied. |
| You close the window | Processing continues. Reopen the app to see the result. |
| You quit the app | Processing is cancelled and the in-memory preview and backup are discarded. |

To process another transcript, copy it and launch the app again, choose **Summarize clipboard**, or use **Summary Notes → Summarize Clipboard** (**⌘N**).

Inputs must contain at least 100 characters and no more than 400,000 UTF-8 bytes. Larger inputs are rejected rather than silently truncated. Requests time out after ten minutes.

## Privacy and data handling

**Summarization sends the transcript to OpenAI through Codex. It is not an on-device AI workflow.** Rich-text formatting happens locally.

- The app holds the source, preview, and clipboard backup in memory. It has no saved transcript library.
- The transcript is passed over standard input, not in command-line arguments or a source file.
- The result is temporarily written into a randomly named directory accessible to the current user. The worker removes that directory when it exits normally. A forced exit, app termination before cleanup finishes, or power loss can leave a temporary result behind.
- Codex runs with `--ephemeral`, a read-only sandbox, approval prompts disabled, and user configuration ignored. The integration disables shell execution, app connectors, plugins, hooks, memory, browser, computer, image, and multi-agent features. It reuses saved authentication without copying credentials.
- Ephemeral mode disables normal session rollout persistence. It does not change OpenAI’s service-side data handling or guarantee that the CLI produces no operational metadata. See [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
- Clipboard managers and system clipboard services may retain or synchronize copied content according to their own settings.

Transcripts are treated as source material to summarize, not as instructions to execute. The app performs no web research or external fact checking.

## Development

```sh
make build     # Build build/Summary Notes.app
make test      # Run the automated checks
make install   # Build and install in ~/Applications
```

| Path | Purpose |
| --- | --- |
| `Sources/main.swift` | AppKit interface and clipboard workflow |
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

### Test a real transcript without changing the clipboard

```sh
'build/Summary Notes.app/Contents/MacOS/SummaryNotes' \
  --summarize-file /absolute/path/to/transcript.md "$PWD/local-output/example"
```

This sends the source to Codex and saves `summary.json`, `summary.rtf`, and `summary.txt` in the chosen folder. These explicit exports persist until you delete them. The suggested `local-output/` directory is excluded from Git.

### Verification

The automated checks cover RTF round trips, native lists, bold headings, soft returns, section spacing, Unicode, plain-text fallback, clipboard conflicts and restoration, input validation, invalid model responses, authentication failures, cancellation, and timeout.

Clipboard tests use a separate named pasteboard, leaving the regular clipboard alone. They require access to the macOS pasteboard service and may fail in a restrictive execution sandbox.

For manual acceptance, copy the synthetic example and paste it into a note you choose. Check headings, single bullet markers, spacing between items and sections, and native list editing. Destination-app behavior needs visual verification in addition to automated checks.

## Contributing

Bug reports, formatting improvements, and compatibility reports are welcome. Include your macOS and Codex CLI versions and a small synthetic example that reproduces the issue.

Please do not include private transcripts, real meeting summaries, credentials, or screenshots containing personal information in issues or pull requests. Keep generated output in `local-output/` and run `make test` for changes to the renderer, clipboard handling, or backend.

## Author and license

Created by **John Niedermeyer**, with AI-assisted development.

Released under the [MIT License](LICENSE). You may use, modify, and redistribute the software, including commercially, as long as you retain the copyright and license notice in copies or substantial portions. MIT does not require visible in-app credit or publication of your modifications.

The license covers this project's code and documentation. It does not grant rights to third-party tools, services, or trademarks, or change their terms. This is an independent project, not affiliated with Apple, OpenAI, Nook, or Granola.

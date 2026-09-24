<img src="docs/images/app-icon.png" width="96" height="96" alt="Note Ferry app icon">

# Note Ferry

**Turn your text into notes worth keeping (with a summary if you want one).**

Note Ferry is a small native macOS app that formats text for Apple Notes and puts the result on your clipboard as rich text. Bring an AI reply, your own writing, or any plain text or Markdown you want to keep. For longer material, such as a meeting transcript from [Nook](https://www.common-tools.co/nook) or [Granola](https://www.granola.ai/), you can create a detailed, scannable summary first.

You choose where to paste. Note Ferry never creates or edits an Apple Note.

<img src="docs/images/app.jpg" width="760" alt="Note Ferry showing a fictional website launch meeting, with spaced bullet points, key takeaways, action items, and a Copy summary button">

*A sample summary with takeaways, action items, and formatting ready for Apple Notes.*

## Why Note Ferry?

You may already have a way to record and transcribe calls, and prefer to keep your finished notes in Apple Notes. Note Ferry handles the step in between: turn the full transcript into detailed topic notes and action items, then copy them with bold headings, native bullets, and enough space to read comfortably after pasting. It can also format existing Markdown without changing its wording.

The original workflow was recording with Nook, sometimes using Granola, and copying transcripts into an AI chat to summarize them. Getting the detail and Apple Notes formatting right took extra work. This app makes that repeatable without writing to your notes or keeping another meeting library.

[Nook](https://www.common-tools.co/nook) records and transcribes meetings on your Mac and already produces local summaries and Markdown files. You can keep using it for capture and bring its full transcript here when you want another summary formatted for Apple Notes. [Granola](https://www.granola.ai/) combines meeting transcription, enhanced notes, and calendar features. Note Ferry is useful when you want this particular output in Apple Notes or use transcripts from several tools.

Note Ferry is free and open source, with no separate app subscription. **Summarize & format requires a signed-in Codex account and uses its allowance.** It sends transcript text to OpenAI, including transcripts captured locally by Nook. **Format only** runs on your Mac without an account. Apple Intelligence summarization is [planned](ROADMAP.md).

## Format existing text

**Format only** is for writing you already want to keep: AI replies, your own notes, or any Markdown text. It converts headings, bold and italic text, links, and lists into rich text for Apple Notes, without rewriting or summarizing the words. It runs locally and needs no account or internet connection.

Paste your text and click **Format only**. Paste into Apple Notes with **⌘V**. **Copy formatted text** copies it again. Choose **Summarize & format** when you want Codex to turn a raw transcript into a summary first. Both actions sit below the text area, with **Clear** separated on the right. Nothing is processed or sent until you click one.

Both options use spaced native lists, preserve a newer clipboard, and offer **Restore clipboard** after copying. Common Markdown is supported, including numbered and nested lists, quotes, and code blocks. Images are not downloaded and tables are not converted into native Notes tables. Formatting is not a complete Markdown publishing engine.

## Download

Download Note Ferry 1.0 (build 2), signed with Developer ID and notarized by Apple:

**[Download Note Ferry 1.0 for Mac](https://github.com/niederme/note-ferry/releases/download/v1.0.0/Note-Ferry-1.0-universal.zip)**

Unzip the download and move **Note Ferry.app** to Applications. The universal app includes both Apple silicon and Intel versions. You do not need Xcode.

**Summarize & format requires Codex CLI, a signed-in Codex account, and internet access.** Install Codex using the [official setup instructions](https://developers.openai.com/codex/cli/), then run `codex login` in Terminal. Note Ferry uses that login and your account’s usage allowance. With a ChatGPT login, you do not need a separate API key in this app. **Format only** needs neither Codex nor an account.

Requires macOS 14 or later. Runtime testing has been on Apple silicon with macOS 27; Intel hardware and older macOS versions have not been tested. See the [release notes and checksum](https://github.com/niederme/note-ferry/releases/tag/v1.0.0).

## How to use Note Ferry

1. Copy the text you want to keep, such as an AI reply, your own notes, or a meeting transcript.
2. Open Note Ferry, paste the text, and choose **Summarize & format** for a Codex summary or **Format only** to preserve the wording.
3. When the result is ready and copied, paste it into Apple Notes with **⌘V**.

Use normal Paste to keep the formatting. **Paste and Match Style** removes it.

Summaries include key takeaways, action items, and detailed topic sections, with bold headings and spaced bullets. Open questions and unclear transcription details are called out when relevant. Review important details, since AI summaries can contain mistakes. **Format only** preserves the original wording and formats the structure already present in your text.

## Working with summaries

- **Copy summary** copies the formatted result again.
- **Copy formatted text** copies a locally formatted result again.
- **Clear** empties the window and leaves your clipboard alone. You can also select all (**⌘A**) and paste another text selection.
- If you copy something else while processing, the app preserves your newer clipboard. Your summary waits in the window until you choose **Copy summary**.
- **Cancel** stops processing. Your transcript remains available to edit or retry.
- **Restore clipboard**, when available, restores what was on the clipboard when you started, provided you have not copied something else since the summary was copied.

Leave the app open throughout the day if you like. It does not monitor your clipboard or start processing on launch, reopening, or paste. Processing begins only when you choose **Format only** or **Summarize & format**.

Closing the window lets processing continue. Quitting cancels it and discards the in-memory transcript, summary, and clipboard backup. The app does not save a transcript library.

## Privacy

Summarization sends your transcript to **OpenAI through Codex**. Formatting happens on your Mac. Note Ferry never creates or edits an Apple Note.

The app normally removes its temporary model output when processing finishes; an interrupted shutdown can leave a temporary file behind. Clipboard managers may retain copied content. [Read the data-handling details](docs/PRIVACY.md).

## Help

If Codex is missing or signed out, install it and run `codex login` in Terminal. If your account reaches a usage limit, wait for it to reset before retrying. Failed or cancelled requests leave your clipboard intact.

Transcripts must contain at least 100 characters and fit within a 400,000-byte limit. Larger transcripts are rejected rather than cut off. Processing times out after ten minutes.

[Report a problem](https://github.com/niederme/note-ferry/issues), including your macOS and Codex versions and a small fictional example. Please leave private transcripts and credentials out of reports.

## What’s next

Planned: Apple Intelligence as the default for eligible Macs without another service configured, Claude support, optional API connections, a preferred provider in Settings, and a provider picker for trying another result. See the [roadmap](ROADMAP.md) for scope and constraints.

## Build or contribute

See the [development guide](docs/DEVELOPMENT.md) for source installation, architecture, tests, and release builds.

## Author and license

Created by **John Niedermeyer**, with AI-assisted development.

Released under the [MIT License](LICENSE). You may use, modify, and redistribute the software, including commercially, as long as you retain the copyright and license notice in copies or substantial portions. MIT does not require visible in-app credit or publication of your modifications.

The license covers this project's code and documentation. It does not grant rights to third-party tools, services, or trademarks, or change their terms. This is an independent project, not affiliated with Apple, OpenAI, Nook, or Granola.

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

Note Ferry is free and open source, with no app subscription. **Format only** runs on your Mac without an account. For **Summarize & format**, choose Apple Intelligence on a compatible Mac, your signed-in Codex account, or your own Claude API key. Codex sends text to OpenAI; Claude sends it to Anthropic. Apple Intelligence summarizes on your Mac.

## Format existing text

**Format only** is for writing you already want to keep: AI replies, your own notes, or any Markdown text. It converts headings, bold and italic text, links, and lists into rich text for Apple Notes, without rewriting or summarizing the words. It runs locally and needs no account or internet connection.

Paste your text and click **Format only**. Paste into Apple Notes with **⌘V**. **Copy formatted text** copies it again. Choose **Summarize & format** when you want your selected summarizer to turn a raw transcript into a summary first. Both actions sit below the text area, with **Clear** separated on the right. Nothing is processed or sent until you click one.

Both options use spaced native lists, preserve a newer clipboard, and offer **Restore clipboard** after copying. Common Markdown is supported, including numbered and nested lists, quotes, and code blocks. Images are not downloaded and tables are not converted into native Notes tables. Formatting is not a complete Markdown publishing engine.

## Download

Download Note Ferry 1.2 (build 4), signed with Developer ID and notarized by Apple:

**[Download Note Ferry 1.2 for Mac](https://github.com/niederme/note-ferry/releases/download/v1.2.0/Note-Ferry-1.2-universal.zip)**

Unzip the download and move **Note Ferry.app** to Applications, replacing an earlier copy. If you already have 1.1, you can instead choose **Note Ferry → Check for Updates…** after the signed update feed is published. The universal app includes Apple silicon and Intel versions. Xcode is not required.

**Apple Intelligence** needs macOS 26 or later, a compatible Mac, and Apple Intelligence enabled. **Codex** needs the [Codex CLI](https://developers.openai.com/codex/cli/), a signed-in Codex account, and internet access; run `codex login` in Terminal. **Claude** needs an Anthropic API key and internet access; API use is billed separately from a Claude subscription. **Format only** needs no account or internet connection.

The app requires macOS 14 or later. Runtime testing has been on Apple silicon with macOS 27; Intel hardware and older macOS versions have not been tested. See the [release notes and checksum](https://github.com/niederme/note-ferry/releases/tag/v1.2.0).

## Updates

Choose **Note Ferry → Check for Updates…** whenever you want to check. On the second launch, Sparkle asks whether it may check automatically in the background. That choice is yours; automatic installation is off by default. Update checks use a signed feed on GitHub and do not send your text or transcript.

## How to use Note Ferry

1. Copy the text you want to keep, such as an AI reply, your own notes, or a meeting transcript.
2. Open Note Ferry, paste the text, and choose **Summarize & format** with the provider you want, or **Format only** to preserve the wording.
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

Apple Intelligence summarizes on your Mac. Codex sends text to OpenAI, and Claude sends text to Anthropic after a first-use confirmation. Formatting happens on your Mac with every option. Note Ferry never creates or edits an Apple Note.

The app normally removes its temporary model output when processing finishes; an interrupted shutdown can leave a temporary file behind. Clipboard managers may retain copied content. [Read the data-handling details](docs/PRIVACY.md).

## Help

If Codex is missing or signed out, install it and run `codex login` in Terminal. If Claude rejects a key, create a new one in Anthropic Console and replace it in Settings. If Apple Intelligence is unavailable, check its status in System Settings or choose another provider. Failed or cancelled requests leave your clipboard intact.

Text to summarize must contain at least 100 characters. Codex and Claude accept up to 400 KB; Apple Intelligence currently accepts up to 100 KB. Larger input is rejected rather than cut off. Codex and Claude requests time out after ten minutes.

[Report a problem](https://github.com/niederme/note-ferry/issues), including your macOS version, selected summarizer, and a small fictional example. Please leave private transcripts and credentials out of reports.

## Choose a summarizer

On first launch, **Choose a summarizer** asks for a default. Apple Intelligence is preselected on a new install, even if it is unavailable on that Mac; choose Codex or Claude instead if needed. Change your default later in **Note Ferry → Settings…**, or use the picker beside **Summarize & format** for one piece of text. The picker never starts processing by itself. **Format only** stays local regardless of the selected summarizer.

For Claude, copy an API key from Anthropic Console and click **Save key from clipboard** in Settings. Note Ferry stores it in this Mac’s Keychain and clears the copied key if it is still on the clipboard after a successful save. Your first Claude summary asks you to confirm sending the text and key to Anthropic. A saved key is not proof that Anthropic will accept it.

## What’s next

The [roadmap](ROADMAP.md) covers evaluation of on-device summary quality, comparing results from different providers, and possible additional connection options. No date is promised for the next release.

## Build or contribute

See the [development guide](docs/DEVELOPMENT.md) for source installation, architecture, tests, and release builds.

## Author and license

Created by **John Niedermeyer**, with AI-assisted development.

Released under the [MIT License](LICENSE). You may use, modify, and redistribute the software, including commercially, as long as you retain the copyright and license notice in copies or substantial portions. MIT does not require visible in-app credit or publication of your modifications.

The license covers this project's code and documentation. Sparkle is bundled under its [own license](Resources/Sparkle.LICENSE). The project license does not grant rights to other third-party tools, services, or trademarks, or change their terms. This is an independent project, not affiliated with Apple, OpenAI, Nook, or Granola.

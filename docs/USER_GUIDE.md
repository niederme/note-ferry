# Note Ferry user guide

[Back to Note Ferry](../README.md)

Setup, clarification questions, formatting, and clipboard behavior for Note Ferry 2.1. For an overview and the download, see the [README](../README.md). For data handling, see [Privacy](PRIVACY.md).

## How to use Note Ferry

1. Copy the text you want to keep, such as an AI reply, your own notes, or a meeting transcript.
2. Open Note Ferry, paste the text, and choose **Summarize & format** with the provider you want, or **Format only** to preserve the wording.
3. If clarification questions appear, answer what you can and choose **Continue interview**, or **Finish & summarize** to proceed now.
4. When the result is ready and copied, paste it into Apple Notes with **⌘V**.

Use normal Paste to keep the formatting. **Paste and Match Style** removes it.

## Choose a summarizer

Apple Intelligence requires a compatible Mac with macOS 26 or later and Apple Intelligence enabled. Codex and Claude require internet access. Claude API usage is billed separately from a Claude subscription.

On first launch, choose **Set Up Summaries** for provider-specific setup, or **Use Format Only** to start without an account. Setup shows whether the selected provider is available and never silently switches providers. Reopen the same flow with **Note Ferry → Settings… → Run Setup Again…**; saved connections and preferences are preserved. Change your default in Settings, or use the bottom-bar picker for the current text. **Format only** stays local regardless of the summarizer.

### Codex

Install the [Codex CLI](https://developers.openai.com/codex/cli/) and run `codex login` in Terminal. Codex uses your signed-in account and lets the CLI choose its built-in default model. To use another model available to your account, enter its ID in **Settings → Model options**. Note Ferry does not force a reasoning-effort setting or silently switch models if your selected model is unavailable. It keeps requests isolated from your personal CLI configuration and tools.

### Claude

For a one-paste Claude setup, create an API key scoped to Anthropic’s **Default workspace**, then choose **Paste & connect** in Settings. That button saves and checks the key in one click. You can also paste into the field and choose **Connect**. The key is masked while editing unless you choose **Show key**, cleared from the field after saving, and stored in this Mac’s Keychain. The clipboard is left unchanged. Note Ferry checks the key with Anthropic without sending a transcript. If that check fails, **Retry connection** checks the saved key again without another paste.

For an organization-wide key, Note Ferry selects the Default workspace when Anthropic makes it available. If Default cannot be determined, Settings asks for a workspace ID and links to the workspace list. The key remains saved, so you only enter the workspace ID. Your first Claude summary asks you to confirm sending the text and key to Anthropic.

## Clarify before summarizing

Before writing a summary, Note Ferry can interview you about meaningful ambiguities in a transcript, rough notes, or other text. The interview is on by default. When you choose **Summarize & format**, the selected model first checks the text in the background. If the model returns questions, the interview appears. Otherwise, summarization continues automatically. Choose **Summarize now** while the check is running to skip waiting for questions. If the initial check fails, **Continue without questions** goes straight to the summary. Leave answers blank and choose **Finish & summarize** to skip the questions. In **Settings**, turn off **Ask clarifying questions before summarizing** to always go straight to summarization.

Questions arrive in small batches, with exact source excerpts when useful and visible radio-button suggestions when supported. Selecting **Something else** reveals a free-text field; questions without suggestions show that field immediately. Answer what you can, including corrections to a question’s premise. **Continue interview** lets the model ask useful follow-ups; **Finish & summarize** uses your answers immediately. **Answers…** lets you review earlier submitted answers, including after a follow-up request fails. Each round has up to three questions; there is no fixed three-question total. **Cancel** discards the unfinished interview and returns to your source. Submitted answers remain available to retry a failed final summary until you edit the input.

Interviews use more tokens and time, and Claude API requests can cost more. Requests stay with the provider you selected. Apple Intelligence has a smaller context budget and may ask you to shorten answers or finish earlier; nothing is silently truncated. Answers remain in memory for the current text and appear under **Context used** with the result. The clipboard stays unchanged throughout the interview, and a newer clipboard is protected when the summary finishes.

### Keyboard controls

| Key | Action |
| --- | --- |
| Tab / Shift-Tab | Move forward / backward through answers |
| Arrow keys | Change the selection in a radio group |
| Return in a text field | Insert a newline |
| ⌘Return | Continue the interview |

Outside the interview, **⌘Return** summarizes input or copies a result, and **⇧⌘Return** formats input without AI. The **Text** menu exposes these commands and clipboard/context actions. **⌘N** keeps its existing Clear behavior.

## Format existing text

**Format only** is for writing you already want to keep: AI replies, your own notes, or any Markdown text. It converts headings, bold and italic text, links, and lists into rich text for Apple Notes, without rewriting or summarizing the words. It runs locally and needs no account or internet connection.

Paste your text and click **Format only**. Paste into Apple Notes with **⌘V**. **Copy formatted text** copies it again. Choose **Summarize & format** when you want your selected summarizer to turn a raw transcript into a summary first. Both actions are in the fixed bottom action bar, with **Clear** separated from processing commands. Nothing is processed or sent until you click one.

Both options use spaced native lists, preserve a newer clipboard, and offer **Restore previous clipboard** after copying. Common Markdown is supported, including numbered and nested lists, checklists, quotes, divider lines, code blocks, and tables. Tables retain a grid with wrapped cells in rich text and HTML clipboard formats; how they paste depends on the receiving app. Checklist states remain visible checkbox symbols. Images become links using their description and are not downloaded. Formatting is not a complete Markdown publishing engine.

**Format only** preserves the original wording and formats the structure already present in your text. It keeps plain-text line breaks and adds a blank line between complete sentences or questions entered on separate lines. In Markdown documents, ordinary soft-wrapped lines continue to follow Markdown rules.

## Working with summaries

Summaries include key takeaways, action items, and detailed topic sections, with bold headings and spaced bullets. Open questions and unclear transcription details are called out when relevant. Review important details, since AI summaries can contain mistakes.

- Before summarizing, use the small **Context (optional)** field beneath the transcript to supply names, terminology, or background. It is open by default and can be collapsed. For example: “NOVA is our planning tool. Jamie leads the project.” Context is limited to 1,000 characters and applies to this summary only. It works with Apple Intelligence, Codex, and Claude. **Format only** ignores it.
- Context stays available after cancellation or an error. Collapsing the field keeps it included; empty the field to omit it. **Clear**, pasting new text over a result, or quitting discards it. It is not saved as a glossary.
- **Copy summary** copies the formatted result again.
- When context or interview answers were supplied, **Context used** is collapsed beneath the summary. Expand it to read and select the context and answers. **Copy context** copies it separately; it is never appended to **Copy summary**.
- The information button beside the result’s provider attribution shows elapsed time and provider-reported input/output token counts when available. Usage includes reported interview requests, instructions, context, and summary generation. Complete totals are unavailable when a request is cancelled or a provider does not report usage. Apple Intelligence reports usage on macOS 27 or later, summed across portions and overview passes; on macOS 26, usage is unavailable. These counts are not costs or remaining subscription limits.
- **Copy formatted text** copies a locally formatted result again.
- **Clear** empties the window and leaves your clipboard alone. You can also select all (**⌘A**) and paste another text selection.
- If you copy something else while processing, the app preserves your newer clipboard. Your summary waits in the window until you choose **Copy summary**.
- **Cancel** stops processing. Your transcript remains available to edit or retry.
- **Restore previous clipboard** restores the content Note Ferry replaced, provided the clipboard still contains its last copy. Repeated copies from Note Ferry keep the same backup. If you copy something else and then use a Note Ferry copy button, that newer content becomes the backup.

Leave the app open throughout the day if you like. It does not monitor your clipboard or start processing on launch, reopening, or paste. Processing begins only when you choose **Format only** or **Summarize & format**.

Closing the window lets processing continue. Quitting cancels it and discards the in-memory transcript, summary, and clipboard backup. The app does not save a transcript library.

## Updates

Choose **Note Ferry → Check for Updates…** whenever you want to check. On the second launch, Sparkle asks whether it may check automatically in the background. That choice is yours; automatic installation is off by default. Update checks use a signed feed on GitHub and do not send your text or transcript.

## Troubleshooting and limits

If the initial clarification check fails, the app returns to your input with an error. Retry or choose **Continue without questions**. If a later round fails, **Answers…** keeps submitted answers available; choose **Retry questions** or **Continue to summary**. Turn off the interview in Settings to skip future checks.

If Codex is missing or signed out, install it and run `codex login` in Terminal. If Claude rejects a key, create a new one in Anthropic Console and replace it in Settings. If Apple Intelligence is unavailable, check its status in System Settings or choose another provider. Failed or cancelled requests leave your clipboard intact.

Each interview answer is limited to 2,000 characters. The combined answered questions and answers, including their labels and separators, must fit within 24,000 characters for Codex/Claude or 1,800 for Apple Intelligence. Apple’s interview history has an additional context limit. If a limit is reached, shorten answers or finish with the accepted answers; the app does not silently truncate them.

Text to summarize must contain at least 100 characters. Codex and Claude accept up to 400 KB; Apple Intelligence currently accepts up to 100 KB. Larger input is rejected rather than cut off. Each Codex or Claude request times out after ten minutes; an interview can involve several requests.

[Report a problem](https://github.com/niederme/note-ferry/issues), including your macOS version, selected summarizer, and a small fictional example. Please leave private transcripts and credentials out of reports.

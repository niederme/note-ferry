# Privacy and data handling

[Back to Note Ferry](../README.md)

In version 1.2, **Summarize & format** uses the provider you select: Apple Intelligence on a compatible Mac, Codex through OpenAI, or Claude through Anthropic. Rich-text formatting happens locally. **Format only** runs entirely on your Mac; it does not call a model, load linked pages or images, or require an account.

Apple Intelligence uses Apple's on-device Foundation Models framework on eligible Macs. Claude uses your own Anthropic API key. The chosen provider is shown before you summarize; failure never silently switches providers. Apple Intelligence may need to download its model before it is available.

- The app holds the source, optional context, interview questions and answers, preview, and clipboard backup in memory. It has no saved transcript library or glossary. Context and interview answers are discarded when you clear the window, replace a result with new text, or quit.
- Optional context follows the selected summarizer: it stays on the Mac with Apple Intelligence, is sent to OpenAI with Codex, or is sent to Anthropic with Claude. **Format only** ignores context.
- In development builds, an optional clarification interview precedes summarization. Its on/off setting is saved in preferences; the questions and answers are not. Starting or continuing the interview sends the source, context, and prior questions and answers to the selected provider. Skipping before it starts makes no interview request. Each round may use more tokens and increase API costs. Cancelling an in-flight request cannot undo processing already performed by a provider.
- Interview answers guide the summary without becoming original-source evidence. Submitted answers are kept for a summary retry if the final request fails, until the input is edited, cleared, or the app quits. Cancelling the interview before summary generation discards its answers and returns to the original input. The interview does not change the clipboard. The original clipboard snapshot is retained across the interview to protect anything copied while answering.
- For Codex, the transcript, context, and interview history are passed over standard input, not in command-line arguments or a source file.
- Codex's structured event stream is read in memory to collect reported token counts and error status. Event lines are bounded and discarded after parsing; the app does not save this stream. Usage counts and the read-only context shown with a result are not included in **Copy summary**. Context is copied only when you select and copy it or choose **Copy context**.
- For Codex, the summary or interview response is temporarily written into a randomly named directory accessible to the current user. The worker removes that directory when it exits normally. A forced exit, app termination before cleanup finishes, or power loss can leave a temporary result behind.
- Codex runs with `--ephemeral`, a read-only sandbox, approval prompts disabled, and user configuration ignored. The integration disables shell execution, app connectors, plugins, hooks, memory, browser, computer, image, and multi-agent features. It reuses saved authentication without copying credentials.
- For Codex, ephemeral mode disables normal session rollout persistence. It does not change OpenAI’s service-side data handling or guarantee that the CLI produces no operational metadata. See [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
- Clipboard managers and system clipboard services may retain or synchronize copied content according to their own settings.


For Claude, you paste an API key into the Settings text field and choose **Save key**, or choose **Paste from clipboard** to save and check the clipboard key in one click. The key is visible while editing and cleared from the field after saving. Note Ferry stores it in its own macOS Keychain item and leaves the system clipboard unchanged. Saving sends the key over HTTPS to Anthropic’s Models API to check access without a transcript. If Anthropic requires a workspace, Note Ferry also calls Anthropic’s List Workspaces API to find Default and checks access to it. The selected workspace ID and name are stored in app preferences. No setup check sends a transcript or makes a Messages API request.

When you choose Claude and click **Summarize & format**, the app asks for confirmation on first use, then sends the selected text, context, interview answers when present, and the key over HTTPS directly to Anthropic's Messages API. The key is used for authentication and is not placed in the transcript or a temporary file. API usage is billed separately from a Claude subscription. A failed or cancelled summary request leaves the clipboard unchanged; the app does not automatically retry with another provider.

Apple Intelligence summarization runs on the Mac through Apple's Foundation Models framework. Formatting text runs locally for every provider.

Transcripts are treated as source material to summarize, not as instructions to execute. The app performs no web research or external fact checking.

Explicit command-line exports made with `--summarize-file` or `--format-file` persist until you delete them. See the [development guide](DEVELOPMENT.md#test-a-real-transcript-without-changing-the-clipboard).

## Software updates

Note Ferry uses Sparkle to check a signed update feed hosted on GitHub. A manual check contacts GitHub when you choose **Check for Updates…**. On the second launch, Sparkle asks whether you want background checks; automatic installation is off by default. Update checks do not include your clipboard contents, transcript, or formatted result. Sparkle's optional system profiling is not enabled. Network services may receive ordinary connection metadata such as your IP address.

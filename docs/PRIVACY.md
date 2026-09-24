# Privacy and data handling

[Back to Note Ferry](../README.md)

In the current 1.1 release, **Summarize & format sends the transcript to OpenAI through Codex**. Rich-text formatting happens locally. **Format only** runs entirely on your Mac. It does not call Codex, load linked pages or images, or require an account.

The development build adds Apple Intelligence through Apple's on-device Foundation Models framework on eligible Macs. It also adds Claude through your own Anthropic API key. The chosen provider is shown before you summarize; failure never silently switches providers. Neither option has shipped in the 1.1 download. Apple Intelligence may need to download its model before it is available.

- The app holds the source, preview, and clipboard backup in memory. It has no saved transcript library.
- For Codex, the transcript is passed over standard input, not in command-line arguments or a source file.
- For Codex, the result is temporarily written into a randomly named directory accessible to the current user. The worker removes that directory when it exits normally. A forced exit, app termination before cleanup finishes, or power loss can leave a temporary result behind.
- Codex runs with `--ephemeral`, a read-only sandbox, approval prompts disabled, and user configuration ignored. The integration disables shell execution, app connectors, plugins, hooks, memory, browser, computer, image, and multi-agent features. It reuses saved authentication without copying credentials.
- For Codex, ephemeral mode disables normal session rollout persistence. It does not change OpenAI’s service-side data handling or guarantee that the CLI produces no operational metadata. See [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
- Clipboard managers and system clipboard services may retain or synchronize copied content according to their own settings.


For Claude in the development build, you explicitly choose **Save key from clipboard** in Settings. Note Ferry stores the copied API key in its own macOS Keychain item and clears it from the system clipboard after a successful save if the clipboard has not changed in the meantime. Clipboard managers may still retain their own history.

When you choose Claude and click **Summarize & format**, the app asks for confirmation on first use, then sends the selected text and the key over HTTPS directly to Anthropic's Messages API. The key is used for authentication and is not placed in the transcript or a temporary file. API usage is billed separately from a Claude subscription. A failed or cancelled summary request leaves the clipboard unchanged; the app does not automatically retry with another provider.

Apple Intelligence summarization runs on the Mac through Apple's Foundation Models framework. Formatting text runs locally for every provider.

Transcripts are treated as source material to summarize, not as instructions to execute. The app performs no web research or external fact checking.

Explicit command-line exports made with `--summarize-file` or `--format-file` persist until you delete them. See the [development guide](DEVELOPMENT.md#test-a-real-transcript-without-changing-the-clipboard).

## Software updates

Note Ferry uses Sparkle to check a signed update feed hosted on GitHub. A manual check contacts GitHub when you choose **Check for Updates…**. On the second launch, Sparkle asks whether you want background checks; automatic installation is off by default. Update checks do not include your clipboard contents, transcript, or formatted result. Sparkle's optional system profiling is not enabled. Network services may receive ordinary connection metadata such as your IP address.

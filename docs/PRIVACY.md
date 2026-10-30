# Privacy and data handling

[Back to Note Ferry](../README.md)

In version 1.2, **Summarize & format** uses the provider you select: Apple Intelligence on a compatible Mac, Codex through OpenAI, or Claude through Anthropic. Rich-text formatting happens locally. **Format only** runs entirely on your Mac; it does not call a model, load linked pages or images, or require an account.

Apple Intelligence uses Apple's on-device Foundation Models framework on eligible Macs. Claude uses your own Anthropic API key. The chosen provider is shown before you summarize; failure never silently switches providers. Apple Intelligence may need to download its model before it is available.

- The app holds the source, optional context, preview, and clipboard backup in memory. It has no saved transcript library or glossary. Context is discarded when you clear the window, replace a result with new text, or quit.
- Optional context follows the selected summarizer: it stays on the Mac with Apple Intelligence, is sent to OpenAI with Codex, or is sent to Anthropic with Claude. **Format only** ignores context.
- For Codex, the transcript and context are passed over standard input, not in command-line arguments or a source file.
- For Codex, the result is temporarily written into a randomly named directory accessible to the current user. The worker removes that directory when it exits normally. A forced exit, app termination before cleanup finishes, or power loss can leave a temporary result behind.
- Codex runs with `--ephemeral`, a read-only sandbox, approval prompts disabled, and user configuration ignored. The integration disables shell execution, app connectors, plugins, hooks, memory, browser, computer, image, and multi-agent features. It reuses saved authentication without copying credentials.
- For Codex, ephemeral mode disables normal session rollout persistence. It does not change OpenAI’s service-side data handling or guarantee that the CLI produces no operational metadata. See [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
- Clipboard managers and system clipboard services may retain or synchronize copied content according to their own settings.


For Claude, you paste an API key into the Settings text field and choose **Save key**, or choose **Paste from clipboard** to save and check the clipboard key in one click. The key is visible while editing and cleared from the field after saving. Note Ferry stores it in its own macOS Keychain item and leaves the system clipboard unchanged. Saving sends the key over HTTPS to Anthropic’s Models API to check access without a transcript. If Anthropic requires a workspace, Note Ferry also calls Anthropic’s List Workspaces API to find Default and checks access to it. The selected workspace ID and name are stored in app preferences. No setup check sends a transcript or makes a Messages API request.

When you choose Claude and click **Summarize & format**, the app asks for confirmation on first use, then sends the selected text and the key over HTTPS directly to Anthropic's Messages API. The key is used for authentication and is not placed in the transcript or a temporary file. API usage is billed separately from a Claude subscription. A failed or cancelled summary request leaves the clipboard unchanged; the app does not automatically retry with another provider.

Apple Intelligence summarization runs on the Mac through Apple's Foundation Models framework. Formatting text runs locally for every provider.

Transcripts are treated as source material to summarize, not as instructions to execute. The app performs no web research or external fact checking.

Explicit command-line exports made with `--summarize-file` or `--format-file` persist until you delete them. See the [development guide](DEVELOPMENT.md#test-a-real-transcript-without-changing-the-clipboard).

## Software updates

Note Ferry uses Sparkle to check a signed update feed hosted on GitHub. A manual check contacts GitHub when you choose **Check for Updates…**. On the second launch, Sparkle asks whether you want background checks; automatic installation is off by default. Update checks do not include your clipboard contents, transcript, or formatted result. Sparkle's optional system profiling is not enabled. Network services may receive ordinary connection metadata such as your IP address.

# Roadmap

[Back to Note Ferry](README.md) · [Development guide](docs/DEVELOPMENT.md)

The current 1.1 download uses Codex CLI for **Summarize & format** and has local **Format only**. The development build adds Apple Intelligence and Claude API summarization, a first-run chooser, a default in Settings, and a per-transcript provider picker. None of these have shipped in the 1.1 download. Other plans have no promised release dates. Keep the core workflow simple: paste text, choose an action, and paste into Apple Notes.

## More ways to summarize

| Provider | Intended access | Direction |
| --- | --- | --- |
| Apple Intelligence | Apple's on-device model through Foundation Models | Initial default in development build on eligible Macs; evaluate quality before release |
| Codex / OpenAI | Existing Codex login; optional direct OpenAI API connection is still planned | Keep the current subscription-backed workflow and add an explicit API option |
| Claude | Own separately billed Anthropic API key in development build; subscription integration remains exploratory | API-key access is implemented locally; investigate supported Claude Code subscription access separately |

Subscription access and API billing must be clearly distinguished. A subscription must not be described as including API credits. Use providers' supported sign-in flows and integrations; do not extract or repurpose session tokens. Keep API keys in macOS Keychain. Show whether a selected connection uses a subscription or separately billed API usage before a request starts.

## Provider selection

- **Settings:** save a preferred provider and connection, with model selection where supported. Existing Codex users retain their choice. On first setup, select Apple Intelligence when it is available and no other provider is configured.
- **Main window:** a compact provider picker beside Summarize lets someone override their default for this transcript. Changing it does not run a request or change the saved default.
- **Try another result:** retain the original source in memory so another provider can summarize the same transcript. Keep the previous result available in the current session for comparison, and identify which provider and model produced each result. This does not introduce a persistent transcript library.
- **Clipboard:** a comparison run should leave the current clipboard alone until the user chooses Copy summary for the result they want. Preserve the existing automatic copy for the first summary and its protection against overwriting newer clipboard content.
- **Availability:** show why a provider is unavailable and how to enable it. If a chosen provider fails or reaches a limit, offer available alternatives. Do not silently send the transcript to another service or switch to API billing.

## Apple Intelligence feasibility

The on-device option is a fallback for compatible, enabled Macs, not a universal fallback for every Mac supported by Note Ferry. Apple's Foundation Models framework starts with macOS 26 and requires an Apple Intelligence-compatible device with Apple Intelligence enabled. Check actual model availability, language support, and download readiness at runtime. Keep Codex and API options usable on older supported Macs. [Apple's framework requirements](https://www.apple.com/ca/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)

The prototype splits text into roughly 4,000-character portions, makes detailed notes in fresh sessions, and consolidates the takeaways in further sessions. It keeps all source portions and accepts up to 100 KB locally; the Codex path retains its 400 KB limit. Long call transcripts still need human evaluation for names, speaker attribution, decisions, commitments, and uncertainty before this can become a default. Do not silently truncate a transcript or imply parity with cloud models. [Apple's context-window guidance](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

## Claude subscription feasibility

Evaluate invoking the user's unmodified Claude Code installation with their own login. Anthropic currently describes subscription usage for `claude -p` and the Agent SDK, while its integration rules require provider-owned authentication and restrict third-party handling of subscription credentials. Recheck supported usage, applicable terms, and billing before implementation. Direct Anthropic API access remains a distinct integration option. [Subscription usage](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan), [integration and authentication rules](https://code.claude.com/docs/en/legal-and-compliance)

## Next validation steps

1. Evaluate Apple Intelligence summaries with short and long transcripts, checking attribution, action items, and missing detail before considering it release-ready.
2. Review Claude summaries against their source transcripts, and test key replacement, failure recovery, and the first-use confirmation in the built app.
3. Test the first-run chooser, Settings, and per-transcript picker on a clean install and on an existing Codex setup.
4. Add session-only result comparison and consider direct OpenAI API access separately.

All providers should use the same output structure and Apple Notes formatting. Retain explicit user-triggered processing, cancellation, clipboard protection, and the rule that the app never creates or edits notes.

## Later exploration

Call recording and closer calendar integration are future ambitions. They are outside the provider work above and need a separate design for capture, permissions, meeting context, and retention.

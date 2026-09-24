# Roadmap

[Back to Note Ferry](README.md) · [Development guide](docs/DEVELOPMENT.md)

Note Ferry uses Codex CLI for **Summarize & format** and has local **Format only**. Everything below is planned, with no promised release dates. Keep the core workflow simple: paste text, choose Format only or Summarize & format, and paste into Apple Notes.

## More ways to summarize

| Provider | Intended access | Direction |
| --- | --- | --- |
| Apple Intelligence | Apple's on-device model through Foundation Models | Default for eligible Macs when no other service is configured; no separate AI subscription or API key |
| Codex / OpenAI | Existing Codex login, plus an optional direct OpenAI API connection | Keep the current subscription-backed workflow and add an explicit API option |
| Claude | User's own Claude subscription through supported Claude Code integration where permitted, plus Anthropic API access | Prefer existing subscriptions when supported; provide API-key access as a separate choice |

Subscription access and API billing must be clearly distinguished. A subscription must not be described as including API credits. Use providers' supported sign-in flows and integrations; do not extract or repurpose session tokens. Keep API keys in macOS Keychain. Show whether a selected connection uses a subscription or separately billed API usage before a request starts.

## Provider selection

- **Settings:** save a preferred provider and connection, with model selection where supported. Existing Codex users retain their choice. On first setup, select Apple Intelligence when it is available and no other provider is configured.
- **Main window:** a compact provider picker beside Summarize lets someone override their default for this transcript. Changing it does not run a request or change the saved default.
- **Try another result:** retain the original source in memory so another provider can summarize the same transcript. Keep the previous result available in the current session for comparison, and identify which provider and model produced each result. This does not introduce a persistent transcript library.
- **Clipboard:** a comparison run should leave the current clipboard alone until the user chooses Copy summary for the result they want. Preserve the existing automatic copy for the first summary and its protection against overwriting newer clipboard content.
- **Availability:** show why a provider is unavailable and how to enable it. If a chosen provider fails or reaches a limit, offer available alternatives. Do not silently send the transcript to another service or switch to API billing.

## Apple Intelligence feasibility

The on-device option is a fallback for compatible, enabled Macs, not a universal fallback for every Mac supported by Note Ferry. Apple's Foundation Models framework starts with macOS 26 and requires an Apple Intelligence-compatible device with Apple Intelligence enabled. Check actual model availability, language support, and download readiness at runtime. Keep Codex and API options usable on older supported Macs. [Apple's framework requirements](https://www.apple.com/ca/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)

Long call transcripts need a dedicated evaluation. Apple's documented on-device context limit is small enough that full transcripts may require chunking and a consolidation pass. Measure preservation of names, speaker attribution, decisions, commitments, and uncertainty across chunks before shipping it as a default. Recheck limits against the SDK and model being targeted. Do not silently truncate a transcript or imply parity with cloud models. [Apple's context-window guidance](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

## Claude subscription feasibility

Evaluate invoking the user's unmodified Claude Code installation with their own login. Anthropic currently describes subscription usage for `claude -p` and the Agent SDK, while its integration rules require provider-owned authentication and restrict third-party handling of subscription credentials. Recheck supported usage, applicable terms, and billing before implementation. Direct Anthropic API access remains a distinct integration option. [Subscription usage](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan), [integration and authentication rules](https://code.claude.com/docs/en/legal-and-compliance)

## Implementation sequence

1. Separate provider execution from the shared summary schema, renderer, and clipboard handling. Make errors and progress provider-neutral.
2. Prototype Apple Intelligence with short and long synthetic transcripts, including attribution and action-item fidelity checks.
3. Add Claude and optional direct API connections, with explicit authentication and billing choices.
4. Add Settings and the per-transcript provider picker, then session-only result comparison.

All providers should use the same output structure and Apple Notes formatting. Retain explicit user-triggered processing, cancellation, clipboard protection, and the rule that the app never creates or edits notes.

## Later exploration

Call recording and closer calendar integration are future ambitions. They are outside the provider work above and need a separate design for capture, permissions, meeting context, and retention.

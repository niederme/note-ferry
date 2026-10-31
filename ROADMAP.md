# Roadmap

[Back to Note Ferry](README.md) · [Development guide](docs/DEVELOPMENT.md)

Version 2.0 adds optional context and adaptive clarification interviews to Apple Intelligence, Codex, and Claude API summarization, with a first-run chooser, a default in Settings, and a per-text provider picker. **Format only** stays local. Other plans have no promised release dates. Keep the core workflow simple: paste text, choose an action, and paste into Apple Notes.

## More ways to summarize

| Provider | Intended access | Direction |
| --- | --- | --- |
| Apple Intelligence | Apple's on-device model through Foundation Models | Initial default on new installs; continue evaluating quality, especially for long transcripts |
| Codex / OpenAI | Existing Codex login; optional direct OpenAI API connection is still planned | Keep the current subscription-backed workflow and add an explicit API option |
| Claude | Own separately billed Anthropic API key; subscription integration remains exploratory | API-key access is available; investigate supported Claude Code subscription access separately |

Subscription access and API billing must be clearly distinguished. A subscription must not be described as including API credits. Use providers' supported sign-in flows and integrations; do not extract or repurpose session tokens. Keep API keys in macOS Keychain. Show whether a selected connection uses a subscription or separately billed API usage before a request starts.

## Provider selection: shipped

- **Settings:** save a preferred provider. Saved provider choices are retained. New installs preselect Apple Intelligence and explain when it is unavailable. Codex supports an optional model ID in Settings; broader model selection can be considered later.
- **Main window:** a compact provider picker beside Summarize lets someone override their default for this transcript. Changing it does not run a request or change the saved default.

## Planned: compare results

- **Try another result:** retain the original source in memory so another provider can summarize the same transcript. Keep the previous result available in the current session for comparison, and identify which provider and model produced each result. This does not introduce a persistent transcript library.
- **Clipboard:** a comparison run should leave the current clipboard alone until the user chooses Copy summary for the result they want. Preserve the existing automatic copy for the first summary and its protection against overwriting newer clipboard content.
- **Availability:** show why a provider is unavailable and how to enable it. If a chosen provider fails or reaches a limit, offer available alternatives. Do not silently send the transcript to another service or switch to API billing.

## Apple Intelligence quality and availability

The on-device option works on compatible, enabled Macs, not every Mac supported by Note Ferry. Apple's Foundation Models framework starts with macOS 26 and requires an Apple Intelligence-compatible device with Apple Intelligence enabled. Check actual model availability, language support, and download readiness at runtime. Keep Codex and API options usable on older supported Macs. [Apple's framework requirements](https://www.apple.com/ca/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)

The on-device summarizer splits text into roughly 4,000-character portions, makes detailed notes in fresh sessions, and consolidates the takeaways in further sessions. It keeps all source portions and accepts up to 100 KB locally; the Codex path retains its 400 KB limit. Long call transcripts still need human evaluation for names, speaker attribution, decisions, commitments, and uncertainty before this default can be considered reliable for every transcript. Do not silently truncate a transcript or imply parity with cloud models. [Apple's context-window guidance](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

## Claude subscription feasibility

Investigate whether a supported third-party integration can invoke the user's Claude Code installation with their own login. Verify current authentication rules, permitted usage, and billing before implementation; do not assume a subscription grants API access. Direct Anthropic API access remains the shipped connection. Start with Anthropic's [integration and authentication rules](https://code.claude.com/docs/en/legal-and-compliance).

## Next validation steps

1. Continue evaluating the shipped Apple Intelligence option with short and long transcripts, checking attribution, action items, and missing detail.
2. Review Claude summaries against their source transcripts, and test key replacement, failure recovery, and the first-use confirmation in the built app.
3. Test the first-run chooser, Settings, and per-transcript picker on a clean install and on an existing Codex setup.
4. Add session-only result comparison and consider direct OpenAI API access separately.

All providers should use the same output structure and Apple Notes formatting. Retain explicit user-triggered processing, cancellation, clipboard protection, and the rule that the app never creates or edits notes.

## Clarification interview: shipped in 2.0

An optional interview now runs before the final summary. It is on by default, with **Ask clarifying questions before summarizing** in Settings. The model checks the source in the background as part of summarizing; an interview appears if the model returns questions. Users can skip those questions with **Finish & summarize**. The source may be a transcript, rough notes, or other text; clear material should need no questions.

Each round offers up to three material questions, exact source excerpts when useful, evidence-supported suggestions, and free text. Three is a batch size, not a total limit. Follow-ups use prior answers; users can correct the question’s premise, leave answers blank, or choose **Finish & summarize** at any time. Answers are separate from original source evidence, and missing answers never imply agreement. The app checks quoted excerpts against the original text.

Codex, Claude, and Apple Intelligence use the same interview flow. Token reporting includes interview requests when available, and Settings explains the extra time, tokens, and possible API cost. On-device context limits can end the interview earlier. Further evaluation should focus on question usefulness, repeated or leading questions, long-source coverage, and faithful use of corrections across providers as the feature evolves.

## Later exploration

Call recording and closer calendar integration are future ambitions. They are outside the provider work above and need a separate design for capture, permissions, meeting context, and retention.

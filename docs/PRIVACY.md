# Privacy and data handling

[Back to Summary Notes](../README.md)

**Summarization sends the transcript to OpenAI through Codex. It is not an on-device AI workflow.** Rich-text formatting happens locally.

**Format only**, available in the current source but not the 1.0 release, runs entirely on your Mac. It does not call Codex, load linked pages or images, or require an account. The Codex details below apply only to **Summarize & format**.

- The app holds the source, preview, and clipboard backup in memory. It has no saved transcript library.
- The transcript is passed over standard input, not in command-line arguments or a source file.
- The result is temporarily written into a randomly named directory accessible to the current user. The worker removes that directory when it exits normally. A forced exit, app termination before cleanup finishes, or power loss can leave a temporary result behind.
- Codex runs with `--ephemeral`, a read-only sandbox, approval prompts disabled, and user configuration ignored. The integration disables shell execution, app connectors, plugins, hooks, memory, browser, computer, image, and multi-agent features. It reuses saved authentication without copying credentials.
- Ephemeral mode disables normal session rollout persistence. It does not change OpenAI’s service-side data handling or guarantee that the CLI produces no operational metadata. See [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
- Clipboard managers and system clipboard services may retain or synchronize copied content according to their own settings.

Transcripts are treated as source material to summarize, not as instructions to execute. The app performs no web research or external fact checking.

Explicit command-line exports made with `--summarize-file` or `--format-file` persist until you delete them. See the [development guide](DEVELOPMENT.md#test-a-real-transcript-without-changing-the-clipboard).

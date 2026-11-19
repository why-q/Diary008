# Diary008 development plan

## Goal and current status

Diary008 is currently an Android-only Flutter prototype. The goal is to write on a phone or laptop, keep writing offline, and sync through storage the user chooses, including self-hosted options. Diary008 will not embed an AI provider. Users can opt in to bringing their own agents to work with diary entries and predictions.

The generic OpenHands profiles are merged. Product implementation has not started. No laptop platform, sync provider, or MCP release scope has been selected.

## M1 — Wrap the existing JSON repository (next)

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M1.1 | Add a file-independent `NotebookRepository` contract (`load` and `save`, with a way to request a non-migrating read). Implement `JsonNotebookRepository` using the existing `readNotebook` and `writeNotebook` helpers. | The contract depends on the `Notebook` domain model, not `File` or Flutter. Test the real adapter against temporary files: missing file, round trip, legacy migration, non-migrating read, and corrupt JSON. |
| M1.2 | After M1.1, route `lib/main.dart` notebook loads and writes through the repository, including backup restore and record destruction. Use the same repository boundary for the read-only notebook access in `lib/reminder_service.dart`. | Keep `notebook.json`, its schema, atomic replacement, diagnostics, error behavior, and save-before-UI-update ordering intact. Preserve backup compatibility and reminder barriers. Background refresh must not migrate or write the notebook. |
| M1.3 | Prepare test fixtures in a separate worktree once the contract is agreed; verify the integrated refactor independently. | Run the new adapter tests and the existing notebook storage, startup, backup, and reminder tests first. Then run `flutter analyze` and `flutter test`. Run Android integration tests only on a disposable device, following `AGENTS.md`; record any checks that could not run. |

Out of scope for M1: a schema migration beyond the existing one, new dependencies, application command refactoring, networking, sync settings, laptop UI, and MCP. The first meaningful commit should deliver M1.1 with focused verification where available.

## Roadmap after M1

1. **Application commands and queries.** Move diary mutations behind application services so the Android UI, a future laptop client, and future agent integrations can use the same domain rules. Keep `Notebook` independent of storage, transport, Flutter, and MCP.
2. **Offline change tracking.** Define versioned operations with stable identifiers, deduplicate replays, and persist the notebook update and its outgoing operation together. Keep existing JSON backup import/export compatible. Use deterministic conflict rules that never silently discard diary text; keep concurrent edits visible and define deletion behavior before enabling multi-device writes.
3. **Provider-neutral sync.** Start with an in-memory provider and test two-device convergence, retries, deduplication, and conflicts. Then select a real provider. WebDAV is a candidate, as are a self-hosted API and other storage adapters. Agree on authentication, encryption, and how the transport prevents lost updates before enabling sync with real diary data.
4. **Laptop writing.** Choose web or native desktop separately. Deliver opening, creating, and editing entries with offline local saves and synchronization with Android. Use an end-to-end acceptance check: edits made offline on both devices survive reconnection without silent data loss.
5. **Bring-your-own-agent access.** MCP is the integration protocol; skills are optional guidance for external agents. Put MCP above the application query/command layer, not directly over files. Start with opt-in, scoped read access for entry search, history, and prediction queries. Add draft creation only if approved and require user confirmation before a draft becomes a diary entry. No bundled AI provider.

## Development workflow

- The main agent owns planning and discussion, stays on its selected model, and reviews, integrates, and verifies delegated work.
- Use `.agents/agents/fast-worker.md`, `tester.md`, and `reviewer.md` for scoped implementation, testing, and review on `deepseek-v4.1-flash` with high reasoning effort. The optional `planner` profile uses `gpt-6.2-sol` with high reasoning effort; it does not replace the main agent's planning.
- Make code changes in a dedicated Git worktree; give independent testing its own worktree. Start from the current `main` and check that worktrees contain no unmerged commits or unique changes before removing them.
- Keep tasks and acceptance criteria in this file; append worktree, delegation, test, and commit events to [`PROCESS.jsonl`](PROCESS.jsonl). Aim for a meaningful commit within 15 minutes of starting implementation. Run focused tests early and broader checks before finishing.

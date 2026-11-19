# Diary008 development plan

See [AGENTS.md](AGENTS.md#development-workflow) for the standing development workflow.

## Goal and current status

Diary008 is currently an Android-only Flutter prototype. The goal is to write on a phone or laptop, keep writing offline, and sync through storage the user chooses, including self-hosted options. Diary008 will not embed an AI provider. Users can opt in to bringing their own agents to work with diary entries and predictions.

The `fast-worker` and `smart-worker` profiles are defined. M1 is complete. The next milestone is application commands and queries. No laptop platform, sync provider, or MCP release scope has been selected.

## M1 — Wrap the existing JSON repository (complete)

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M1.1 | Add a file-independent `NotebookRepository` contract (`load` and `save`, with a way to request a non-migrating read). Implement `JsonNotebookRepository` using the existing `readNotebook` and `writeNotebook` helpers. | The contract depends on the `Notebook` domain model, not `File` or Flutter. Test the real adapter against temporary files: missing file, round trip, legacy migration, non-migrating read, and corrupt JSON. |
| M1.2 | After M1.1, route `lib/main.dart` notebook loads and writes through the repository, including backup restore and record destruction. Use the same repository boundary for the read-only notebook access in `lib/reminder_service.dart`. | Keep `notebook.json`, its schema, atomic replacement, diagnostics, error behavior, and save-before-UI-update ordering intact. Preserve backup compatibility and reminder barriers. Background refresh must not migrate or write the notebook. |
| M1.3 | After M1.1 and M1.2 are committed, assign a fresh worker to verify the integrated refactor independently in its own worktree. | Target the adapter and affected storage, startup, backup, and reminder tests. For the integrated milestone, run `flutter analyze` and the full `flutter test` suite; record any checks that could not run. |

Out of scope for M1: a schema migration beyond the existing one, new dependencies, application command refactoring, networking, sync settings, laptop UI, and MCP. The first meaningful commit should deliver M1.1 with focused verification where available.

## Roadmap after M1

1. **Application commands and queries.** Move diary mutations behind application services so the Android UI, a future laptop client, and future agent integrations can use the same domain rules. Keep `Notebook` independent of storage, transport, Flutter, and MCP.
2. **Offline change tracking.** Define versioned operations with stable identifiers, deduplicate replays, and persist the notebook update and its outgoing operation together. Keep existing JSON backup import/export compatible. Use deterministic conflict rules that never silently discard diary text; keep concurrent edits visible and define deletion behavior before enabling multi-device writes.
3. **Provider-neutral sync.** Start with an in-memory provider and test two-device convergence, retries, deduplication, and conflicts. Then select a real provider. WebDAV is a candidate, as are a self-hosted API and other storage adapters. Agree on authentication, encryption, and how the transport prevents lost updates before enabling sync with real diary data.
4. **Laptop writing.** Choose web or native desktop separately. Deliver opening, creating, and editing entries with offline local saves and synchronization with Android. Use an end-to-end acceptance check: edits made offline on both devices survive reconnection without silent data loss.
5. **Bring-your-own-agent access.** MCP is the integration protocol; skills are optional guidance for external agents. Put MCP above the application query/command layer, not directly over files. Start with opt-in, scoped read access for entry search, history, and prediction queries. Add draft creation only if approved and require user confirmation before a draft becomes a diary entry. No bundled AI provider.

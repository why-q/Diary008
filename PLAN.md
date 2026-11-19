# Diary008 development plan

See [AGENTS.md](AGENTS.md#development-workflow) for the standing development workflow.

## Goal and current status

Diary008 is currently an Android-only Flutter prototype. The goal is to write on a phone or laptop, keep writing offline, and sync through storage the user chooses, including self-hosted options. Diary008 will not embed an AI provider. Users can opt in to bringing their own agents to work with diary entries and predictions.

The `fast-worker` and `smart-worker` profiles are defined. M1 is complete. M2 is complete and integrated on `main` at `abebef4`. M3.1 is implemented on `m3-journal-foundation`. No laptop platform, sync provider, or MCP release scope has been selected.

## M1 — Wrap the existing JSON repository (complete)

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M1.1 | Add a file-independent `NotebookRepository` contract (`load` and `save`, with a way to request a non-migrating read). Implement `JsonNotebookRepository` using the existing `readNotebook` and `writeNotebook` helpers. | The contract depends on the `Notebook` domain model, not `File` or Flutter. Test the real adapter against temporary files: missing file, round trip, legacy migration, non-migrating read, and corrupt JSON. |
| M1.2 | After M1.1, route `lib/main.dart` notebook loads and writes through the repository, including backup restore and record destruction. Use the same repository boundary for the read-only notebook access in `lib/reminder_service.dart`. | Keep `notebook.json`, its schema, atomic replacement, diagnostics, error behavior, and save-before-UI-update ordering intact. Preserve backup compatibility and reminder barriers. Background refresh must not migrate or write the notebook. |
| M1.3 | After M1.1 and M1.2 are committed, assign a fresh worker to verify the integrated refactor independently in its own worktree. | Target the adapter and affected storage, startup, backup, and reminder tests. For the integrated milestone, run `flutter analyze` and the full `flutter test` suite; record any checks that could not run. |

Out of scope for M1: a schema migration beyond the existing one, new dependencies, application command refactoring, networking, sync settings, laptop UI, and MCP. The first meaningful commit should deliver M1.1 with focused verification where available.

## M2 — Application commands and queries

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M2.1 | Add `NotebookApplication` commands for add, revise, fulfill, expiration reconciliation, sort, volume rename and creation, and archived-volume deletion, plus `NotebookQueries` for filtered current and archived entries. Both depend only on `Notebook` and `NotebookRepository`. | Commands delegate validation, expiry, archive scope, and ordering to `Notebook`, persist only accepted changes, and report applied, unchanged, rejected, or save-failed. Queries reuse the domain filter and sort rules. Test success, rejection, save failure, no-op paths, explicit time, sorting and filtering, and archive scope against real files. |
| M2.2 | Route `lib/main.dart` notebook mutations and reads through the application boundary while keeping navigation, localized notices, filters, selection, reminder barriers, startup and storage ordering, snapshots, and busy semantics unchanged. | Existing domain, storage, startup, settings, reminder, and volume tests keep passing. Presentation still writes through `notebook.json` before updating the UI. |

Out of scope for M2: schema or dependency changes, sync, offline change tracking, a new UI, and MCP.

### M2 completion record

- Candidate integrated on `main`: `abebef48f3fa2bc19c34e70b9075d41ce8c10fbe`, based on `e20d46e08525e4ab74e44ad158ce573ccbc0fd58`.
- Implementer: DeepSeek (`deepseek-v4.1-flash`) conversation `fd02ee9712154dcc8898e1cf8abde90d`. Independent reviewer: conversation `1a212387bcca4b3aad33dd049b23f2d2`.
- Verification: 59 focused tests and 120 full-suite tests passed; `flutter analyze` reported only the 36 pre-existing infos and no new diagnostics. No Android device test was run because no disposable device was available.
- Both M2 commits were pushed together; no separate M2 pull request was opened.

### M1 and M2 platform notes

- The M1 APK workflow run `44520936650` passed on attempt 2 without any code changes.
- M2 Android device tests were not run.

## M3 — Offline change tracking

M3 stays offline and in-process. It adds no provider, no sync transport, and no production hookup.

### M3.1 — Versioned entry journal foundation (implemented on `m3-journal-foundation`)

Delivered as an isolated, pure-Dart module under `lib/journal/`, with no imports of `dart:io`, Flutter, or the existing notebook/storage code, and no production call sites.

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M3.1.1 | Define versioned immutable operations for entry creation and revision. A create operation carries an explicit UTC instant plus the civil date the entry belongs to; a revision carries an explicit UTC instant only. Identity is an opaque `notebookId`, `epochId`, `actorId`, per-actor `sequence`, `operationId`, and `entryId`. | Identifiers reject diary text, numeric-only values such as volume ordinals, and wall-clock strings. Payloads are validated on construction and on decode: exact key sets, unsupported `schemaVersion`, unknown `kind`, non-UTC instants, invalid civil dates, empty text, and oversized text are all rejected. JSON round trips preserve Unicode. |
| M3.1.2 | Add a journal admission API. | An exact replay is idempotent and does not append. A reused `operationId` or `actorId`+`sequence` with divergent content is an explicit collision that leaves the accepted operation untouched. A second create for the same `entryId` is a collision, not a clobber. Writes for another notebook or epoch are rejected. All distinct text-bearing operations are retained; nothing is merged. |
| M3.1.3 | Encode and decode the whole journal document. | A stored journal rejects an unsupported version, malformed entries, and duplicate operations instead of silently repairing or merging them. |
| M3.1.4 | Record the M3.1 checkpoint. | One focused test file covers round trips including Unicode, clock and time-zone independence, replay/dedup, both collision shapes, malformed and unsupported data, and notebook/epoch isolation. |

Explicit non-goals for M3.1, all still unshipped:

- No notebook+journal atomic write, no replay of a journal onto a notebook, and no conflict-resolution UI or policy beyond refusal.
- No volume deletion or restore rules. Those need their own specification before they can be committed.
- No notebook or entry lineage inferred from content similarity or text equality; lineage is only the explicit `notebookId`/`epochId`/`entryId` carried by each operation.
- No migration of `notebook.json`, no backup format change, no UI change, no dependency addition, and no scanning of real diary records.

### Next checkpoints after M3.1

1. **Atomic notebook and journal.** Persist a notebook change and its outgoing operation in one durable step, with a crash-safe ordering and a recovery read. Acceptance: an interrupted write leaves either both or neither, verified against temporary files.
2. **Pure replay and conflicts.** Apply an accepted journal to a `Notebook` in a pure function, producing a deterministic state plus an explicit list of unresolved conflicts. Acceptance: identical inputs give identical output, concurrent text stays visible, and no text is dropped.
3. **Backup, restore, and wipe barriers.** Define how an existing backup file, a restore, and an entry-destruction action interact with a pending journal. Acceptance: no barrier silently discards unshipped operations or resurrects deleted text.
4. **M4 in-memory only.** Build a provider-neutral in-memory sync provider and test two-device convergence, retries, deduplication, and conflicts. In-memory only; no real provider, credentials, or real diary data.

None of the remaining M3 or M4 work has shipped.

## Roadmap after M1

1. **Application commands and queries.** Move diary mutations behind application services so the Android UI, a future laptop client, and future agent integrations can use the same domain rules. Keep `Notebook` independent of storage, transport, Flutter, and MCP.
2. **Offline change tracking.** Define versioned operations with stable identifiers, deduplicate replays, and persist the notebook update and its outgoing operation together. Keep existing JSON backup import/export compatible. Use deterministic conflict rules that never silently discard diary text; keep concurrent edits visible and define deletion behavior before enabling multi-device writes.
3. **Provider-neutral sync.** Start with an in-memory provider and test two-device convergence, retries, deduplication, and conflicts. Then select a real provider. WebDAV is a candidate, as are a self-hosted API and other storage adapters. Agree on authentication, encryption, and how the transport prevents lost updates before enabling sync with real diary data.
4. **Laptop writing.** Choose web or native desktop separately. Deliver opening, creating, and editing entries with offline local saves and synchronization with Android. Use an end-to-end acceptance check: edits made offline on both devices survive reconnection without silent data loss.
5. **Bring-your-own-agent access.** MCP is the integration protocol; skills are optional guidance for external agents. Put MCP above the application query/command layer, not directly over files. Start with opt-in, scoped read access for entry search, history, and prediction queries. Add draft creation only if approved and require user confirmation before a draft becomes a diary entry. No bundled AI provider.

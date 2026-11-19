# Diary008 development plan

See [AGENTS.md](AGENTS.md#development-workflow) for the standing development workflow.

## Goal and current status

Diary008 is currently an Android-only Flutter prototype. The goal is to write on a phone or laptop, keep writing offline, and sync through storage the user chooses, including self-hosted options. Diary008 will not embed an AI provider. Users can opt in to bringing their own agents to work with diary entries and predictions.

The `fast-worker` and `smart-worker` profiles are defined. M1 is complete. M2 is complete and integrated on `main` at `abebef4`. M3.1 is complete on `main` at `28e79a945826f5d2d0aec7b1b317a94a2e985791`. M3.2 is implemented on `m3-atomic-storage`. No laptop platform, sync provider, or MCP release scope has been selected.

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

### M3.1 — Versioned entry journal foundation (complete on `main`)

Delivered as an isolated, pure-Dart module under `lib/journal/`, with no imports of `dart:io`, Flutter, or the existing notebook/storage code, and no production call sites.

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M3.1.1 | Define versioned immutable operations for entry creation and revision. A create operation carries an explicit UTC instant plus the civil date the entry belongs to; a revision carries an explicit UTC instant only. Identity is an opaque `notebookId`, `epochId`, `actorId`, per-actor `sequence`, `operationId`, and `entryId`. | Identifiers reject diary text, numeric-only values such as volume ordinals, and wall-clock strings. Payloads are validated on construction and on decode: exact key sets, unsupported `schemaVersion`, unknown `kind`, non-UTC instants, invalid civil dates, empty text, and oversized text are all rejected. JSON round trips preserve Unicode. |
| M3.1.2 | Add a journal admission API. | An exact replay is idempotent and does not append. A reused `operationId` or `actorId`+`sequence` with divergent content is an explicit collision that leaves the accepted operation untouched. A second create for the same `entryId` is a collision, not a clobber. Writes for another notebook or epoch are rejected. All distinct text-bearing operations are retained; nothing is merged. |
| M3.1.3 | Encode and decode the whole journal document. | A stored journal rejects an unsupported version, malformed entries, and duplicate operations instead of silently repairing or merging them. |
| M3.1.4 | Record the M3.1 checkpoint. | One focused test file covers round trips including Unicode, clock and time-zone independence, replay/dedup, both collision shapes, malformed and unsupported data, and notebook/epoch isolation. |

#### M3.1 completion record

- Final tip on `main`: `28e79a945826f5d2d0aec7b1b317a94a2e985791`. All three M3.1 commits were pushed to `main`; no pull request was opened for them.
- Independent reviewer conversation `f302d0cd2c8a4129b3daf77d93d5243c` reported no blockers.
- Verification on Flutter 3.47.7 (Dart 3.13.5): 27 focused journal tests and 147 full-suite tests passed, the targeted analyzer run was clean, and a JavaScript compile and run check was verified.
- M2 Android platform note: APK workflow run `44526762707` succeeded.
- M3.1 stayed a pure-Dart protocol with no production call sites.

Explicit non-goals for M3.1, all still unshipped:

- No notebook+journal atomic write, no replay of a journal onto a notebook, and no conflict-resolution UI or policy beyond refusal.
- No volume deletion or restore rules. Those need their own specification before they can be committed.
- No notebook or entry lineage inferred from content similarity or text equality; lineage is only the explicit `notebookId`/`epochId`/`entryId` carried by each operation.
- No migration of `notebook.json`, no backup format change, no UI change, no dependency addition, and no scanning of real diary records.

### M3.2 — Atomic notebook and journal storage (implemented on `m3-atomic-storage`)

An experimental, explicitly instantiated file adapter under `lib/journal/`. It is not imported by `lib/main.dart` or any other production code, and it touches no existing app file.

| Task | Work | Acceptance and focused verification |
| --- | --- | --- |
| M3.2.1 | Add a versioned envelope document that carries one notebook snapshot and one journal, plus an explicit `JournalScope` (`notebookId`, `epochId`) and a monotonic `revision`. | Decode rejects unknown keys, an unsupported envelope or notebook schema version, a missing or wrong format discriminator, a non-canonical snapshot, a duplicate operation, and a journal outside the requested scope. It never migrates and never repairs. Errors name fields only, never diary text. |
| M3.2.2 | Add `AtomicNotebookStore`: one instance owns one file, and a commit writes the whole envelope to a unique same-directory temporary file, validates those exact bytes, then renames over the target. Commits are serialized on a normalized target path, and `notebook.json` is refused as a target. | A commit is refused as `stale` unless the caller's base revision and base content both match the stored envelope; it is refused as `conflict`, `duplicate`, `noChange`, `inconsistent`, or `scopeMismatch` when the journal already holds the operation or the snapshot contradicts it. Only `committed` claims a durable change, and it increments the revision by exactly one. Two instances on one path never both report `committed`. |
| M3.2.3 | Record the M3.2 checkpoint. | One focused test file covers reload, Unicode, scope, malformed and unsupported envelopes, disruption immediately before replacement (the prior notebook and journal remain together and the interrupted commit can be retried), replay/idempotence, stale-write protection, serialized overlapping commits across two instances, malformed UTF-8 and malformed keys that never echo stored content, refusal of a `notebook.json` target, and that `notebook.json` is untouched. |

Ownership contract and limits, stated in the code and tested:

- One writer at a time per target, inside one isolate. Commits are serialized on a lexically normalized absolute path, so two `AtomicNotebookStore` instances in the same isolate that name the same file cannot interleave a read-check-write, and only one of them can report `committed`. The other observes the new revision and returns `stale`.
- Not coordinated, and not claimed: a second isolate, a second process, and path aliases that a lexical normalization cannot see (symlinks, hard links, case-insensitive file systems, bind mounts). Those writers can still lose updates. No lock file is created.
- Durability is `writeAsBytes(flush: true)` plus a same-directory `rename`. That ordering survives a process crash. It is not a tested power-loss guarantee, the directory is not fsynced, and a sudden power loss can leave a rename undurable after `committed` was reported.
- Each attempt writes a unique temporary file beside the target, so a stale temp file from a crashed writer is never reused and two writers never share one temporary file.
- `notebook.json` is refused as a target at construction, before any write, temp file, or rename. The envelope keeps its own file name and `notebook.json` keeps its own format and writer.

What a commit actually checks, and what it does not:

- Checked: the caller's base revision equals the stored revision; the caller's base content equals the stored content byte for byte after canonical encoding; the operation is admitted to the stored journal; the offered snapshot differs from the stored snapshot; the exact bytes about to be renamed decode back to the intended envelope; the scope matches.
- Not checked: that the offered snapshot actually reflects the operation. `Notebook` carries no notebook, epoch, or entry identity, so a commit of an operation for an absent entry succeeds today, and that test pins the gap. This is not a snapshot-versus-operation consistency check; it is only a "snapshot changed" check.
- Production hookup therefore requires projection-backed validation: replay must produce the snapshot from the journal and compare it, so the correspondence is derived rather than asserted by the caller.

How storage and format errors surface:

- `read()` throws. A malformed, non-UTF-8, unsupported, or non-canonical stored document throws `EnvelopeFormatException`; a valid document from another scope throws `EnvelopeScopeMismatch`. Both name fields only and never echo stored bytes, paths, or diary text.
- `commit()` returns instead of throwing. A stored document that cannot be read yields `failed` with a short static reason; a stored document from another scope yields `scopeMismatch`. A failure while writing, validating, or renaming yields `failed`. Only `committed` claims a durable change, and the stored bytes are left untouched in every other case.

Explicit non-goals for M3.2, all still unshipped:

- No replay or projection of a journal onto a notebook, and no conflict-resolution policy beyond refusal.
- No hookup to `notebook.json`, the reminder service, backups, restore, wipe, or the UI; no schema migration and no dependency change.
- No cross-process or cross-isolate coordination, no power-loss guarantee, and no use of real diary data.

### Next checkpoints after M3.2

1. **Pure replay and conflicts.** Apply an accepted journal to a `Notebook` in a pure function, producing a deterministic state plus an explicit list of unresolved conflicts. Acceptance: identical inputs give identical output, concurrent text stays visible, and no text is dropped.
2. **Backup, restore, and wipe barriers.** Define how an existing backup file, a restore, and an entry-destruction action interact with a pending journal. Acceptance: no barrier silently discards unshipped operations or resurrects deleted text.
3. **M4 in-memory only.** Build a provider-neutral in-memory sync provider and test two-device convergence, retries, deduplication, and conflicts. In-memory only; no real provider, credentials, or real diary data.

Remaining prerequisites before any production hookup:

- Replay must define and check the snapshot/operation correspondence the store cannot verify. Hookup needs projection-backed validation: replay derives the snapshot from the journal and the store compares it, instead of trusting the caller.
- A single-writer contract must be extended to cover a second isolate and a second process, and to detect path aliases a lexical normalization cannot see, before the envelope file is shared with the app.
- Backup, restore, and entry destruction need their own barriers so a pending journal is neither discarded nor used to resurrect deleted text.

#### M3.2 corrective follow-up

Applied on branch `m3-atomic-hardening`, based on candidate `9c0e968734dce22c19d15d12f7a0307bc13303e1`.

- Regression tests first, then minimal fixes: malformed JSON keys no longer repeat the offending key in a `JournalFormatException` or `EnvelopeFormatException` message or field; malformed UTF-8 fails closed with no payload; a `notebook.json` target is refused at construction before any write; commits from two instances on one path are serialized and never both report `committed`.
- Fixes: unknown-key errors name only the known parent field; an unsupported operation kind no longer echoes the stored value; `read()` decodes UTF-8 explicitly and throws a content-free `EnvelopeFormatException`; `commit()` converts an unreadable stored document into `failed` instead of throwing; commits share a per-path chain keyed by a lexically normalized absolute path; each attempt uses a unique temporary file name so writers never share one temp file.
- Unchanged: the single experimental envelope, same-directory flushed atomic replace, `notebook.json` path, schema, and backup format, production APIs, and dependencies. No diary data is used.
- This follow-up corrects claims, not scope. The store still checks only that the snapshot changed, not that it reflects the operation; production hookup still needs replay-backed projection.

None of the remaining M3 or M4 work has shipped.

## Roadmap after M1

1. **Application commands and queries.** Move diary mutations behind application services so the Android UI, a future laptop client, and future agent integrations can use the same domain rules. Keep `Notebook` independent of storage, transport, Flutter, and MCP.
2. **Offline change tracking.** Define versioned operations with stable identifiers, deduplicate replays, and persist the notebook update and its outgoing operation together. Keep existing JSON backup import/export compatible. Use deterministic conflict rules that never silently discard diary text; keep concurrent edits visible and define deletion behavior before enabling multi-device writes.
3. **Provider-neutral sync.** Start with an in-memory provider and test two-device convergence, retries, deduplication, and conflicts. Then select a real provider. WebDAV is a candidate, as are a self-hosted API and other storage adapters. Agree on authentication, encryption, and how the transport prevents lost updates before enabling sync with real diary data.
4. **Laptop writing.** Choose web or native desktop separately. Deliver opening, creating, and editing entries with offline local saves and synchronization with Android. Use an end-to-end acceptance check: edits made offline on both devices survive reconnection without silent data loss.
5. **Bring-your-own-agent access.** MCP is the integration protocol; skills are optional guidance for external agents. Put MCP above the application query/command layer, not directly over files. Start with opt-in, scoped read access for entry search, history, and prediction queries. Add draft creation only if approved and require user confirmation before a draft becomes a diary entry. No bundled AI provider.

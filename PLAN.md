# Diary008 development plan

See [AGENTS.md](AGENTS.md#development-workflow) for the standing development workflow.

## Goal and current status

Diary008 is currently an Android-only Flutter prototype. The goal is to write on a phone or laptop, keep writing offline, and sync through storage the user chooses, including self-hosted options. Diary008 will not embed an AI provider. Users can opt in to bringing their own agents to work with diary entries and predictions.

The `fast-worker` and `smart-worker` profiles are defined. M1 is complete. M2 is complete and integrated on `main` at `abebef4`. M3.1 is complete on `main` at `28e79a945826f5d2d0aec7b1b317a94a2e985791`. M3.2, M3.3, and M3.4 are delivered on `main` through `f91fafd77c459905a350e556fa1e6db8bf13b7e4`. The non-blocking review findings against that M3 work are integrated on `main` in `bf882a3` (branch `storage-integrated`, based on published main `0918ea9`). M4 is in-memory only and is delivered on `main` through `0918ea931ef32394b9a44520f9ca90e0e2d6d650`. No laptop platform, sync provider, or MCP release scope has been selected, and no journal or sync module is wired into production.

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

### M3.2 — Atomic notebook and journal storage (delivered on `main`)

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

#### M3.2 corrective follow-up (delivered on `main`)

Applied on branch `m3-atomic-hardening`, based on candidate `9c0e968734dce22c19d15d12f7a0307bc13303e1`, and integrated as `6e8311a` with its record `6086669`.

- Regression tests first, then minimal fixes: malformed JSON keys no longer repeat the offending key in a `JournalFormatException` or `EnvelopeFormatException` message or field; malformed UTF-8 fails closed with no payload; a `notebook.json` target is refused at construction before any write; commits from two instances on one path are serialized and never both report `committed`.
- Fixes: unknown-key errors name only the known parent field; an unsupported operation kind no longer echoes the stored value; `read()` decodes UTF-8 explicitly and throws a content-free `EnvelopeFormatException`; `commit()` converts an unreadable stored document into `failed` instead of throwing; commits share a per-path chain keyed by a lexically normalized absolute path; each attempt uses a unique temporary file name so writers never share one temp file.
- Unchanged: the single experimental envelope, same-directory flushed atomic replace, `notebook.json` path, schema, and backup format, production APIs, and dependencies. No diary data is used.
- This follow-up corrected claims, not scope. The store still checks only that the snapshot changed, not that it reflects the operation; production hookup still needs replay-backed projection.

### M3.3 — Pure deterministic replay (delivered on `main`)

Delivered in `lib/journal/journal_replay.dart` and `lib/journal/journal_snapshot_equivalence.dart`, with `test/journal/journal_replay_test.dart`. Pure Dart: no `dart:io`, no clock, no I/O, and no production call sites.

- `JournalReplay.project` applies an accepted journal to a base `Notebook` and returns a deterministic projection, the operations it applied, and an explicit list of unresolved conflicts. Identical inputs always give an identical notebook.
- Canonical order is `recordedAt`, then `actorId`, then `sequence`, then `operationId`. Order decides display order and supplement placement only. It never decides whose text survives, because every accepted operation is kept.
- A create becomes a due-less explanation entry in the current volume with the exact `entryId`, verbatim text, `createdAt` equal to the recorded instant, and `createdOn` from the operation's explicit civil date.
- A revision mirrors `Notebook.revise` as a supplement, not a replacement: the base entry is marked `revised` and a due-less explanation supplement follows it.
- `isSnapshotEquivalentToProjection` fails closed: a projection with any conflict is never equivalent, so a snapshot cannot be shown to match a conflicted journal.

Conflict kinds, each keeping the original operation so no payload is lost:

- `entryIdCollision` — a create reuses an id present in the current volume, an archived volume, or an earlier projected entry.
- `missingTarget`, `archivedTarget`, `ambiguousTarget` — a revision's target is absent, archived, or duplicated.
- `ineligibleTarget`, `dueLessTarget` — a revision's base target is not pending, or is pending without a due date, so the supplement shape cannot be mirrored.
- `createThenRevise` — a revision targets an entry created by the same journal. A v1 revision carries no due date, so eligibility cannot be established without inventing data.
- `generatedIdCollision` — a projected supplement id would overwrite an existing id.
- `competingActors` — two or more actors revised the same base entry. All revisions stay visible and no last-writer winner is chosen.

Version 1 limits, stated in the code and pinned by tests:

- A v1 revision carries no civil date. The projection uses the UTC calendar date of the recorded instant and documents that the recording device's local calendar cannot be reconstructed. It does not guess.
- A v1 revision carries no due date, so a create followed by a revision is a conflict rather than a guess, and a due-less pending target is a conflict rather than a synthesized deadline.
- Replay reads no clock. Wall-clock expiry guards in `Notebook` are out of scope, so replay decides eligibility from structure only and leaves time-based decisions to a caller that supplies an explicit now.
- Identity is exact. No operation is matched to an entry by text, creation time, or volume position.
- `competingActors` is reported after the revisions were applied. It flags the divergence for a caller; it does not remove either revision.

### M3.4 — Backup, restore, and wipe barriers (delivered on `main`)

Delivered in `lib/journal/journal_barrier.dart` with `test/journal/journal_barrier_test.dart`. It decides only whether an action may proceed; it never reads or writes storage, inspects entry text, or mutates the journal.

- `planJournalBarrier` evaluates `export`, `restore`, and `wipe` in a fixed order: notebook identifier validity, notebook scope, pending operations, then fresh-epoch validation. Identical inputs give an identical decision.
- Version 1 has no acknowledgement or tombstone protocol, so every retained operation counts as pending. Export, restore, and wipe are all blocked while any operation remains. Export is blocked because the existing backup format omits the journal and would silently drop pending operations.
- Restore or wipe of an empty journal requires an explicit fresh epoch for the same notebook and returns an empty `JournalBarrierPlan` under that epoch. The plan is a value, not a write: it persists nothing and registers nothing.
- Decisions and diagnostics carry no diary text. `JournalBarrierDecision` has a private constructor, so an inconsistent decision cannot be built in a release build where an `assert` would be removed; the returned public type and its value semantics are unchanged.
- Epoch uniqueness is a caller responsibility, not a helper policy. The helper can only compare a fresh epoch with the epoch of the journal it was given. It cannot know whether an epoch was issued years earlier, and no durable epoch registry exists, so it does not implement historical uniqueness and must not be read as doing so. A future caller needs that durable registry before relying on the plan for correctness.
- A future caller that adopts this policy would, in one durable step, write the restored or emptied notebook data together with the fresh epoch, then release the existing reminder barrier (`ReminderService.beginDestruction` and `endDestruction`) so reminders are recalculated against the new scope.

### M3 delivery record

| Milestone | Candidate on `main` | Implementation commits | Independent review |
| --- | --- | --- | --- |
| M3.2 atomic envelope storage | `6086669b4eae0ea75386bba853d8a4b5741f3b48` | `9c0e968` (2026-11-19 13:18:41 +0000), `6e8311a` (author 2026-11-19 13:43:57 +0000, committer 13:45:56 +0000), `6086669` (2026-11-19 13:47:27 +0000) | conversation `cb9c7b234d4b4f1f88c669127eda125b` |
| M3.3 deterministic replay | `44dca15a4309195df6df43505293c40f991ac341` | `4ef0d43` (2026-11-19 13:48:52 +0000), `f1dec46` (13:54:19), `5c1dae3` (13:55:12), integrated by merge `44dca15` (2026-11-20 06:59:17 +0000) | conversation `cb9c7b234d4b4f1f88c669127eda125b` |
| M3.4 barriers | `f91fafd77c459905a350e556fa1e6db8bf13b7e4` | `e9ffb23` (2026-11-19 13:42:34 +0000), integrated by merge `f91fafd` (2026-11-20 06:59:18 +0000) | conversation `cb9c7b234d4b4f1f88c669127eda125b` |

- Original implementers: hardening `d4342f6274a6403fa04375593599fb03`, replay `e252dc12d57a4f3398da360c3f67e19b`, barriers `583df1e11c7d44c9904e667075305532`.
- Commit timestamps above come from `git show`, not from `PROCESS.jsonl`. The M3.2 entries previously appended to `PROCESS.jsonl` carry wall-clock times that do not match Git order: `9c0e968` was authored at 13:18:41, but its checkpoint was logged at 13:32:00, while the barrier checkpoint `e9ffb23` is authored at 13:42:34 and was not logged as an M3 entry at all. Git metadata is authoritative; the earlier log times are left as they were rather than rewritten.
- The independent DeepSeek reviewer `cb9c7b234d4b4f1f88c669127eda125b` measured, on the exact corresponding merge trees: 68 focused and 188 full tests at the M3.2 candidate `6086669`; 101 focused and 221 full at the M3.3 merge `44dca15`; 124 focused and 244 full at the M3.4 merge `f91fafd`. All runs were clean for `flutter analyze` and `dart format`. Those counts were reproduced on `f91fafd` before this follow-up changed anything.
- The reviewer reported no blockers and three non-blocking correctness issues, which are fixed by branch `m3-follow-up` and integrated on `main` in `bf882a3`:

| Finding | Fix | Regression test |
| --- | --- | --- |
| An invalid proposed snapshot rejected the commit future with `EnvelopeFormatException` instead of returning `failed`. | `commit()` builds the replacement envelope first and converts only `EnvelopeFormatException` into `EnvelopeCommitStatus.failed`. Any other error keeps propagating. The stored bytes are unchanged and the store stays readable. | `invalid proposed snapshot` group: typed failure with unchanged bytes and a usable store, a later commit still succeeding, and an unrelated `StateError` still propagating. |
| Only the exact lowercase `notebook.json` was refused as a target, so an ASCII-case variant could be accepted on a case-sensitive host. | The reserved-name check folds ASCII case for the final path segment, so the refusal is the same on every platform. Names that merely contain the reserved name stay usable. | `ASCII case variants of notebook.json are refused everywhere`, `names that merely contain the reserved name stay usable`. |
| `JournalBarrierDecision` could be hand-constructed into an inconsistent value in a release build, because its only guard was an `assert`. | The constructor is private, so only `planJournalBarrier` can create a decision. The returned public type and value semantics are unchanged. | `decision invariants` sweeps every action, notebook, and fresh epoch and checks that a plan is present exactly for an allowed restore or wipe, and pins the private constructor and the value-based equality. |

#### M3 follow-up integration on published main

Integrated on branch `storage-integrated`, based on published main `0918ea931ef32394b9a44520f9ca90e0e2d6d650`. Only the M3 storage follow-up was carried over: the code tree of `09ad4f4` applied onto current main, which already contains M3.3, M3.4, and M4. No production file, no backup format, no dependency, no provider, and no UI is touched, and no real diary data is used.

- Integrated unchanged: the typed `failed` result for a refused snapshot, the ASCII-case `notebook.json` refusal, and the private decision constructor.
- Corrected during integration, without changing any result semantics: the follow-up left a duplicated `_sameNotebook` inconsistency check unreachable after the replacement envelope was built, which is removed so the check keeps its single original position, status, and reason string.
- Corrected during integration: the narrowed catches stranded the temporary file when a non-storage error was thrown after the write, for example by a `beforeReplace` hook. Cleanup now runs on every failure path, still ignores its own errors so it cannot mask a typed result or the original exception, and the temporary file is deleted before the error propagates. `committed`, `failed`, `inconsistent`, `noChange`, `duplicate`, and the `stale`/`conflict`/`scopeMismatch` paths, their reason strings, the parity of stored bytes, and the per-path lock release are unchanged.
- Test gaps closed: the earlier unrelated-error test threw while building its snapshot, before the narrow `on EnvelopeFormatException` catch could be reached, so it never validated that catch. Two mutation checks confirm the new tests fail if either catch widens and fail if the temp cleanup is removed again. A live-target ASCII-case refusal case and a hook-failure case that also proves the path lock recovers complete the set.
- Verification on Flutter 3.47.7 (Dart 3.13.5) in an isolated worktree: 135 focused journal tests and 310 full-suite tests passed against 124 and 299 measured on published main `0918ea9`, `flutter analyze` reported no issues, `dart format` is clean for every changed file, and both new store paths were mutation-checked. No Android device test was run, because no disposable device is available in this sandbox; the Android APK workflow status for this branch was not obtained because nothing is pushed.

### M4 — In-memory journal exchange (delivered on `main`, in-memory only)

Delivered in `lib/sync/journal_exchange.dart`, `lib/sync/journal_scope.dart`, and `lib/sync/memory_journal_exchange.dart`, with `test/sync/memory_journal_exchange_test.dart` and `test/sync/two_device_convergence_test.dart`. `lib/sync/` is not imported by `lib/main.dart` or any other production code.

| Milestone | Candidate on `main` | Commits |
| --- | --- | --- |
| M4.1 provider-neutral in-memory exchange | `caa0c6b678dab98ee0a36613629ee3013350e738` | `fecc2f8` (2026-11-20 06:39:29 +0000), `86467c9` (06:42:52), correction `fcef23b` (07:18:52), integrated by merge `caa0c6b` (07:20:37) |
| M4.2 two-device convergence fixtures | `0918ea931ef32394b9a44520f9ca90e0e2d6d650` | `0918ea9` (07:24:50) |

- The exchange is provider-neutral and in-memory only: no persistence, no transport, no credentials, no retry policy, and no real diary data. The append step is synchronous, so an overlapping publish cannot lose the other's operations and no last-writer-wins rule exists.
- A batch is refused as a whole when any operation is invalid or out of scope, so a refused batch appends nothing. Admission is by identity only: identical replays are no-ops, divergent collisions are typed refusals keeping both variants, and accepted text is never overwritten.
- Only the decoded immutable operation is admitted. Each submitted operation is re-encoded and re-decoded, and the decoded value alone is scope-checked, compared, and stored, so an overridable getter, an overridable `toJson`, or a nested mutable value cannot keep changing what a journal reports.
- The convergence fixtures cover independent offline edits, reversed batch order, delayed delivery, retry after a lost response, duplicate delivery, competing actors on one entry, and same-scope identity collisions, using synthetic fixtures and a `MemoryJournalExchange` with the pure replay.
- Android APK workflow status for both M4 commits on `main` is success at attempt 1: run `44695727807` for `caa0c6b` and run `44695729525` for `0918ea9`. These are APK build workflow results, not on-device tests; no Android device test was run for M4.

### Known remaining production gates

None of the M3 work is hooked into the app, and these gates are still open:

1. **Snapshot/operation correspondence.** The store checks that the snapshot changed, not that it reflects the operation. Hookup needs projection-backed validation: replay derives the snapshot from the journal and the store compares it with `isSnapshotEquivalentToProjection`, instead of trusting the caller.
2. **Epoch registry.** Historical epoch uniqueness needs a durable record of every epoch issued for a notebook. The barrier helper deliberately does not implement it, so a caller cannot yet rely on a plan for uniqueness.
3. **Single-writer extension.** The path lock covers one isolate. A second isolate, a second process, and path aliases a lexical normalization cannot see (symlinks, hard links, case-insensitive file systems, bind mounts) can still lose updates.
4. **Durability.** `writeAsBytes(flush: true)` plus a same-directory rename survives a process crash. It is not a tested power-loss guarantee, and the directory is not fsynced.
5. **Barrier execution.** The barrier module returns decisions and plans only. Nothing writes the restored or emptied notebook together with the fresh epoch, and no reminder barrier is released, because no production caller exists.
6. **Replay policy gaps.** Expiry is decided from structure only, v1 revisions carry no civil date or due date, and competing actors are reported without a resolution policy.
7. **Volume lifecycle.** Volume deletion, restore rules, and entry destruction still need their own specification before they can be committed.
8. **Real sync provider.** M4 is in-memory only. A real transport needs authentication, encryption, and a lost-update argument before it touches real diary data, and no on-device test has been run.

None of the M3 journal work and none of the M4 exchange work is wired into production. M4 is complete only as an in-memory adapter and its convergence fixtures; no real provider, transport, credential handling, or on-device test exists.

## Roadmap after M1

1. **Application commands and queries.** Move diary mutations behind application services so the Android UI, a future laptop client, and future agent integrations can use the same domain rules. Keep `Notebook` independent of storage, transport, Flutter, and MCP.
2. **Offline change tracking.** Define versioned operations with stable identifiers, deduplicate replays, and persist the notebook update and its outgoing operation together. Keep existing JSON backup import/export compatible. Use deterministic conflict rules that never silently discard diary text; keep concurrent edits visible and define deletion behavior before enabling multi-device writes.
3. **Provider-neutral sync.** Start with an in-memory provider and test two-device convergence, retries, deduplication, and conflicts. Then select a real provider. WebDAV is a candidate, as are a self-hosted API and other storage adapters. Agree on authentication, encryption, and how the transport prevents lost updates before enabling sync with real diary data.
4. **Laptop writing.** Choose web or native desktop separately. Deliver opening, creating, and editing entries with offline local saves and synchronization with Android. Use an end-to-end acceptance check: edits made offline on both devices survive reconnection without silent data loss.
5. **Bring-your-own-agent access.** MCP is the integration protocol; skills are optional guidance for external agents. Put MCP above the application query/command layer, not directly over files. Start with opt-in, scoped read access for entry search, history, and prediction queries. Add draft creation only if approved and require user confirmation before a draft becomes a diary entry. No bundled AI provider.

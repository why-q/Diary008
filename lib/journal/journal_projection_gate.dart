/// Projection-backed snapshot validation for the experimental journal store.
///
/// Experimental and unshipped: nothing in production calls this, and the store
/// only runs it when a caller opts in and supplies an explicit baseline. It
/// reads no clock, performs no I/O, and mutates neither the baseline nor the
/// stored envelope.
///
/// Why it exists
/// -------------
/// The envelope store can prove that a commit changed the notebook snapshot,
/// but not that the snapshot reflects the journal. `Notebook` carries no
/// notebook, epoch, or entry identity, so a snapshot-versus-operation
/// correspondence is unverifiable by inspection. This gate derives that
/// correspondence instead of trusting the caller: the expected snapshot is
/// replayed from the journal, and the offered snapshot is compared with it.
///
/// The seed is explicit
/// --------------------
/// The only seed is [JournalProjectionBaseline]: an immutable snapshot taken
/// before the journal accepted any operation. There is deliberately no API
/// that recovers a seed by replaying the whole journal onto the already
/// projected snapshot, because that would assume the correspondence the gate
/// is supposed to prove and would accept any self-consistent tampering.
///
/// What is checked, in this order
/// ------------------------------
/// 1. The baseline, the stored envelope, and the offered journal share one
///    scope.
/// 2. The persisted snapshot equals the replay of the stored journal onto the
///    baseline, with no unresolved conflict. This catches a projection that
///    was already corrupted or drifted before the call, and it runs before the
///    offered snapshot is considered.
/// 3. The offered snapshot equals the replay of the offered journal onto the
///    same baseline. Replay conflicts are reported separately from a
///    structurally different snapshot, so a caller can tell "this operation
///    cannot be projected" from "this snapshot is not the projection".
///
/// Every snapshot is judged in its canonical form
/// ---------------------------------------------
/// `Notebook` is not final and its encoding is virtual, so a subclass can
/// return journal-equivalent values from its getters while serializing
/// different text. Comparing the caller's object would then validate one shape
/// and persist another. Each snapshot is therefore canonicalized once, through
/// its own encoding and back through `Notebook.fromJson`, and only the decoded
/// plain value is compared, persisted, or returned. The baseline is detached
/// the same way at construction, so it cannot drift after it was validated.
/// The caller's object is never consulted twice.
///
/// Anything else fails closed with a typed status; [JournalProjectionStatus]
/// never degrades to "assume it is fine".
///
/// Caller preconditions this gate cannot enforce
/// --------------------------------------------
/// These are stated so a future hookup does not mistake the gate for a
/// complete guarantee:
///
/// * The baseline must genuinely predate the first operation this envelope
///   accepted. The gate can prove internal consistency against the baseline it
///   is handed; it cannot prove the baseline itself was not fabricated or
///   rewritten. A durable, write-once record of the baseline is the caller's
///   job.
/// * The same baseline must be supplied on every call for one envelope file,
///   and it must be the snapshot that revision 1 was created with. Passing a
///   different baseline later is detected only insofar as it makes the stored
///   projection disagree.
/// * The caller's `base` envelope must be the envelope it actually read. The
///   gate re-reads the stored bytes under the per-path lock, so a fabricated
///   `base` is still caught by the store's revision/content comparison, but the
///   gate adds nothing there.
/// * Single-isolate, single-process ownership, path aliasing, and durability
///   limits are unchanged from the store. Projection validation narrows *what*
///   may be committed, not *who* may commit concurrently.
/// * Replay is deterministic but not lossless: it refuses anything it cannot
///   apply exactly and reports a typed conflict. A caller must treat a
///   `projectionConflict` as "no snapshot can be stored for this journal",
///   not as a transient error to retry.
library;

import '../notebook.dart';
import 'journal.dart';
import 'journal_replay.dart';
import 'journal_snapshot_equivalence.dart';
import 'journal_values.dart';
import 'notebook_envelope.dart';

/// Outcome of comparing persisted and offered snapshots with replay.
enum JournalProjectionStatus {
  /// Both snapshots are exactly the deterministic projection of their journal
  /// onto the baseline, and neither replay reported a conflict.
  valid,

  /// The baseline, the stored envelope, or the offered journal belongs to
  /// another notebook or epoch.
  scopeMismatch,

  /// The baseline snapshot is not structurally usable, so no projection can
  /// be trusted. Defensive: [JournalProjectionBaseline] refuses such a
  /// baseline at construction.
  baselineInvalid,

  /// The persisted snapshot is not the projection of the stored journal onto
  /// the baseline, or that projection has an unresolved conflict.
  baselineMismatch,

  /// The offered journal cannot be projected onto the baseline without an
  /// unresolved conflict, so no snapshot can represent it.
  projectionConflict,

  /// The offered journal projects cleanly, but the offered snapshot is not
  /// that projection.
  projectionMismatch,
}

/// An immutable snapshot taken before the journal accepted any operation.
///
/// [notebook] must satisfy the same invariants an envelope snapshot requires;
/// an invalid baseline throws [EnvelopeFormatException] at construction rather
/// than failing later during a commit. [scope] names the notebook and epoch the
/// baseline belongs to, so a baseline from another scope is detectable.
///
/// The baseline is never persisted by this library. A caller must supply it
/// from its own durable source on every call, and must supply the same
/// baseline for the lifetime of one envelope file.
final class JournalProjectionBaseline {
  JournalProjectionBaseline({required Notebook notebook, required this.scope})
    : notebook = _detach(notebook);

  /// Detaches the baseline from the caller's object.
  ///
  /// A baseline that kept the caller's instance could drift after
  /// construction: a subclass could answer honest getters when it was
  /// validated and serialize something else on every later replay. The stored
  /// value is the decoded, plain snapshot, so it cannot change.
  static Notebook _detach(Notebook candidate) {
    final canonical = CanonicalSnapshot.tryCanonicalize(candidate);
    if (canonical == null) {
      throw const EnvelopeFormatException(
        'projection baseline is not a canonically decodable snapshot',
        field: 'baseline',
      );
    }
    return canonical.notebook;
  }

  /// The plain snapshot taken before any operation was accepted. It is not the
  /// caller's object, so later mutation of that object cannot affect the gate.
  final Notebook notebook;

  final JournalScope scope;

  @override
  String toString() => 'JournalProjectionBaseline($scope)';
}

/// Stable diagnostic code for a [JournalProjectionStatus].
///
/// Exposed so a caller that refuses on a status without building a check (for
/// example, a snapshot that could not be canonicalized at all) reports the same
/// code every other refusal path uses.
String projectionDiagnosticCode(JournalProjectionStatus status) =>
    'journal.projection.${status.name}';

/// One gate decision, with the projections that produced it.
///
/// [storedProjection] is present once the persisted snapshot was projected.
/// [nextProjection] is present once the offered journal was projected. Neither
/// is a string, so no diary text leaks through [diagnosticCode].
final class JournalProjectionCheck {
  const JournalProjectionCheck._(
    this.status, {
    this.storedProjection,
    this.nextProjection,
  });

  final JournalProjectionStatus status;
  final JournalReplayResult? storedProjection;
  final JournalReplayResult? nextProjection;

  bool get isValid => status == JournalProjectionStatus.valid;

  /// Stable, content-free code suitable for diagnostics.
  String get diagnosticCode => projectionDiagnosticCode(status);

  @override
  String toString() => 'JournalProjectionCheck($diagnosticCode)';
}

/// Checks only the persisted side: the snapshot already in the envelope must be
/// the projection of the envelope's own journal onto [baseline].
///
/// The stored snapshot is canonicalized the same way an offered one is, so a
/// persisted envelope is judged by the bytes it would re-encode to rather than
/// by whatever object it carries.
///
/// This runs before admission, so a projection that is already corrupt or
/// drifted is refused even when the offered operation would be a no-op.
JournalProjectionCheck checkStoredProjection({
  required JournalProjectionBaseline baseline,
  required NotebookEnvelope stored,
}) {
  if (baseline.scope != stored.scope) {
    return const JournalProjectionCheck._(
      JournalProjectionStatus.scopeMismatch,
    );
  }
  final canonical = CanonicalSnapshot.tryCanonicalize(stored.notebook);
  if (canonical == null) {
    return const JournalProjectionCheck._(
      JournalProjectionStatus.baselineMismatch,
    );
  }
  final JournalReplayResult projection;
  try {
    projection = _project(baseline, stored.journal);
  } on JournalFormatException {
    return const JournalProjectionCheck._(
      JournalProjectionStatus.baselineInvalid,
    );
  }
  if (projection.hasConflicts ||
      !isSnapshotEquivalentToProjection(canonical.notebook, projection)) {
    return JournalProjectionCheck._(
      JournalProjectionStatus.baselineMismatch,
      storedProjection: projection,
    );
  }
  return JournalProjectionCheck._(
    JournalProjectionStatus.valid,
    storedProjection: projection,
  );
}

/// Checks only the offered side: the snapshot that will be written must be
/// the conflict-free projection of [journal] onto [baseline].
///
/// The candidate is canonicalized first, and the decoded value is what gets
/// compared. A snapshot whose getters and encoding disagree therefore cannot
/// pass by looking correct and then serializing something else, and the caller
/// encodes exactly the value that was checked.
///
/// [journal] is the journal the caller intends to persist, already including
/// the operation under consideration. This decides nothing about admission.
JournalProjectionCheck checkOfferedProjection({
  required JournalProjectionBaseline baseline,
  required Journal journal,
  required CanonicalSnapshot? notebook,
}) {
  if (!baseline.scope.covers(journal)) {
    return const JournalProjectionCheck._(
      JournalProjectionStatus.scopeMismatch,
    );
  }
  if (notebook == null) {
    // The offered snapshot could not produce a canonically decodable form, so
    // nothing about it can be trusted enough to persist.
    return const JournalProjectionCheck._(
      JournalProjectionStatus.projectionMismatch,
    );
  }
  final JournalReplayResult projection;
  try {
    projection = _project(baseline, journal);
  } on JournalFormatException {
    return const JournalProjectionCheck._(
      JournalProjectionStatus.scopeMismatch,
    );
  }
  if (projection.hasConflicts) {
    return JournalProjectionCheck._(
      JournalProjectionStatus.projectionConflict,
      nextProjection: projection,
    );
  }
  if (!isSnapshotEquivalentToProjection(notebook.notebook, projection)) {
    return JournalProjectionCheck._(
      JournalProjectionStatus.projectionMismatch,
      nextProjection: projection,
    );
  }
  return JournalProjectionCheck._(
    JournalProjectionStatus.valid,
    nextProjection: projection,
  );
}

/// Composes both checks for one commit: persisted first, then offered.
JournalProjectionCheck checkProjectionBackedSnapshots({
  required JournalProjectionBaseline baseline,
  required NotebookEnvelope stored,
  required Journal journal,
  required CanonicalSnapshot? notebook,
}) {
  final storedCheck = checkStoredProjection(baseline: baseline, stored: stored);
  if (!storedCheck.isValid) return storedCheck;
  return checkOfferedProjection(
    baseline: baseline,
    journal: journal,
    notebook: notebook,
  );
}

JournalReplayResult _project(
  JournalProjectionBaseline baseline,
  Journal journal,
) => JournalReplay.project(
  notebookId: baseline.scope.notebookId,
  epochId: baseline.scope.epochId,
  base: baseline.notebook,
  journal: journal,
);

import 'dart:io';

import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/epoch_history_barrier.dart';
import 'package:diary008/journal/epoch_history_envelope.dart';
import 'package:diary008/journal/epoch_history_reset.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_barrier.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-7d21';
const _epoch = 'ep-01';
const _fresh = 'ep-02';

/// One character longer than the journal identifier maximum of 128.
const _overlongEpoch =
    'ep-0123456789012345678901234567890123456789012345678901234567890'
    '12345678901234567890123456789012345678901234567890123456789012345';

final _now = DateTime.utc(2026, 11, 20, 14, 5, 7);

Notebook restoreSnapshot() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  entries: [
    JournalEntry(
      id: 'entry-b1',
      text: 'synthetic restore fixture',
      createdAt: _now,
      createdOn: DateTime.utc(2026, 11, 20),
      due: DateTime.utc(2026, 11, 30),
      status: EntryStatus.pending,
    ),
  ],
);

JournalCreateEntry _operation() => JournalCreateEntry(
  notebookId: _notebook,
  epochId: _epoch,
  actorId: 'dev-alpha',
  sequence: 1,
  operationId: 'op-1',
  recordedAt: _now,
  entryId: 'entry-b1',
  text: 'synthetic pending fixture',
  createdOn: CivilDate(2026, 11, 20),
);

/// An initial V2 document: revision 1, empty notebook, empty journal, ledger
/// holding exactly the journal epoch.
EpochHistoryEnvelope storedInitial() => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: 1,
    notebook: Notebook.empty(),
    journal: Journal(notebookId: _notebook, epochId: _epoch),
  ),
  history: EpochHistory(notebookId: _notebook, epochs: [_epoch]),
);

/// A synthetically seeded V2 document whose journal retains one operation.
EpochHistoryEnvelope storedWithPendingOperation() => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: 1,
    notebook: Notebook.empty(),
    journal: Journal(
      notebookId: _notebook,
      epochId: _epoch,
      operations: [_operation()],
    ),
  ),
  history: EpochHistory(notebookId: _notebook, epochs: [_epoch]),
);

EpochResetExpectation expectationFor(
  EpochHistoryEnvelope stored, {
  String notebookId = _notebook,
  int? revision,
  String? epochId,
}) => EpochResetExpectation(
  notebookId: notebookId,
  revision: revision ?? stored.envelope.revision,
  epochId: epochId ?? stored.envelope.journal.epochId,
);

/// A restore payload whose snapshot cannot be encoded, so reading it would
/// throw. Any check that runs before canonicalization must skip it entirely.
final class _ThrowingNotebook extends Notebook {
  _ThrowingNotebook() : super(volume: 1, entries: const []);

  bool wasRead = false;

  @override
  Map<String, dynamic> toJson() {
    wasRead = true;
    throw StateError('payload must not be read here');
  }
}

void main() {
  group('an allowed reset derives the whole document', () {
    test('restore derives revision, empty journal, and one ledger entry', () {
      final stored = storedInitial();
      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(restoreSnapshot()),
      );

      expect(outcome.status, EpochResetStatus.allowed);
      expect(outcome.action, JournalBarrierAction.restore);
      expect(outcome.isAllowed, isTrue);
      // A decision is never a durable claim.
      expect(outcome.isCommitted, isFalse);
      expect(outcome.revision, 2);
      expect(outcome.epochId, _fresh);

      final next = outcome.document!;
      expect(next.envelope.revision, 2);
      expect(next.envelope.notebook.volume, 2);
      expect(next.envelope.notebook.entries.single.id, 'entry-b1');
      expect(next.envelope.journal.epochId, _fresh);
      expect(next.envelope.journal.isEmpty, isTrue);
      expect(next.history.epochs, [_epoch, _fresh]);
    });

    test('wipe derives a canonically valid empty notebook', () {
      final stored = storedInitial();
      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(outcome.status, EpochResetStatus.allowed);
      expect(outcome.action, JournalBarrierAction.wipe);
      final notebook = outcome.document!.envelope.notebook;
      expect(notebook.entries, isEmpty);
      expect(notebook.archives, isEmpty);
      expect(notebook.volume, 1);
    });

    test('the derived document round trips through the codec', () {
      final stored = storedInitial();
      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(restoreSnapshot()),
      );

      final decoded = EpochHistoryEnvelope.decode(outcome.document!.encode());
      expect(decoded.hasSameContentAs(outcome.document!), isTrue);
    });

    test('the stored document is never mutated', () {
      final stored = storedInitial();
      planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(restoreSnapshot()),
      );

      expect(stored.history.epochs, [_epoch]);
      expect(stored.envelope.journal.epochId, _epoch);
      expect(stored.envelope.revision, 1);
    });
  });

  group('the caller cannot state the next document', () {
    test('the planner accepts no document, revision, journal, or ledger', () {
      // Pins the surface: there is no parameter a caller could use to supply
      // the replacement document itself.
      final source = File('lib/journal/epoch_history_reset.dart')
          .readAsStringSync();
      final signature = source.substring(
        source.indexOf('EpochResetOutcome planEpochReset('),
      );
      final declaration = signature.substring(0, signature.indexOf('})'));

      expect(declaration, contains('required EpochHistoryEnvelope stored'));
      expect(declaration, contains('required EpochResetExpectation expected'));
      expect(declaration, contains('required JournalResetEpoch epoch'));
      expect(declaration, contains('required JournalResetPayload payload'));
      expect(
        declaration,
        isNot(contains('required EpochHistoryEnvelope next')),
      );
      expect(declaration, isNot(contains('required Journal journal')));
      expect(declaration, isNot(contains('required EpochHistory history')));
      expect(declaration, isNot(contains('int revision')));
    });

    test('a wipe payload carries no data', () {
      final source = File('lib/journal/epoch_history_reset.dart')
          .readAsStringSync();
      expect(source, contains('class JournalWipePayload extends'));
      expect(source, contains('const JournalWipePayload();'));
    });

    test('a transition cannot be built without a matching document', () {
      final stored = storedInitial();
      final next = stored.advance(
        revision: 2,
        notebook: Notebook.empty(),
        journal: Journal(notebookId: _notebook, epochId: _fresh),
        history: stored.history.append(_fresh),
      );

      // A transition always carries the document it describes, so an empty
      // durable claim is not expressible.
      expect(
        () => EpochResetOutcome.applied(
          action: JournalBarrierAction.wipe,
          status: EpochResetStatus.committed,
          revision: 5,
          epochId: _fresh,
          document: next,
        ),
        throwsArgumentError,
      );
      expect(
        EpochResetOutcome.applied(
          action: JournalBarrierAction.wipe,
          status: EpochResetStatus.committed,
          revision: 2,
          epochId: _fresh,
          document: next,
        ).isCommitted,
        isTrue,
      );
    });

    test('a transition status cannot be built by a refusal factory', () {
      expect(
        () => EpochResetOutcome.notApplied(
          action: JournalBarrierAction.wipe,
          status: EpochResetStatus.committed,
        ),
        throwsArgumentError,
      );
      expect(
        () => EpochResetOutcome.notApplied(
          action: JournalBarrierAction.wipe,
          status: EpochResetStatus.allowed,
        ),
        throwsArgumentError,
      );
    });
  });

  group('refusal ordering decides before the payload is read', () {
    test('a retained operation refuses before the payload is touched', () {
      final stored = storedWithPendingOperation();
      final payload = _ThrowingNotebook();

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(payload),
      );

      expect(outcome.status, EpochResetStatus.policyRefused);
      expect(
        outcome.barrier!.barrier.reason,
        JournalBarrierReason.pendingOperations,
      );
      expect(payload.wasRead, isFalse);
      expect(outcome.document, isNull);
    });

    test('a stale revision refuses before the payload is touched', () {
      final stored = storedInitial();
      final payload = _ThrowingNotebook();

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored, revision: 9),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(payload),
      );

      expect(outcome.status, EpochResetStatus.stale);
      expect(payload.wasRead, isFalse);
      expect(outcome.reason, isNotNull);
    });

    test('a foreign notebook is a scope mismatch, never a stale write', () {
      final stored = storedInitial();

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored, notebookId: 'nb-other', revision: 9),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(restoreSnapshot()),
      );

      expect(outcome.status, EpochResetStatus.scopeMismatch);
    });

    test('an observed epoch that is not stored is stale', () {
      final stored = storedInitial();

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored, epochId: 'ep-old'),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(outcome.status, EpochResetStatus.stale);
    });

    test('an adopted epoch already in the ledger is refused as reused', () {
      final stored = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 2,
          notebook: Notebook.empty(),
          journal: Journal(notebookId: _notebook, epochId: _epoch),
        ),
        history: EpochHistory(notebookId: _notebook, epochs: ['ep-00', _epoch]),
      );

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch('ep-00'),
        payload: const JournalWipePayload(),
      );

      expect(outcome.status, EpochResetStatus.policyRefused);
      expect(outcome.barrier!.status, HistoricalBarrierStatus.freshEpochReused);
      expect(outcome.document, isNull);
    });

    test('the current epoch is refused by the version 1 policy', () {
      final stored = storedInitial();

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_epoch),
        payload: const JournalWipePayload(),
      );

      expect(outcome.status, EpochResetStatus.policyRefused);
      expect(
        outcome.barrier!.barrier.reason,
        JournalBarrierReason.freshEpochReused,
      );
    });
  });

  group('an unusable payload is refused only after the policy allows it', () {
    test('a snapshot that cannot be encoded is payloadInvalid', () {
      final stored = storedInitial();

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(_ThrowingNotebook()),
      );

      expect(outcome.status, EpochResetStatus.payloadInvalid);
      expect(outcome.document, isNull);
      // The policy still ran and allowed the action.
      expect(outcome.barrier!.allowed, isTrue);
    });

    test('duplicate entry identifiers are payloadInvalid', () {
      final stored = storedInitial();
      final duplicated = Notebook(
        volume: 1,
        entries: [
          JournalEntry(
            id: 'entry-dup',
            text: 'first',
            createdAt: _now,
            createdOn: DateTime.utc(2026, 11, 20),
            due: DateTime.utc(2026, 11, 30),
            status: EntryStatus.pending,
          ),
          JournalEntry(
            id: 'entry-dup',
            text: 'second',
            createdAt: _now,
            createdOn: DateTime.utc(2026, 11, 20),
            due: DateTime.utc(2026, 11, 30),
            status: EntryStatus.pending,
          ),
        ],
      );

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(duplicated),
      );

      expect(outcome.status, EpochResetStatus.payloadInvalid);
    });

    test('an explanation entry carrying a due date is payloadInvalid', () {
      final stored = storedInitial();
      final invalid = Notebook(
        volume: 1,
        entries: [
          JournalEntry(
            id: 'entry-x',
            text: 'supplement',
            createdAt: _now,
            createdOn: DateTime.utc(2026, 11, 20),
            due: DateTime.utc(2026, 11, 30),
            status: EntryStatus.explanation,
          ),
        ],
      );

      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(invalid),
      );

      expect(outcome.status, EpochResetStatus.payloadInvalid);
    });

    test('no refusal carries the payload or the stored document', () {
      final stored = storedWithPendingOperation();
      final payload = _ThrowingNotebook();
      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(payload),
      );

      expect(outcome.document, isNull);
      expect(outcome.reason, isNot(contains('payload must not be read')));
      expect(outcome.toString(), contains('journal.reset.restore'));
    });
  });

  group('the fresh epoch is a validated opaque token', () {
    test('accepted values follow the journal identifier rule', () {
      expect(JournalResetEpoch('ep-02').id, 'ep-02');
      expect(const JournalWipePayload(), isA<JournalResetPayload>());
      // Numeric-only values are refused so a volume ordinal or a count cannot
      // pose as an epoch. Long or non-ASCII tokens are refused by the pattern.
      // A date-shaped token that satisfies the pattern is accepted here; the
      // pattern is the journal's own; this slice neither widens nor narrows it.
      for (final value in ['', '01', 'ep 01', '  ', 'ep\u00e9']) {
        expect(
          () => JournalResetEpoch(value),
          throwsA(isA<JournalFormatException>()),
          reason: 'accepted "$value"',
        );
      }
      expect(
        () => JournalResetEpoch(_overlongEpoch),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('two epochs with the same id compare equal', () {
      expect(JournalResetEpoch(_fresh), JournalResetEpoch(_fresh));
      expect(
        JournalResetEpoch(_fresh).hashCode,
        JournalResetEpoch(_fresh).hashCode,
      );
    });
  });

  group('the planner is pure', () {
    test('identical inputs produce equal outcomes', () {
      EpochResetOutcome run() {
        final stored = storedInitial();
        return planEpochReset(
          notebookId: _notebook,
          stored: stored,
          expected: expectationFor(stored),
          epoch: JournalResetEpoch(_fresh),
          payload: JournalRestorePayload(restoreSnapshot()),
        );
      }

      expect(run(), equals(run()));
    });

    test('diagnostics carry identifiers and statuses only', () {
      final stored = storedInitial();
      final outcome = planEpochReset(
        notebookId: _notebook,
        stored: stored,
        expected: expectationFor(stored, revision: 4),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(restoreSnapshot()),
      );

      expect(outcome.diagnosticCode, 'journal.reset.restore.stale');
      expect(outcome.toString(), isNot(contains('synthetic')));
    });
  });
}

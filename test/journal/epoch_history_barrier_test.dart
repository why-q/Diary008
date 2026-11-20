import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/epoch_history_barrier.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_barrier.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-8f2c';
const _epoch = 'ep-02';

JournalCreateEntry createOp() => JournalCreateEntry(
  notebookId: _notebook,
  epochId: _epoch,
  actorId: 'dev-alpha',
  sequence: 1,
  operationId: 'op-a1',
  recordedAt: DateTime.utc(2026, 11, 19, 12, 45, 7),
  entryId: 'entry-77',
  text: 'synthetic fixture text',
  createdOn: CivilDate.parse('2026-11-19'),
);

Journal emptyJournal({String epochId = _epoch}) =>
    Journal(notebookId: _notebook, epochId: epochId);

Journal journalWithOperation() {
  final journal = emptyJournal();
  journal.admit(createOp());
  return journal;
}

EpochHistory history({List<String> epochs = const ['ep-01', _epoch]}) =>
    EpochHistory(notebookId: _notebook, epochs: epochs);

HistoricalBarrierDecision decide({
  JournalBarrierAction action = JournalBarrierAction.wipe,
  Journal? journal,
  String notebookId = _notebook,
  EpochHistory? epochs,
  String? freshEpochId,
}) => planHistoricalBarrier(
  action: action,
  journal: journal ?? emptyJournal(),
  notebookId: notebookId,
  history: epochs ?? history(),
  freshEpochId: freshEpochId,
);

void main() {
  group('composition with the version 1 policy', () {
    test('the version 1 block is preserved verbatim', () {
      final decision = decide(
        journal: journalWithOperation(),
        freshEpochId: 'ep-09',
      );
      expect(decision.status, HistoricalBarrierStatus.barrierBlocked);
      expect(decision.barrier.reason, JournalBarrierReason.pendingOperations);
      expect(decision.plan, isNull);
      expect(decision.allowed, isFalse);
    });

    test('a blocked export stays blocked even with a valid ledger', () {
      final decision = decide(
        action: JournalBarrierAction.export,
        journal: journalWithOperation(),
      );
      expect(decision.status, HistoricalBarrierStatus.barrierBlocked);
      expect(decision.barrier.reason, JournalBarrierReason.pendingOperations);
    });

    test('an allowed export keeps the version 1 decision and no plan', () {
      final decision = decide(action: JournalBarrierAction.export);
      expect(decision.status, HistoricalBarrierStatus.allowed);
      expect(decision.plan, isNull);
      expect(decision.barrier.allowed, isTrue);
    });

    test('a missing fresh epoch is still refused by the version 1 policy', () {
      final decision = decide();
      expect(decision.status, HistoricalBarrierStatus.barrierBlocked);
      expect(decision.barrier.reason, JournalBarrierReason.freshEpochRequired);
    });
  });

  group('historical uniqueness from the ledger', () {
    test('an unused fresh epoch is allowed and produces the plan', () {
      final decision = decide(freshEpochId: 'ep-09');
      expect(decision.status, HistoricalBarrierStatus.allowed);
      expect(decision.barrier.reason, JournalBarrierReason.allowed);
      expect(decision.plan, isNotNull);
      expect(decision.plan!.epochId, 'ep-09');
      expect(decision.plan!.notebookId, _notebook);
      expect(decision.plan!.emptyJournal().epochId, 'ep-09');
    });

    test('an epoch used in an earlier epoch is refused as reused', () {
      final decision = decide(
        epochs: history(epochs: const ['ep-01', _epoch]),
        freshEpochId: 'ep-01',
      );
      expect(decision.status, HistoricalBarrierStatus.freshEpochReused);
      expect(decision.plan, isNull);
      expect(decision.allowed, isFalse);
    });

    test('the current epoch is refused as a version 1 reuse', () {
      final decision = decide(freshEpochId: _epoch);
      expect(decision.status, HistoricalBarrierStatus.barrierBlocked);
      expect(decision.barrier.reason, JournalBarrierReason.freshEpochReused);
      expect(decision.plan, isNull);
    });

    test('two planned resets cannot reuse one fresh epoch', () {
      // The version 1 helper alone would allow both, because the second plan's
      // ledger is not consulted. The durable ledger refuses the second.
      final first = decide(epochs: history(), freshEpochId: 'ep-09');
      expect(first.status, HistoricalBarrierStatus.allowed);

      final adopted = history().append(first.plan!.epochId);
      final second = decide(
        journal: emptyJournal(epochId: 'ep-09'),
        epochs: adopted,
        freshEpochId: 'ep-09',
      );
      expect(second.status, HistoricalBarrierStatus.barrierBlocked);
      expect(second.barrier.reason, JournalBarrierReason.freshEpochReused);

      final third = decide(
        journal: emptyJournal(epochId: 'ep-09'),
        epochs: adopted,
        freshEpochId: 'ep-10',
      );
      expect(third.status, HistoricalBarrierStatus.allowed);
    });

    test('an invalid fresh epoch is refused by the version 1 policy', () {
      final decision = decide(freshEpochId: '99');
      expect(decision.status, HistoricalBarrierStatus.barrierBlocked);
      expect(decision.barrier.reason, JournalBarrierReason.freshEpochInvalid);
    });
  });

  group('the ledger must prove the current epoch', () {
    test('a ledger that stops before the journal epoch is refused', () {
      final decision = decide(
        epochs: history(epochs: const ['ep-01']),
        freshEpochId: 'ep-09',
      );
      expect(
        decision.status,
        HistoricalBarrierStatus.historyDoesNotReachJournal,
      );
      expect(decision.plan, isNull);
    });

    test('a ledger whose newest epoch is ahead of the journal is refused', () {
      final decision = decide(
        epochs: history(epochs: const ['ep-01', _epoch, 'ep-05']),
        freshEpochId: 'ep-09',
      );
      expect(
        decision.status,
        HistoricalBarrierStatus.historyDoesNotReachJournal,
      );
    });

    test('a ledger for another notebook is refused', () {
      final decision = decide(
        epochs: EpochHistory(
          notebookId: 'nb-other',
          epochs: const ['ep-01', _epoch],
        ),
        freshEpochId: 'ep-09',
      );
      expect(decision.status, HistoricalBarrierStatus.historyNotebookMismatch);
    });

    test('the ledger is checked before the fresh epoch is accepted', () {
      final decision = decide(
        epochs: history(epochs: const ['ep-01']),
        freshEpochId: 'ep-01',
      );
      expect(
        decision.status,
        HistoricalBarrierStatus.historyDoesNotReachJournal,
      );
    });
  });

  group('purity', () {
    test('decisions are deterministic and never mutate the ledger', () {
      final ledger = history();
      final a = decide(epochs: ledger, freshEpochId: 'ep-09');
      final b = decide(epochs: ledger, freshEpochId: 'ep-09');
      expect(a.status, b.status);
      expect(a.plan, b.plan);
      expect(ledger.epochs, ['ep-01', _epoch]);
    });

    test('identical inputs produce an equal decision', () {
      expect(decide(freshEpochId: 'ep-09'), decide(freshEpochId: 'ep-09'));
      expect(
        decide(freshEpochId: 'ep-09'),
        isNot(decide(freshEpochId: 'ep-10')),
      );
    });

    test('diagnostics carry identifiers only, never diary text', () {
      final decision = decide(
        journal: journalWithOperation(),
        freshEpochId: 'ep-09',
      );
      expect(decision.diagnosticCode, isNot(contains('synthetic')));
      expect(decision.status.name, isNot(contains('synthetic')));
    });
  });
}

import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_barrier.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-8f2c';
const _epoch = 'ep-01';
const _freshEpoch = 'ep-02';

JournalCreateEntry createOp({
  String operationId = 'op-a1',
  String actorId = 'dev-alpha',
  int sequence = 1,
  String entryId = 'entry-77',
  String notebookId = _notebook,
  String epochId = _epoch,
}) => JournalCreateEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: DateTime.utc(2026, 11, 19, 12, 45, 7),
  entryId: entryId,
  text: 'synthetic fixture text',
  createdOn: CivilDate.parse('2026-11-19'),
);

Journal journalWithOperations() {
  final log = Journal(notebookId: _notebook, epochId: _epoch);
  log.admit(createOp());
  return log;
}

Journal emptyJournal() => Journal(notebookId: _notebook, epochId: _epoch);

JournalBarrierDecision decide(
  JournalBarrierAction action,
  Journal journal, {
  String notebookId = _notebook,
  String? freshEpochId,
}) => planJournalBarrier(
  action: action,
  journal: journal,
  notebookId: notebookId,
  freshEpochId: freshEpochId,
);

void main() {
  group('blocked decisions', () {
    for (final action in JournalBarrierAction.values) {
      test('${action.name} is blocked while operations remain', () {
        final decision = decide(
          action,
          journalWithOperations(),
          freshEpochId: _freshEpoch,
        );

        expect(decision.allowed, isFalse);
        expect(decision.reason, JournalBarrierReason.pendingOperations);
        expect(decision.plan, isNull);
        expect(
          decision.diagnosticCode,
          'journal.barrier.${action.name}.pendingOperations',
        );
      });
    }

    test('a journal with only a retained revision still blocks export', () {
      final log = Journal(notebookId: _notebook, epochId: _epoch);
      log.admit(
        JournalReviseEntry(
          notebookId: _notebook,
          epochId: _epoch,
          actorId: 'dev-alpha',
          sequence: 4,
          operationId: 'op-b1',
          recordedAt: DateTime.utc(2026, 11, 19, 13),
          entryId: 'entry-77',
          text: 'synthetic revision text',
        ),
      );

      final decision = decide(JournalBarrierAction.export, log);

      expect(decision.reason, JournalBarrierReason.pendingOperations);
    });

    test('restore and wipe of an empty journal need a fresh epoch', () {
      for (final action in [
        JournalBarrierAction.restore,
        JournalBarrierAction.wipe,
      ]) {
        final decision = decide(action, emptyJournal());

        expect(decision.reason, JournalBarrierReason.freshEpochRequired);
        expect(decision.plan, isNull);
      }
    });
  });

  group('allowed decisions', () {
    test('export of an empty journal is allowed without a plan', () {
      final decision = decide(JournalBarrierAction.export, emptyJournal());

      expect(decision.allowed, isTrue);
      expect(decision.reason, JournalBarrierReason.allowed);
      expect(decision.plan, isNull);
    });

    test('export ignores a supplied fresh epoch', () {
      expect(
        decide(
          JournalBarrierAction.export,
          emptyJournal(),
          freshEpochId: _freshEpoch,
        ).plan,
        isNull,
      );
      expect(
        decide(
          JournalBarrierAction.export,
          emptyJournal(),
          freshEpochId: _epoch,
        ).allowed,
        isTrue,
      );
    });

    for (final action in [
      JournalBarrierAction.restore,
      JournalBarrierAction.wipe,
    ]) {
      test('${action.name} of an empty journal plans the fresh scope', () {
        final decision = decide(
          action,
          emptyJournal(),
          freshEpochId: _freshEpoch,
        );

        expect(decision.allowed, isTrue);
        expect(decision.plan!.notebookId, _notebook);
        expect(decision.plan!.epochId, _freshEpoch);
        expect(
          decision.diagnosticCode,
          'journal.barrier.${action.name}.allowed',
        );
      });
    }
  });

  group('fresh epoch validation', () {
    test('a missing fresh epoch is rejected', () {
      final decision = decide(JournalBarrierAction.wipe, emptyJournal());

      expect(decision.reason, JournalBarrierReason.freshEpochRequired);
    });

    test('historical reuse is left to the caller', () {
      // No durable epoch registry exists, so the helper cannot know that
      // 'ep-02' was issued before. It plans the same epoch twice, and only
      // rejects the epoch the journal in hand already uses. Callers must check
      // historical uniqueness themselves; this test pins that limit.
      final first = decide(
        JournalBarrierAction.restore,
        emptyJournal(),
        freshEpochId: _freshEpoch,
      );
      final second = decide(
        JournalBarrierAction.restore,
        emptyJournal(),
        freshEpochId: _freshEpoch,
      );

      expect(first.allowed, isTrue);
      expect(second.allowed, isTrue);
      expect(first.plan, second.plan);

      // A plan registers nothing, so the epoch stays reusable after planning.
      first.plan!.emptyJournal();
      expect(
        decide(
          JournalBarrierAction.wipe,
          emptyJournal(),
          freshEpochId: _freshEpoch,
        ).allowed,
        isTrue,
      );
    });

    test('a malformed fresh epoch is rejected', () {
      for (final invalid in ['', '12', 'ep 02', 'has space', '!bad']) {
        final decision = decide(
          JournalBarrierAction.restore,
          emptyJournal(),
          freshEpochId: invalid,
        );

        expect(
          decision.reason,
          JournalBarrierReason.freshEpochInvalid,
          reason: 'expected "$invalid" to be rejected',
        );
        expect(decision.plan, isNull);
      }
    });

    test('reusing the current epoch is rejected', () {
      final decision = decide(
        JournalBarrierAction.restore,
        emptyJournal(),
        freshEpochId: _epoch,
      );

      expect(decision.reason, JournalBarrierReason.freshEpochReused);
      expect(decision.plan, isNull);
    });

    test('fresh epoch validation runs only after the journal is empty', () {
      final decision = decide(
        JournalBarrierAction.restore,
        journalWithOperations(),
        freshEpochId: _epoch,
      );

      expect(decision.reason, JournalBarrierReason.pendingOperations);
    });
  });

  group('scope isolation', () {
    test('an invalid notebook identifier is rejected', () {
      for (final invalid in ['', '12345', 'nb 8f2c', 'nb-8f2c!']) {
        final decision = decide(
          JournalBarrierAction.export,
          emptyJournal(),
          notebookId: invalid,
        );

        expect(
          decision.reason,
          JournalBarrierReason.notebookInvalid,
          reason: 'expected "$invalid" to be rejected',
        );
      }
    });

    test('a journal for another notebook is refused', () {
      final decision = decide(
        JournalBarrierAction.export,
        emptyJournal(),
        notebookId: 'nb-other',
      );

      expect(decision.reason, JournalBarrierReason.notebookMismatch);
      expect(decision.plan, isNull);
    });

    test('notebook validation precedes the pending-operation check', () {
      final decision = decide(
        JournalBarrierAction.wipe,
        journalWithOperations(),
        notebookId: 'nb-other',
      );

      expect(decision.reason, JournalBarrierReason.notebookMismatch);
    });

    test('a plan journal admits only its own notebook and epoch', () {
      final decision = decide(
        JournalBarrierAction.restore,
        emptyJournal(),
        freshEpochId: _freshEpoch,
      );
      final planned = decision.plan!.emptyJournal();

      expect(planned.notebookId, _notebook);
      expect(planned.epochId, _freshEpoch);
      expect(planned.isEmpty, isTrue);
      expect(
        planned
            .admit(createOp(epochId: _freshEpoch, operationId: 'op-new'))
            .admission,
        JournalAdmission.appended,
      );
      expect(
        planned.admit(createOp(notebookId: 'nb-other')).admission,
        JournalAdmission.rejected,
      );
    });
  });

  group('stale operations', () {
    test('operations from the previous epoch fail admission to the plan', () {
      final source = journalWithOperations();
      final stale = source.operations.single;

      final planned = decide(
        JournalBarrierAction.wipe,
        emptyJournal(),
        freshEpochId: _freshEpoch,
      ).plan!.emptyJournal();

      final result = planned.admit(stale);

      expect(result.admission, JournalAdmission.rejected);
      expect(planned.isEmpty, isTrue);
      expect(planned.byOperationId(stale.operationId), isNull);
    });

    test('an identical operation becomes admissible only in its own epoch', () {
      final stale = createOp();

      final planned = decide(
        JournalBarrierAction.restore,
        emptyJournal(),
        freshEpochId: _freshEpoch,
      ).plan!.emptyJournal();

      expect(planned.admit(stale).admission, JournalAdmission.rejected);
      expect(
        planned.admit(createOp(epochId: _freshEpoch)).admission,
        JournalAdmission.appended,
      );
      expect(planned.length, 1);
    });
  });

  group('determinism and immutability', () {
    test('identical inputs produce equal decisions', () {
      final log = journalWithOperations();

      final first = decide(
        JournalBarrierAction.restore,
        log,
        freshEpochId: _freshEpoch,
      );
      final second = decide(
        JournalBarrierAction.restore,
        log,
        freshEpochId: _freshEpoch,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.toString(), second.toString());
    });

    test('a decision carries no diary text', () {
      final decision = decide(
        JournalBarrierAction.export,
        journalWithOperations(),
      );

      expect(decision.toString(), isNot(contains('synthetic fixture text')));
      expect(decision.diagnosticCode, isNot(contains('synthetic')));
    });

    test('evaluating a barrier does not mutate the journal', () {
      final log = journalWithOperations();
      final before = log.encode();

      for (final action in JournalBarrierAction.values) {
        decide(action, log, freshEpochId: _freshEpoch);
        decide(action, emptyJournal(), freshEpochId: _freshEpoch);
      }

      expect(log.encode(), before);
      expect(log.length, 1);
      expect(log.epochId, _epoch);
    });

    test('plans are equal by value and do not touch their source journal', () {
      final log = emptyJournal();
      final before = log.encode();

      final a = decide(
        JournalBarrierAction.wipe,
        log,
        freshEpochId: _freshEpoch,
      ).plan!;
      final b = decide(
        JournalBarrierAction.wipe,
        log,
        freshEpochId: _freshEpoch,
      ).plan!;

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.emptyJournal().encode(), b.emptyJournal().encode());
      expect(log.encode(), before);
      expect(log.isEmpty, isTrue);
    });
  });

  group('decision invariants', () {
    test('every decision carries a plan only when it is an allowed restore '
        'or wipe', () {
      final journals = [emptyJournal(), journalWithOperations()];
      final notebooks = [_notebook, 'nb-other', '', '12345'];
      final freshEpochs = [null, _freshEpoch, _epoch, '', 'ep 02'];

      for (final action in JournalBarrierAction.values) {
        for (final journal in journals) {
          for (final notebookId in notebooks) {
            for (final freshEpochId in freshEpochs) {
              final decision = planJournalBarrier(
                action: action,
                journal: journal,
                notebookId: notebookId,
                freshEpochId: freshEpochId,
              );
              final expectsPlan =
                  decision.allowed && action != JournalBarrierAction.export;
              expect(
                decision.plan != null,
                expectsPlan,
                reason:
                    '${decision.diagnosticCode} notebook=$notebookId '
                    'epoch=$freshEpochId',
              );
              if (expectsPlan) {
                expect(decision.plan!.notebookId, notebookId);
                expect(decision.plan!.epochId, freshEpochId);
              }
            }
          }
        }
      }
    });
  });
}

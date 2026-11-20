import 'dart:async';

import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/sync/journal_exchange.dart';
import 'package:diary008/sync/journal_scope.dart';
import 'package:diary008/sync/memory_journal_exchange.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-8f2c';
const _epoch = 'ep-01';

JournalScope scope({String notebookId = _notebook, String epochId = _epoch}) =>
    JournalScope(notebookId: notebookId, epochId: epochId);

JournalCreateEntry createOp({
  String operationId = 'op-a1',
  String actorId = 'dev-alpha',
  int sequence = 1,
  String entryId = 'entry-77',
  String text = '我会考完雅思。',
  String createdOn = '2026-11-19',
  DateTime? recordedAt,
  String notebookId = _notebook,
  String epochId = _epoch,
}) => JournalCreateEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: recordedAt ?? DateTime.utc(2026, 11, 19, 12, 45, 7, 123, 456),
  entryId: entryId,
  text: text,
  createdOn: CivilDate.parse(createdOn),
);

JournalReviseEntry reviseOp({
  String operationId = 'op-b1',
  String actorId = 'dev-alpha',
  int sequence = 2,
  String entryId = 'entry-77',
  String text = '我会考完雅思，然后旅行。',
  DateTime? recordedAt,
  String notebookId = _notebook,
  String epochId = _epoch,
}) => JournalReviseEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: recordedAt ?? DateTime.utc(2026, 11, 19, 13, 0, 0),
  entryId: entryId,
  text: text,
);

/// Matches an operation by content, not by object identity.
///
/// The exchange stores its own decoded value, so a submitted object and the
/// stored operation are never the same instance.
Matcher sameContent(JournalOperation expected) => isA<JournalOperation>()
    .having((operation) => operation.canonicalForm, 'canonicalForm',
        expected.canonicalForm);

JournalPublishCommitted committed(JournalPublishResult result) {
  expect(result, isA<JournalPublishCommitted>());
  return result as JournalPublishCommitted;
}

JournalPublishRejected rejected(JournalPublishResult result) {
  expect(result, isA<JournalPublishRejected>());
  return result as JournalPublishRejected;
}

/// A transport wrapper that reports failure after the exchange has committed,
/// which is what a lost response looks like to a client.
class _LostResponse implements JournalExchange {
  _LostResponse(this.inner);

  final JournalExchange inner;
  int failuresRemaining = 1;

  @override
  Future<JournalPublishResult> publish({
    required JournalScope scope,
    required Iterable<JournalOperation> operations,
  }) async {
    final result = await inner.publish(scope: scope, operations: operations);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('response lost after the batch was stored');
    }
    return result;
  }

  @override
  Future<JournalSnapshot> fetch({required JournalScope scope}) =>
      inner.fetch(scope: scope);
}

void main() {
  group('scope', () {
    test('rejects identifiers the journal protocol would reject', () {
      expect(
        () => scope(notebookId: '12'),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => scope(epochId: '我的日记'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('equality is by notebook and epoch, not by instance', () {
      expect(scope(), scope());
      expect(scope().hashCode, scope().hashCode);
      expect(scope(epochId: 'ep-02'), isNot(scope()));
    });

    test('contains only operations claiming the same notebook and epoch', () {
      expect(scope().contains(createOp()), isTrue);
      expect(scope().contains(createOp(notebookId: 'nb-other')), isFalse);
      expect(scope().contains(createOp(epochId: 'ep-02')), isFalse);
    });
  });

  group('publish and fetch', () {
    test('a published batch is readable in the same order', () async {
      final exchange = MemoryJournalExchange();
      final first = createOp();
      final second = reviseOp();

      final result = committed(
        await exchange.publish(scope: scope(), operations: [first, second]),
      );
      final snapshot = await exchange.fetch(scope: scope());

      expect(result.appended, [sameContent(first), sameContent(second)]);
      expect(result.replayed, isEmpty);
      expect(result.conflicts, isEmpty);
      expect(snapshot.operations, [sameContent(first), sameContent(second)]);
      expect(snapshot.scope, scope());
      expect(snapshot.length, 2);
    });

    test('an empty scope reads as an empty snapshot, not an error', () async {
      final exchange = MemoryJournalExchange();

      final snapshot = await exchange.fetch(scope: scope());

      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.operations, isEmpty);
      expect(snapshot.scope, scope());
      expect(exchange.scopes, isEmpty);
    });

    test('an empty batch is a valid no-op', () async {
      final exchange = MemoryJournalExchange();

      final result = committed(
        await exchange.publish(scope: scope(), operations: const []),
      );

      expect(result.isNoOp, isTrue);
      expect(result.appendedAny, isFalse);
      expect(result.hasConflicts, isFalse);
      expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
    });

    test('results echo the scope the caller requested', () async {
      final exchange = MemoryJournalExchange();
      final requested = scope(notebookId: 'nb-echo', epochId: 'ep-echo');

      final result = committed(
        await exchange.publish(
          scope: requested,
          operations: [createOp(notebookId: 'nb-echo', epochId: 'ep-echo')],
        ),
      );

      expect(result.scope, requested);
      expect((await exchange.fetch(scope: requested)).scope, requested);
    });

    test('snapshot lookups answer by identity, not by position', () async {
      final exchange = MemoryJournalExchange();
      final create = createOp();
      final revise = reviseOp();
      await exchange.publish(scope: scope(), operations: [create, revise]);

      final snapshot = await exchange.fetch(scope: scope());

      expect(snapshot.byOperationId('op-a1'), sameContent(create));
      expect(snapshot.byOperationId('op-missing'), isNull);
      expect(snapshot.byActorSequence('dev-alpha', 2), sameContent(revise));
      expect(snapshot.byActorSequence('dev-alpha', 3), isNull);
      expect(snapshot.operationsForEntry('entry-77'), [
        sameContent(create),
        sameContent(revise),
      ]);
      expect(snapshot.operationsForEntry('entry-other'), isEmpty);
    });
  });

  group('replay and deduplication', () {
    test('an identical replay appends nothing', () async {
      final exchange = MemoryJournalExchange();
      final operation = createOp();
      await exchange.publish(scope: scope(), operations: [operation]);

      final replay = committed(
        await exchange.publish(scope: scope(), operations: [createOp()]),
      );

      expect(replay.isNoOp, isTrue);
      expect(replay.replayed, [sameContent(operation)]);
      expect(replay.conflicts, isEmpty);
      expect((await exchange.fetch(scope: scope())).length, 1);
    });

    test('a duplicate inside one batch is appended once', () async {
      final exchange = MemoryJournalExchange();

      final result = committed(
        await exchange.publish(
          scope: scope(),
          operations: [createOp(), createOp()],
        ),
      );

      expect(result.appended, hasLength(1));
      expect(result.replayed, hasLength(1));
      expect((await exchange.fetch(scope: scope())).length, 1);
    });

    test('a retry after a lost response converges on one operation', () async {
      final inner = MemoryJournalExchange();
      final transport = _LostResponse(inner);

      await expectLater(
        transport.publish(scope: scope(), operations: [createOp()]),
        throwsA(isA<StateError>()),
      );
      final retried = committed(
        await transport.publish(scope: scope(), operations: [createOp()]),
      );

      expect(retried.isNoOp, isTrue);
      expect(retried.replayed.single.text, '我会考完雅思。');
      expect((await inner.fetch(scope: scope())).length, 1);
    });

    test('a repeated replay stays a no-op on every attempt', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(scope: scope(), operations: [createOp()]);

      for (var attempt = 0; attempt < 3; attempt++) {
        final result = committed(
          await exchange.publish(scope: scope(), operations: [createOp()]),
        );
        expect(result.isNoOp, isTrue);
      }
      expect((await exchange.fetch(scope: scope())).length, 1);
    });
  });

  group('divergent collisions', () {
    test('a reused operation id with other text is a typed refusal', () async {
      final exchange = MemoryJournalExchange();
      final accepted = createOp(text: '第一次写下的内容。');
      await exchange.publish(scope: scope(), operations: [accepted]);

      final result = committed(
        await exchange.publish(
          scope: scope(),
          operations: [createOp(text: '后来改写的内容。')],
        ),
      );

      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalRefusalKind.operationIdCollision);
      expect(conflict.incoming.text, '后来改写的内容。');
      expect(conflict.accepted, sameContent(accepted));
      expect(conflict.accepted!.text, '第一次写下的内容。');
      expect(result.isNoOp, isTrue);

      final snapshot = await exchange.fetch(scope: scope());
      expect(snapshot.operations.single.text, '第一次写下的内容。');
      expect(snapshot.length, 1);
    });

    test('a reused actor sequence with another operation is refused', () async {
      final exchange = MemoryJournalExchange();
      final accepted = createOp(operationId: 'op-a1', sequence: 1);
      await exchange.publish(scope: scope(), operations: [accepted]);

      final result = committed(
        await exchange.publish(
          scope: scope(),
          operations: [
            createOp(
              operationId: 'op-a2',
              sequence: 1,
              entryId: 'entry-78',
              text: '同一台设备的第二个操作。',
            ),
          ],
        ),
      );

      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalRefusalKind.actorSequenceCollision);
      expect(conflict.accepted, sameContent(accepted));
      expect(conflict.incoming.operationId, 'op-a2');
      expect((await exchange.fetch(scope: scope())).length, 1);
    });

    test('a second creation of one entry keeps the first text', () async {
      final exchange = MemoryJournalExchange();
      final accepted = createOp(operationId: 'op-a1', text: '设备甲的原文。');
      await exchange.publish(scope: scope(), operations: [accepted]);

      final result = committed(
        await exchange.publish(
          scope: scope(),
          operations: [
            createOp(
              operationId: 'op-z9',
              actorId: 'dev-beta',
              entryId: 'entry-77',
              text: '设备乙的原文。',
            ),
          ],
        ),
      );

      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalRefusalKind.entryCreationCollision);
      expect(conflict.accepted!.text, '设备甲的原文。');
      expect(conflict.incoming.text, '设备乙的原文。');

      final snapshot = await exchange.fetch(scope: scope());
      expect(snapshot.operations.single.text, '设备甲的原文。');
    });

    test('a batch may append new operations and refuse a conflict', () async {
      final exchange = MemoryJournalExchange();
      final accepted = createOp();
      await exchange.publish(scope: scope(), operations: [accepted]);
      final fresh = reviseOp();

      final result = committed(
        await exchange.publish(
          scope: scope(),
          operations: [
            createOp(text: '冲突的文本。'),
            fresh,
          ],
        ),
      );

      expect(result.appended, [sameContent(fresh)]);
      expect(result.conflicts, hasLength(1));
      expect(result.hasConflicts, isTrue);
      expect((await exchange.fetch(scope: scope())).length, 2);
    });

    test(
      'a divergent duplicate inside one batch keeps the first variant',
      () async {
        final exchange = MemoryJournalExchange();

        final result = committed(
          await exchange.publish(
            scope: scope(),
            operations: [
              createOp(text: '批次里的第一版。'),
              createOp(text: '批次里的第二版。'),
            ],
          ),
        );

        expect(result.appended, hasLength(1));
        expect(
          result.conflicts.single.kind,
          JournalRefusalKind.operationIdCollision,
        );
        expect(result.conflicts.single.incoming.text, '批次里的第二版。');
        expect(result.conflicts.single.accepted!.text, '批次里的第一版。');
        expect(
          (await exchange.fetch(scope: scope())).operations.single.text,
          '批次里的第一版。',
        );
      },
    );

    test('both divergent variants stay visible to the caller', () async {
      final exchange = MemoryJournalExchange();
      final mine = createOp(text: '我的版本。');
      final theirs = createOp(text: '对方的版本。');
      await exchange.publish(scope: scope(), operations: [mine]);

      final result = committed(
        await exchange.publish(scope: scope(), operations: [theirs]),
      );
      final conflict = result.conflicts.single;
      final snapshot = await exchange.fetch(scope: scope());

      expect(
        {conflict.incoming.text, conflict.accepted!.text},
        {'我的版本。', '对方的版本。'},
      );
      expect(snapshot.operations.single.text, '我的版本。');
    });
  });

  group('whole-batch validation', () {
    test(
      'a wrong-scope operation refuses the batch with no partial append',
      () async {
        final exchange = MemoryJournalExchange();
        final good = createOp();
        final wrong = createOp(
          operationId: 'op-foreign',
          notebookId: 'nb-other',
          epochId: 'ep-other',
        );

        final result = rejected(
          await exchange.publish(scope: scope(), operations: [good, wrong]),
        );

        expect(result.appendedAny, isFalse);
        expect(result.refusals.single.kind, JournalRefusalKind.outOfScope);
        expect(result.refusals.single.incoming, sameContent(wrong));
        expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
      },
    );

    test('another epoch of the same notebook is out of scope', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(
        scope: scope(epochId: 'ep-02'),
        operations: [createOp(epochId: 'ep-02')],
      );

      final result = rejected(
        await exchange.publish(
          scope: scope(),
          operations: [
            createOp(),
            createOp(operationId: 'op-a2', epochId: 'ep-02'),
          ],
        ),
      );

      expect(result.refusals.single.kind, JournalRefusalKind.outOfScope);
      expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
      expect((await exchange.fetch(scope: scope(epochId: 'ep-02'))).length, 1);
    });

    test(
      'an invalid operation refuses the batch with no partial append',
      () async {
        final exchange = MemoryJournalExchange();
        final good = createOp();
        final invalid = _MangledOperation();

        final result = rejected(
          await exchange.publish(scope: scope(), operations: [good, invalid]),
        );

        expect(
          result.refusals.single.kind,
          JournalRefusalKind.invalidOperation,
        );
        expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
      },
    );

    test('a refused batch leaves an existing journal untouched', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(scope: scope(), operations: [createOp()]);

      await exchange.publish(
        scope: scope(),
        operations: [
          reviseOp(),
          createOp(notebookId: 'nb-other'),
        ],
      );

      final snapshot = await exchange.fetch(scope: scope());
      expect(snapshot.length, 1);
      expect(snapshot.byOperationId('op-b1'), isNull);
    });
  });

  group('isolation', () {
    test('notebooks do not see each other', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(
        scope: scope(notebookId: 'nb-one'),
        operations: [createOp(notebookId: 'nb-one')],
      );
      await exchange.publish(
        scope: scope(notebookId: 'nb-two'),
        operations: [createOp(notebookId: 'nb-two', text: '另一本日记。')],
      );

      expect(
        (await exchange.fetch(scope: scope(notebookId: 'nb-one'))).length,
        1,
      );
      expect(
        (await exchange.fetch(scope: scope(notebookId: 'nb-two'))).length,
        1,
      );
      expect(
        (await exchange.fetch(scope: scope(notebookId: 'nb-two')))
            .operations
            .single
            .text,
        '另一本日记。',
      );
      expect(exchange.scopes, hasLength(2));
    });

    test('epochs of one notebook are isolated', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(
        scope: scope(epochId: 'ep-01'),
        operations: [createOp(epochId: 'ep-01')],
      );

      expect(
        (await exchange.fetch(scope: scope(epochId: 'ep-02'))).isEmpty,
        isTrue,
      );
      // The same operation id is free in another epoch of the same notebook.
      final result = committed(
        await exchange.publish(
          scope: scope(epochId: 'ep-02'),
          operations: [createOp(epochId: 'ep-02', text: '新纪元的第一篇。')],
        ),
      );
      expect(result.appended, hasLength(1));
    });
  });

  group('detached reads', () {
    test('a snapshot does not change when the exchange changes', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(scope: scope(), operations: [createOp()]);
      final before = await exchange.fetch(scope: scope());
      final canonicalBefore = before.canonicalForm;

      await exchange.publish(scope: scope(), operations: [reviseOp()]);

      expect(before.length, 1);
      expect(before.canonicalForm, canonicalBefore);
      expect((await exchange.fetch(scope: scope())).length, 2);
    });

    test('snapshot lists are immutable', () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(scope: scope(), operations: [createOp()]);
      final snapshot = await exchange.fetch(scope: scope());

      expect(() => snapshot.operations.add(reviseOp()), throwsA(anything));
      expect(
        () => snapshot.operationsForEntry('entry-77').clear(),
        throwsA(anything),
      );
    });

    test('snapshot identity ignores arrival order', () async {
      final first = MemoryJournalExchange();
      final second = MemoryJournalExchange();
      await first.publish(scope: scope(), operations: [createOp(), reviseOp()]);
      await second.publish(
        scope: scope(),
        operations: [reviseOp(), createOp()],
      );

      final a = await first.fetch(scope: scope());
      final b = await second.fetch(scope: scope());

      expect(a, b);
      expect(a.operations, isNot(b.operations));
    });
  });

  group('concurrent and out-of-order exchange', () {
    test('overlapping publishes keep both writers', () async {
      final release = Completer<void>();
      final exchange = MemoryJournalExchange(gate: () => release.future);

      final alpha = exchange.publish(
        scope: scope(),
        operations: [createOp(actorId: 'dev-alpha')],
      );
      final beta = exchange.publish(
        scope: scope(),
        operations: [
          createOp(
            operationId: 'op-b1',
            actorId: 'dev-beta',
            entryId: 'entry-78',
            text: '设备乙写下的另一篇。',
          ),
        ],
      );
      release.complete();

      final results = await Future.wait([alpha, beta]);
      final snapshot = await exchange.fetch(scope: scope());

      expect(results.every((r) => r.appendedAny), isTrue);
      expect(snapshot.length, 2);
      expect(snapshot.operations.map((op) => op.actorId).toSet(), {
        'dev-alpha',
        'dev-beta',
      });
    });

    test(
      'a later publish does not drop an earlier overlapping append',
      () async {
        final exchange = MemoryJournalExchange();
        final slow = createOp(actorId: 'dev-alpha');

        final firstBatch = exchange.publish(scope: scope(), operations: [slow]);
        final secondBatch = exchange.publish(
          scope: scope(),
          operations: [reviseOp(actorId: 'dev-beta', sequence: 1)],
        );
        await Future.wait([firstBatch, secondBatch]);

        final snapshot = await exchange.fetch(scope: scope());
        expect(snapshot.length, 2);
        expect(snapshot.byOperationId('op-a1'), sameContent(slow));
      },
    );

    test(
      'delayed and out-of-order delivery converges on the same content',
      () async {
        final exchange = MemoryJournalExchange();
        final create = createOp(sequence: 1);
        final later = reviseOp(sequence: 3);
        final earlier = reviseOp(operationId: 'op-b0', sequence: 2);

        await exchange.publish(scope: scope(), operations: [later]);
        await exchange.publish(scope: scope(), operations: [create]);
        await exchange.publish(scope: scope(), operations: [earlier]);

        final snapshot = await exchange.fetch(scope: scope());

        expect(snapshot.length, 3);
        expect(snapshot.byActorSequence('dev-alpha', 1), sameContent(create));
        expect(snapshot.byActorSequence('dev-alpha', 2), sameContent(earlier));
        expect(snapshot.byActorSequence('dev-alpha', 3), sameContent(later));
      },
    );

    test(
      'no last-writer-wins: a late write never replaces accepted text',
      () async {
        final exchange = MemoryJournalExchange();
        final first = createOp(recordedAt: DateTime.utc(2026, 11, 19, 8));
        await exchange.publish(scope: scope(), operations: [first]);

        final late = createOp(
          text: '一个更晚的时间戳。',
          recordedAt: DateTime.utc(2026, 11, 20, 8),
        );
        final result = committed(
          await exchange.publish(scope: scope(), operations: [late]),
        );

        expect(
          result.conflicts.single.kind,
          JournalRefusalKind.operationIdCollision,
        );
        expect(
          (await exchange.fetch(scope: scope())).operations.single.text,
          '我会考完雅思。',
        );
      },
    );

    test('independent writers with disjoint identities both land', () async {
      final exchange = MemoryJournalExchange();
      final alphaOps = [
        createOp(actorId: 'dev-alpha', sequence: 1, entryId: 'entry-a'),
        reviseOp(
          operationId: 'op-a2',
          actorId: 'dev-alpha',
          sequence: 2,
          entryId: 'entry-a',
          text: '甲修订了一次。',
        ),
      ];
      final betaOps = [
        createOp(
          operationId: 'op-b1',
          actorId: 'dev-beta',
          sequence: 1,
          entryId: 'entry-b',
          text: '乙的日记。',
        ),
      ];

      await Future.wait([
        exchange.publish(scope: scope(), operations: alphaOps),
        exchange.publish(scope: scope(), operations: betaOps),
      ]);

      final snapshot = await exchange.fetch(scope: scope());
      expect(snapshot.length, 3);
      expect(snapshot.operationsForEntry('entry-a'), hasLength(2));
      expect(snapshot.operationsForEntry('entry-b'), hasLength(1));
    });
  });

  group('failure handling', () {
    test('a failed publish changes neither input nor shared state', () async {
      var calls = 0;
      final exchange = MemoryJournalExchange(
        gate: () async {
          calls++;
          throw StateError('network down');
        },
      );
      final input = [createOp(), reviseOp()];
      final inputJson = input.map((op) => op.canonicalForm).toList();

      await expectLater(
        exchange.publish(scope: scope(), operations: input),
        throwsA(isA<StateError>()),
      );

      expect(calls, 1);
      expect(input.map((op) => op.canonicalForm).toList(), inputJson);
      expect(input, hasLength(2));
      expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
      expect(exchange.scopes, isEmpty);
    });

    test(
      'a failed publish leaves earlier accepted operations intact',
      () async {
        var publishes = 0;
        final exchange = MemoryJournalExchange(
          gate: () async {
            publishes++;
            if (publishes == 2) throw StateError('network down');
          },
        );
        final accepted = createOp();
        await exchange.publish(scope: scope(), operations: [accepted]);

        await expectLater(
          exchange.publish(scope: scope(), operations: [reviseOp()]),
          throwsA(isA<StateError>()),
        );

        final snapshot = await exchange.fetch(scope: scope());
        expect(snapshot.operations, [sameContent(accepted)]);
        expect(snapshot.byOperationId('op-b1'), isNull);
      },
    );

    test('publish never mutates the caller operation objects', () async {
      final exchange = MemoryJournalExchange();
      final operation = createOp();
      final before = operation.canonicalForm;

      await exchange.publish(scope: scope(), operations: [operation]);
      await exchange.publish(scope: scope(), operations: [operation]);

      expect(operation.canonicalForm, before);
      expect(operation.text, '我会考完雅思。');
      // The exchange stores its own decoded value, not the submitted object.
      expect(
        (await exchange.fetch(scope: scope())).operations.single,
        isNot(same(operation)),
      );
      expect(
        (await exchange.fetch(scope: scope())).operations.single.canonicalForm,
        before,
      );
    });
  });

  group('admitted representation', () {
    test('a source object changed after publish cannot alter the journal',
        () async {
      final exchange = MemoryJournalExchange();
      final source = _DriftingCreate()..text = '先写下的内容。';
      await exchange.publish(scope: scope(), operations: [source]);

      final before = await exchange.fetch(scope: scope());
      final canonicalBefore = before.canonicalForm;

      source.text = '发布之后改掉的内容。';
      source.createdOn = CivilDate(2026, 11, 20);

      final after = await exchange.fetch(scope: scope());
      expect(after.canonicalForm, canonicalBefore);
      expect(after.operations.single.text, '先写下的内容。');
      expect(
        (after.operations.single as JournalCreateEntry).createdOn,
        CivilDate(2026, 11, 19),
      );
      expect((await exchange.fetch(scope: scope())).length, 1);
    });

    test('a source object changed after publish cannot force a collision',
        () async {
      final exchange = MemoryJournalExchange();
      final source = _DriftingCreate()..text = '原始文本。';
      await exchange.publish(scope: scope(), operations: [source]);

      // Drift the source into different content, then replay it. Identity is
      // judged on the stored value, so this is a divergent collision, not a
      // silent overwrite of accepted text.
      source.text = '漂移之后的文本。';
      final result = committed(
        await exchange.publish(scope: scope(), operations: [source]),
      );

      expect(
        result.conflicts.single.kind,
        JournalRefusalKind.operationIdCollision,
      );
      expect(result.conflicts.single.incoming.text, '漂移之后的文本。');
      expect(result.conflicts.single.accepted!.text, '原始文本。');
      expect(
        (await exchange.fetch(scope: scope())).operations.single.text,
        '原始文本。',
      );
    });

    test('the stored operation is a decode round trip, not the submitted one',
        () async {
      final exchange = MemoryJournalExchange();
      final source = createOp();
      await exchange.publish(scope: scope(), operations: [source]);

      final stored = (await exchange.fetch(scope: scope())).operations.single;

      expect(stored, isNot(same(source)));
      expect(stored, isA<JournalCreateEntry>());
      expect(
        JournalOperation.fromJson(stored.toJson()).canonicalForm,
        source.canonicalForm,
      );
      expect(stored.canonicalForm, source.canonicalForm);
      expect(stored.runtimeType, JournalCreateEntry);
      // Identity is stable across every read of the same exchange.
      expect(
        (await exchange.fetch(scope: scope())).operations.single,
        sameContent(stored),
      );
    });

    test('a stored nested civil date is the decoded value, not a shared one',
        () async {
      final exchange = MemoryJournalExchange();
      final source = createOp(createdOn: '2026-02-28');
      await exchange.publish(scope: scope(), operations: [source]);

      final stored =
          (await exchange.fetch(scope: scope())).operations.single
              as JournalCreateEntry;
      final original = source.createdOn;

      expect(stored.createdOn, CivilDate(2026, 2, 28));
      expect(stored.createdOn, isNot(same(original)));
      expect(stored.createdOn.text, '2026-02-28');
    });

    test('an operation whose encoding is invalid is refused with a clean reason',
        () async {
      final exchange = MemoryJournalExchange();

      final result = rejected(
        await exchange.publish(
          scope: scope(),
          operations: [_MangledOperation()],
        ),
      );

      final refusal = result.refusals.single;
      expect(refusal.kind, JournalRefusalKind.invalidOperation);
      expect(refusal.reason, contains('is not a valid journal operation'));
      // The reason quotes the identifier only; it never leaks diary text.
      expect(refusal.reason, isNot(contains('看起来正常的文本')));
      expect(refusal.reason, contains('op-mangled'));
      expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
    });

    test('a rejected operation with an unreadable identifier is still refused',
        () async {
      final exchange = MemoryJournalExchange();

      final result = rejected(
        await exchange.publish(
          scope: scope(),
          operations: [_ThrowingIdMangledOperation()],
        ),
      );

      final refusal = result.refusals.single;
      expect(refusal.kind, JournalRefusalKind.invalidOperation);
      expect(refusal.reason, contains('unidentified'));
      expect(refusal.reason, isNot(contains('未解码的文本')));
    });

    test('a replay and a collision differ only in what was already accepted',
        () async {
      final exchange = MemoryJournalExchange();
      await exchange.publish(scope: scope(), operations: [createOp()]);

      final replay = committed(
        await exchange.publish(scope: scope(), operations: [createOp()]),
      );
      final collision = committed(
        await exchange.publish(
          scope: scope(),
          operations: [createOp(text: '不同的内容。')],
        ),
      );

      expect(replay.isNoOp, isTrue);
      expect(replay.replayed, hasLength(1));
      expect(replay.conflicts, isEmpty);
      expect(collision.isNoOp, isTrue);
      expect(collision.replayed, isEmpty);
      expect(collision.conflicts, hasLength(1));
      expect((await exchange.fetch(scope: scope())).length, 1);
    });

    test('scope is judged on the decoded value, not the submitted object',
        () async {
      final exchange = MemoryJournalExchange();
      final source = _DriftingScopeCreate();

      // The object reports the requested scope while it is validated, then
      // claims another notebook. Only the decoded value is scope-checked, so
      // the batch is admitted under the scope its content actually names.
      final result = await exchange.publish(
        scope: scope(),
        operations: [source],
      );

      expect(result, isA<JournalPublishRejected>());
      final refusal = (result as JournalPublishRejected).refusals.single;
      expect(refusal.kind, JournalRefusalKind.outOfScope);
      expect(refusal.reason, contains('nb-drifted'));
      expect((await exchange.fetch(scope: scope())).isEmpty, isTrue);
      expect(
        (await exchange.fetch(scope: scope(notebookId: 'nb-drifted'))).isEmpty,
        isTrue,
      );
    });
  });

  group('Unicode', () {
    test('text survives publish and fetch byte for byte', () async {
      const text =
          '今天的日记：Emoji 😀, 中文, кириллица, ﷽, e\u0301, \u{1F1E8}\u{1F1F3}';
      final exchange = MemoryJournalExchange();
      final operation = createOp(text: text);

      await exchange.publish(scope: scope(), operations: [operation]);
      final snapshot = await exchange.fetch(scope: scope());

      expect(snapshot.operations.single.text, text);
      expect(snapshot.operations.single.text.length, text.length);
      expect(snapshot.operations.single.canonicalForm, operation.canonicalForm);
    });

    test('replaying Unicode text is still a no-op', () async {
      const text = '重复的日记：😀😀😀';
      final exchange = MemoryJournalExchange();
      await exchange.publish(
        scope: scope(),
        operations: [createOp(text: text)],
      );

      final replay = committed(
        await exchange.publish(
          scope: scope(),
          operations: [createOp(text: text)],
        ),
      );

      expect(replay.isNoOp, isTrue);
      expect(
        (await exchange.fetch(scope: scope())).operations.single.text,
        text,
      );
    });
  });
}

/// An operation whose encoding is not a valid journal document, used to check
/// that the exchange re-validates what it is handed.
class _MangledOperation extends JournalCreateEntry {
  _MangledOperation()
    : super(
        notebookId: _notebook,
        epochId: _epoch,
        actorId: 'dev-mangled',
        sequence: 1,
        operationId: 'op-mangled',
        recordedAt: DateTime.utc(2026, 11, 19, 12),
        entryId: 'entry-mangled',
        text: '看起来正常的文本。',
        createdOn: CivilDate(2026, 11, 19),
      );

  @override
  Map<String, Object?> toJson() => super.toJson()..remove('entryId');
}

/// A caller subclass with live, overridable state.
///
/// `JournalOperation` declares `final` fields, but Dart lets a subclass
/// override the implicit getter, so a stored instance would keep reporting
/// whatever the caller sets next. The exchange must never retain one.
class _DriftingCreate extends JournalCreateEntry {
  _DriftingCreate()
    : _text = '初始文本。',
      _createdOn = CivilDate(2026, 11, 19),
      super(
        notebookId: _notebook,
        epochId: _epoch,
        actorId: 'dev-drifting',
        sequence: 1,
        operationId: 'op-drifting',
        recordedAt: DateTime.utc(2026, 11, 19, 12),
        entryId: 'entry-drifting',
        text: '初始文本。',
        createdOn: CivilDate(2026, 11, 19),
      );

  String _text;
  CivilDate _createdOn;

  set text(String value) => _text = value;

  set createdOn(CivilDate value) => _createdOn = value;

  @override
  String get text => _text;

  @override
  CivilDate get createdOn => _createdOn;
}

/// A subclass whose scope getter claims the requested notebook while its own
/// encoding names a different one.
class _DriftingScopeCreate extends JournalCreateEntry {
  _DriftingScopeCreate()
    : super(
        notebookId: _notebook,
        epochId: _epoch,
        actorId: 'dev-scope',
        sequence: 1,
        operationId: 'op-scope',
        recordedAt: DateTime.utc(2026, 11, 19, 12),
        entryId: 'entry-scope',
        text: '作用域漂移。',
        createdOn: CivilDate(2026, 11, 19),
      );

  @override
  String get notebookId => _notebook;

  @override
  Map<String, Object?> toJson() =>
      super.toJson()..['notebookId'] = 'nb-drifted';
}

/// An invalid operation whose identifier getter throws, so a diagnostic must
/// not depend on reading it.
///
/// The getter only throws once construction is done, because the base
/// constructor validates the identifier it was given.
class _ThrowingIdMangledOperation extends JournalCreateEntry {
  _ThrowingIdMangledOperation()
    : super(
        notebookId: _notebook,
        epochId: _epoch,
        actorId: 'dev-throwing',
        sequence: 1,
        operationId: 'op-throwing',
        recordedAt: DateTime.utc(2026, 11, 19, 12),
        entryId: 'entry-throwing',
        text: '未解码的文本。',
        createdOn: CivilDate(2026, 11, 19),
      ) {
    _armed = true;
  }

  bool _armed = false;

  @override
  String get operationId =>
      _armed ? throw StateError('identifier unavailable') : 'op-throwing';

  @override
  Map<String, Object?> toJson() => super.toJson()..remove('entryId');
}

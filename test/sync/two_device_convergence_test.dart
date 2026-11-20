import 'dart:convert';

import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_replay.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/sync/journal_exchange.dart';
import 'package:diary008/sync/journal_scope.dart';
import 'package:diary008/sync/memory_journal_exchange.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-8f2c';
const _epoch = 'ep-01';
const _volume = 3;
const _sharedEntryId = 'entry-shared';

final JournalScope _scope = JournalScope(
  notebookId: _notebook,
  epochId: _epoch,
);

DateTime _at(int minute) => DateTime.utc(2026, 11, 19, 9, minute);

/// The notebook both peers start from, before either writes offline.
Notebook _baseNotebook() => Notebook(
  volume: _volume,
  volumeName: '第三卷',
  entries: [
    JournalEntry(
      id: _sharedEntryId,
      text: '原有的共享条目。',
      createdAt: DateTime.utc(2026, 11, 1, 9),
      createdOn: DateTime.utc(2026, 11, 1),
      due: DateTime.utc(2026, 12, 1),
      status: EntryStatus.pending,
    ),
  ],
);

/// One device: a local journal, a local actor id, and a base notebook.
///
/// The peer owns no transport. It publishes what it has written and pulls what
/// the exchange holds, exactly as a client would after reconnecting.
class _Peer {
  _Peer({required this.actorId, required this.base})
    : journal = Journal(notebookId: _notebook, epochId: _epoch);

  final String actorId;
  final Notebook base;
  final Journal journal;

  int _nextSequence = 1;

  JournalCreateEntry create({
    required String operationId,
    required String entryId,
    required String text,
    required int minute,
  }) {
    final operation = JournalCreateEntry(
      notebookId: _notebook,
      epochId: _epoch,
      actorId: actorId,
      sequence: _nextSequence++,
      operationId: operationId,
      recordedAt: _at(minute),
      entryId: entryId,
      text: text,
      createdOn: CivilDate(2026, 11, 19),
    );
    _admitLocally(operation);
    return operation;
  }

  JournalReviseEntry revise({
    required String operationId,
    required String text,
    required int minute,
    String entryId = _sharedEntryId,
  }) {
    final operation = JournalReviseEntry(
      notebookId: _notebook,
      epochId: _epoch,
      actorId: actorId,
      sequence: _nextSequence++,
      operationId: operationId,
      recordedAt: _at(minute),
      entryId: entryId,
      text: text,
    );
    _admitLocally(operation);
    return operation;
  }

  void _admitLocally(JournalOperation operation) {
    final result = journal.admit(operation);
    expect(
      result.admission,
      JournalAdmission.appended,
      reason: 'local edit ${operation.operationId} must be accepted offline',
    );
  }

  /// Publishes everything this peer has written. Replays are no-ops, so
  /// republishing after a reconnect is safe.
  Future<JournalPublishCommitted> publishAll(JournalExchange exchange) async {
    final result = await exchange.publish(
      scope: _scope,
      operations: journal.operations,
    );
    expect(result, isA<JournalPublishCommitted>());
    return result as JournalPublishCommitted;
  }

  /// Admits whatever the exchange holds. Already-known operations are replays.
  Future<void> pull(JournalExchange exchange) async {
    final snapshot = await exchange.fetch(scope: _scope);
    for (final operation in snapshot.operations) {
      journal.admit(operation);
    }
  }

  JournalReplayResult project() => JournalReplay.project(
    notebookId: _notebook,
    epochId: _epoch,
    base: base,
    journal: journal,
  );
}

/// Content of a peer's accepted journal, independent of admission order.
String _journalKey(Journal journal) {
  final forms =
      journal.operations.map((operation) => operation.canonicalForm).toList()
        ..sort();
  return forms.join('\n');
}

/// Structural form of a projected notebook, for exact comparison.
String _notebookKey(Notebook notebook) => jsonEncode(notebook.toJson());

/// Conflict outcome, independent of conflict list order.
String _conflictKey(JournalReplayResult result) {
  final keys =
      result.conflicts
          .map(
            (conflict) =>
                '${conflict.kind.name}:${conflict.operation.operationId}',
          )
          .toList()
        ..sort();
  return keys.join('\n');
}

/// Every entry text in a notebook, current entries and archives alike.
List<String> _texts(Notebook notebook) => [
  for (final entry in notebook.entries) entry.text,
  for (final archive in notebook.archives)
    for (final entry in archive.entries) entry.text,
];

/// An exchange that stores the batch and then reports failure, which is what a
/// lost response looks like to the client that sent it.
class _LostResponseExchange implements JournalExchange {
  _LostResponseExchange(this.inner);

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
  group('two-device convergence', () {
    test(
      'peers that edit offline converge on one projected notebook',
      () async {
        final exchange = MemoryJournalExchange();
        final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
        final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());

        alpha.create(
          operationId: 'op-a-create',
          entryId: 'entry-alpha',
          text: '甲在离线时写下的第一篇。',
          minute: 1,
        );
        beta.create(
          operationId: 'op-b-create',
          entryId: 'entry-beta',
          text: '乙在离线时写下的第一篇。',
          minute: 2,
        );

        await alpha.publishAll(exchange);
        await beta.publishAll(exchange);
        await alpha.pull(exchange);
        await beta.pull(exchange);

        final projectedAlpha = alpha.project();
        final projectedBeta = beta.project();

        expect(_journalKey(alpha.journal), _journalKey(beta.journal));
        expect(
          _notebookKey(projectedAlpha.notebook),
          _notebookKey(projectedBeta.notebook),
        );
        expect(_conflictKey(projectedAlpha), _conflictKey(projectedBeta));
        expect(projectedAlpha.hasConflicts, isFalse);
        expect(
          _texts(projectedAlpha.notebook),
          containsAll(<String>['原有的共享条目。', '甲在离线时写下的第一篇。', '乙在离线时写下的第一篇。']),
        );
      },
    );

    test(
      'exchanging the same batches in reverse order converges identically',
      () async {
        Future<({String notebook, String journal, int length})> run({
          required bool reverse,
        }) async {
          final exchange = MemoryJournalExchange();
          final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
          final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());
          alpha.create(
            operationId: 'op-a-create',
            entryId: 'entry-alpha',
            text: '甲的第一篇。',
            minute: 1,
          );
          beta.revise(operationId: 'op-b-revise', text: '乙的补充。', minute: 2);

          final order = reverse ? [beta, alpha] : [alpha, beta];
          for (final peer in order) {
            await peer.publishAll(exchange);
          }
          for (final peer in order.reversed) {
            await peer.pull(exchange);
          }
          return (
            notebook: _notebookKey(alpha.project().notebook),
            journal: _journalKey(alpha.journal),
            length: alpha.journal.length,
          );
        }

        final forward = await run(reverse: false);
        final backward = await run(reverse: true);

        expect(backward.notebook, forward.notebook);
        expect(backward.journal, forward.journal);
        // Both batches really landed in both orders, so the equality above is
        // about ordering rather than about two empty runs.
        expect(forward.length, 2);
        expect(backward.length, 2);
      },
    );

    test('a delayed batch is delivered without losing either side', () async {
      final exchange = MemoryJournalExchange();
      final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
      final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());

      alpha.create(
        operationId: 'op-a-create',
        entryId: 'entry-alpha',
        text: '甲写下的内容，迟迟才送达。',
        minute: 1,
      );
      beta.create(
        operationId: 'op-b-create',
        entryId: 'entry-beta',
        text: '乙先送达的内容。',
        minute: 2,
      );

      // Beta's batch arrives and is read first; alpha's batch is held back.
      await beta.publishAll(exchange);
      await beta.pull(exchange);
      await alpha.pull(exchange);

      expect((await exchange.fetch(scope: _scope)).length, 1);

      await alpha.publishAll(exchange);
      await alpha.pull(exchange);
      await beta.pull(exchange);

      final projectedAlpha = alpha.project();
      final projectedBeta = beta.project();

      expect(_journalKey(alpha.journal), _journalKey(beta.journal));
      expect(
        _notebookKey(projectedAlpha.notebook),
        _notebookKey(projectedBeta.notebook),
      );
      expect(
        _texts(projectedAlpha.notebook),
        containsAll(<String>['甲写下的内容，迟迟才送达。', '乙先送达的内容。']),
      );
    });

    test('a retry after a lost response converges on one operation', () async {
      final inner = MemoryJournalExchange();
      final transport = _LostResponseExchange(inner);
      final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
      final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());

      alpha.create(
        operationId: 'op-a-create',
        entryId: 'entry-alpha',
        text: '重试之后只应存在一次。',
        minute: 1,
      );

      await expectLater(
        alpha.publishAll(transport),
        throwsA(isA<StateError>()),
      );
      final retried = await alpha.publishAll(transport);

      expect(retried.isNoOp, isTrue);
      expect(retried.replayed.single.text, '重试之后只应存在一次。');
      expect((await inner.fetch(scope: _scope)).length, 1);

      await beta.pull(inner);
      await beta.publishAll(inner);
      await alpha.pull(inner);

      expect(_journalKey(alpha.journal), _journalKey(beta.journal));
      expect(
        _notebookKey(alpha.project().notebook),
        _notebookKey(beta.project().notebook),
      );
      expect(
        _texts(alpha.project().notebook).where((text) => text == '重试之后只应存在一次。'),
        hasLength(1),
      );
    });

    test('a duplicate delivery is an idempotent no-op', () async {
      final exchange = MemoryJournalExchange();
      final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
      final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());

      alpha.create(
        operationId: 'op-a-create',
        entryId: 'entry-alpha',
        text: '重复投递的内容。',
        minute: 1,
      );

      await alpha.publishAll(exchange);
      final duplicate = await alpha.publishAll(exchange);
      await alpha.publishAll(exchange);

      expect(duplicate.isNoOp, isTrue);
      expect(duplicate.conflicts, isEmpty);
      expect((await exchange.fetch(scope: _scope)).length, 1);

      await beta.pull(exchange);
      expect(_journalKey(alpha.journal), _journalKey(beta.journal));
    });

    test(
      'competing revisions to one entry keep both texts on both peers',
      () async {
        final exchange = MemoryJournalExchange();
        final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
        final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());

        alpha.revise(operationId: 'op-a-revise', text: '甲对共享条目的补充。', minute: 1);
        beta.revise(operationId: 'op-b-revise', text: '乙对共享条目的补充。', minute: 2);

        await alpha.publishAll(exchange);
        await beta.publishAll(exchange);
        await alpha.pull(exchange);
        await beta.pull(exchange);

        final projectedAlpha = alpha.project();
        final projectedBeta = beta.project();

        expect(_journalKey(alpha.journal), _journalKey(beta.journal));
        expect(
          _notebookKey(projectedAlpha.notebook),
          _notebookKey(projectedBeta.notebook),
        );
        expect(_conflictKey(projectedAlpha), _conflictKey(projectedBeta));

        // Both competing edits stay visible; neither is silently dropped.
        expect(
          _texts(projectedAlpha.notebook),
          containsAll(<String>['甲对共享条目的补充。', '乙对共享条目的补充。']),
        );
        expect(
          projectedAlpha.conflicts
              .where(
                (conflict) =>
                    conflict.kind == JournalReplayConflictKind.competingActors,
              )
              .single
              .related
              .map((operation) => operation.text),
          contains('乙对共享条目的补充。'),
        );
      },
    );

    test(
      'a same-scope identity collision stays explicit and keeps both texts',
      () async {
        final exchange = MemoryJournalExchange();
        final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
        final beta = _Peer(actorId: 'dev-beta', base: _baseNotebook());

        // Both devices independently mint the same identity for different text.
        alpha.create(
          operationId: 'op-collide',
          entryId: 'entry-race',
          text: '甲写下的版本。',
          minute: 1,
        );
        beta.create(
          operationId: 'op-collide',
          entryId: 'entry-race',
          text: '乙写下的版本。',
          minute: 2,
        );

        await alpha.publishAll(exchange);
        final refusal = await beta.publishAll(exchange);

        expect(refusal.hasConflicts, isTrue);
        expect(refusal.appended, isEmpty);
        final conflict = refusal.conflicts.single;
        expect(conflict.kind, JournalRefusalKind.operationIdCollision);
        expect(conflict.accepted!.text, '甲写下的版本。');
        expect(conflict.incoming.text, '乙写下的版本。');

        // The accepted text is unchanged and the collision is not swallowed.
        final stored = (await exchange.fetch(scope: _scope)).operations.single;
        expect(stored.text, '甲写下的版本。');

        await alpha.pull(exchange);
        await beta.pull(exchange);

        // A reused identity is never merged, so each peer keeps the text it
        // admitted locally and both texts survive somewhere in the system. The
        // collision is reported instead of being resolved by overwriting one.
        expect(alpha.journal.operations.single.text, '甲写下的版本。');
        expect(beta.journal.operations.single.text, '乙写下的版本。');
        expect(
          {conflict.accepted!.text, conflict.incoming.text},
          {'甲写下的版本。', '乙写下的版本。'},
        );
        expect(
          _texts(alpha.project().notebook),
          containsAll(<String>['甲写下的版本。', '原有的共享条目。']),
        );
        expect(_texts(alpha.project().notebook), isNot(contains('乙写下的版本。')));
        expect(_texts(beta.project().notebook), contains('乙写下的版本。'));
      },
    );
  });

  group('no lasting side effects', () {
    test('an exchange holds state only for its own instance', () async {
      final first = MemoryJournalExchange();
      final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
      alpha.create(
        operationId: 'op-a-create',
        entryId: 'entry-alpha',
        text: '只属于第一个交换实例。',
        minute: 1,
      );
      await alpha.publishAll(first);

      final second = MemoryJournalExchange();
      expect(second.scopes, isEmpty);
      expect((await second.fetch(scope: _scope)).isEmpty, isTrue);
      expect(first.scopes, {_scope});
    });

    test(
      'a refused batch leaves the exchange and the caller untouched',
      () async {
        final exchange = MemoryJournalExchange();
        final alpha = _Peer(actorId: 'dev-alpha', base: _baseNotebook());
        final accepted = alpha.create(
          operationId: 'op-a-create',
          entryId: 'entry-alpha',
          text: '已接受的内容。',
          minute: 1,
        );
        await alpha.publishAll(exchange);

        final before = (await exchange.fetch(scope: _scope)).canonicalForm;
        final foreign = JournalCreateEntry(
          notebookId: 'nb-other',
          epochId: 'ep-other',
          actorId: 'dev-alpha',
          sequence: 9,
          operationId: 'op-foreign',
          recordedAt: _at(30),
          entryId: 'entry-foreign',
          text: '不属于这个范围。',
          createdOn: CivilDate(2026, 11, 19),
        );
        final acceptedBefore = accepted.canonicalForm;

        final refused = await exchange.publish(
          scope: _scope,
          operations: [
            alpha.create(
              operationId: 'op-a-second',
              entryId: 'entry-alpha-two',
              text: '与外来操作同批。',
              minute: 2,
            ),
            foreign,
          ],
        );

        expect(refused, isA<JournalPublishRejected>());
        expect((await exchange.fetch(scope: _scope)).canonicalForm, before);
        expect(accepted.canonicalForm, acceptedBefore);
        expect(
          foreign.canonicalForm,
          JournalOperation.fromJson(foreign.toJson()).canonicalForm,
        );
      },
    );

    test('projection is pure and does not mutate the base notebook', () async {
      final exchange = MemoryJournalExchange();
      final base = _baseNotebook();
      final baseKey = _notebookKey(base);
      final alpha = _Peer(actorId: 'dev-alpha', base: base);

      alpha.create(
        operationId: 'op-a-create',
        entryId: 'entry-alpha',
        text: '投影不会改动基座。',
        minute: 1,
      );
      await alpha.publishAll(exchange);

      final first = alpha.project();
      final second = alpha.project();

      expect(_notebookKey(base), baseKey);
      expect(_notebookKey(first.notebook), _notebookKey(second.notebook));
      expect(_conflictKey(first), _conflictKey(second));
      expect(alpha.journal.operations, hasLength(1));
    });
  });
}

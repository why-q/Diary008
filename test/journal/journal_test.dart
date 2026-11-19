import 'dart:convert';

import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-8f2c';
const _epoch = 'ep-01';

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

Journal journal() => Journal(notebookId: _notebook, epochId: _epoch);

void main() {
  group('operation encoding', () {
    test('create round trips through JSON with Unicode text intact', () {
      const text = '今天的日记：Emoji 😀, 中文, и кириллица, ﷽, e\u0301';
      final original = createOp(text: text);

      final decoded = JournalOperation.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );

      expect(decoded, isA<JournalCreateEntry>());
      expect(decoded.text, text);
      expect((decoded as JournalCreateEntry).createdOn.text, '2026-11-19');
      expect(
        decoded.recordedAt,
        DateTime.utc(2026, 11, 19, 12, 45, 7, 123, 456),
      );
      expect(decoded.recordedAt.isUtc, isTrue);
      expect(decoded.canonicalForm, original.canonicalForm);
    });

    test('revise round trips and carries no civil date', () {
      final original = reviseOp();
      final decoded = JournalOperation.fromJson(original.toJson());

      expect(decoded, isA<JournalReviseEntry>());
      expect(decoded.toJson().containsKey('createdOn'), isFalse);
      expect(decoded.canonicalForm, original.canonicalForm);
    });

    test('encoding does not depend on the local time zone', () {
      // Same UTC instant expressed through a local-zone view of it.
      final utc = DateTime.utc(2026, 3, 8, 6, 30);
      final local = utc.toLocal();
      final op = createOp(recordedAt: utc);

      expect(op.toJson()['recordedAt'], '2026-03-08T06:30:00.000Z');
      expect(
        () => createOp(recordedAt: local),
        throwsA(isA<JournalFormatException>()),
      );
      expect(op.createdOn.text, '2026-11-19');
    });

    test('rejects a non-UTC instant in stored JSON', () {
      final json = createOp().toJson()
        ..['recordedAt'] = '2026-11-19T12:45:07+08:00';

      expect(
        () => JournalOperation.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('malformed and unsupported data', () {
    test('rejects an unsupported operation schema version', () {
      final json = createOp().toJson()..['schemaVersion'] = 2;

      expect(
        () => JournalOperation.fromJson(json),
        throwsA(
          isA<JournalFormatException>().having(
            (e) => e.field,
            'field',
            'operation.schemaVersion',
          ),
        ),
      );
    });

    test('rejects an unknown operation kind', () {
      final json = createOp().toJson()..['kind'] = 'delete';

      expect(
        () => JournalOperation.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects unknown and missing keys', () {
      final extra = createOp().toJson()..['mergeWinner'] = true;
      final missing = createOp().toJson()..remove('entryId');

      expect(
        () => JournalOperation.fromJson(extra),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => JournalOperation.fromJson(missing),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects a create payload key on a revise operation', () {
      final json = reviseOp().toJson()..['createdOn'] = '2026-11-19';

      expect(
        () => JournalOperation.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects invalid identity, sequence, and text values', () {
      expect(
        () => createOp(operationId: '12'),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => createOp(actorId: '我有日记'),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => createOp(sequence: 0),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => createOp(text: '   \n\t '),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => createOp(text: 'x' * (journalMaxTextLength + 1)),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => createOp(createdOn: '2026-02-30'),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('rejects an unsupported journal document version', () {
      final document = journal().toJson()..['schemaVersion'] = 99;

      expect(
        () => Journal.fromJson(document),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => Journal.fromJson({'schemaVersion': 1, 'notebookId': _notebook}),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => Journal.fromJson([]),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('admission', () {
    test('appends distinct operations and keeps them in order', () {
      final log = journal();

      expect(log.admit(createOp()).admission, JournalAdmission.appended);
      expect(log.admit(reviseOp()).admission, JournalAdmission.appended);

      expect(log.length, 2);
      expect(log.operations.first, isA<JournalCreateEntry>());
      expect(log.operations.last, isA<JournalReviseEntry>());
      expect(log.operationsForEntry('entry-77').length, 2);
    });

    test('exact replay is idempotent and does not append', () {
      final log = journal();
      final op = createOp();
      log.admit(op);

      final replay = log.admit(createOp());

      expect(replay.admission, JournalAdmission.replayed);
      expect(replay.accepted, isTrue);
      expect(log.length, 1);
      expect(log.operations.single.operationId, 'op-a1');
    });

    test('replay after a JSON round trip is still a replay', () {
      final log = journal();
      log.admit(createOp());
      final stored = Journal.fromJson(jsonDecode(jsonEncode(log.toJson())));

      expect(stored.admit(createOp()).admission, JournalAdmission.replayed);
      expect(stored.length, 1);
    });

    test('reused operation id with different content is a collision', () {
      final log = journal();
      log.admit(createOp());
      final colliding = createOp(text: '完全不同的内容');

      final result = log.admit(colliding);

      expect(result.admission, JournalAdmission.collided);
      expect(result.accepted, isFalse);
      expect(result.conflict!.isCollision, isTrue);
      expect(result.conflict!.conflicting!.text, '我会考完雅思。');
      expect(log.length, 1);
      expect(log.operations.single.text, '我会考完雅思。');
    });

    test('reused actor sequence with different content is a collision', () {
      final log = journal();
      log.admit(createOp());
      final colliding = reviseOp(sequence: 1, entryId: 'entry-77');

      final result = log.admit(colliding);

      expect(result.admission, JournalAdmission.collided);
      expect(result.conflict!.conflicting!.operationId, 'op-a1');
      expect(log.length, 1);
    });

    test(
      'a second create for the same entry is a collision, not a clobber',
      () {
        final log = journal();
        log.admit(createOp());

        final result = log.admit(
          createOp(operationId: 'op-a2', sequence: 2, text: '另一个版本'),
        );

        expect(result.admission, JournalAdmission.collided);
        expect(log.length, 1);
      },
    );

    test('a later revision of an entry is appended, not merged', () {
      final log = journal();
      log.admit(createOp());
      log.admit(reviseOp(actorId: 'dev-beta', sequence: 1));
      log.admit(reviseOp(operationId: 'op-b2', sequence: 3));

      final texts = log
          .operationsForEntry('entry-77')
          .map((op) => op.text)
          .toList();

      expect(texts, ['我会考完雅思。', '我会考完雅思，然后旅行。', '我会考完雅思，然后旅行。']);
    });

    test('retains text-bearing operations that differ only by whitespace', () {
      final log = journal();
      log.admit(createOp());
      log.admit(reviseOp(text: '我会考完雅思。 '));
      log.admit(reviseOp(operationId: 'op-b2', sequence: 3, text: '我会考完雅思。'));

      expect(log.length, 3);
      expect(log.operationsForEntry('entry-77').map((op) => op.text), [
        '我会考完雅思。',
        '我会考完雅思。 ',
        '我会考完雅思。',
      ]);
    });

    test('rejects a foreign notebook without appending', () {
      final log = journal();

      final result = log.admit(createOp(notebookId: 'nb-other'));

      expect(result.admission, JournalAdmission.rejected);
      expect(result.accepted, isFalse);
      expect(log.isEmpty, isTrue);
      expect(log.byOperationId('op-a1'), isNull);
    });

    test('admission does not order operations by wall clock', () {
      final log = journal();
      final later = createOp(recordedAt: DateTime.utc(2026, 11, 20, 1));
      final earlier = reviseOp(recordedAt: DateTime.utc(2026, 1, 1, 0));

      expect(log.admit(later).admission, JournalAdmission.appended);
      expect(log.admit(earlier).admission, JournalAdmission.appended);
      expect(log.operations.map((op) => op.operationId), ['op-a1', 'op-b1']);
    });

    test('rejects a foreign epoch without appending', () {
      final log = journal();

      final result = log.admit(createOp(epochId: 'ep-02'));

      expect(result.admission, JournalAdmission.rejected);
      expect(log.isEmpty, isTrue);
    });

    test('lookups report accepted identity only', () {
      final log = journal();
      log.admit(createOp());

      expect(log.byOperationId('op-a1')!.entryId, 'entry-77');
      expect(log.byActorSequence('dev-alpha', 1)!.operationId, 'op-a1');
      expect(log.byActorSequence('dev-alpha', 2), isNull);
      expect(log.byActorSequence('dev-beta', 1), isNull);
    });
  });

  group('isolation', () {
    test('two journals for different notebooks stay independent', () {
      final alpha = journal();
      final beta = Journal(notebookId: 'nb-other', epochId: _epoch);

      alpha.admit(createOp());
      beta.admit(createOp(notebookId: 'nb-other'));

      expect(alpha.length, 1);
      expect(beta.length, 1);
      expect(
        beta.admit(createOp(notebookId: 'nb-other')).admission,
        JournalAdmission.replayed,
      );
      expect(beta.notebookId, 'nb-other');
    });

    test('a stored journal keeps its own notebook and epoch', () {
      final log = journal();
      log.admit(createOp());
      final restored = Journal.fromJson(jsonDecode(jsonEncode(log.toJson())));

      expect(restored.notebookId, _notebook);
      expect(restored.epochId, _epoch);
      expect(
        restored.admit(createOp(epochId: 'ep-other')).admission,
        JournalAdmission.rejected,
      );
    });

    test('a stored journal rejects an operation from another epoch', () {
      final document = {
        'schemaVersion': journalSchemaVersion,
        'notebookId': _notebook,
        'epochId': _epoch,
        'operations': [createOp(epochId: 'ep-other').toJson()],
      };

      expect(
        () => Journal.fromJson(document),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test(
      'a stored journal rejects duplicate operations instead of merging',
      () {
        final create = createOp();
        final document = {
          'schemaVersion': journalSchemaVersion,
          'notebookId': _notebook,
          'epochId': _epoch,
          'operations': [create.toJson(), create.toJson()],
        };

        expect(
          () => Journal.fromJson(document),
          throwsA(isA<JournalFormatException>()),
        );
      },
    );
  });
}

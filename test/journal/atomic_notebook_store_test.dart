import 'dart:convert';
import 'dart:io';

import 'package:diary008/journal/atomic_notebook_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-4c71';
const _epochId = 'ep-07';
final _now = DateTime.utc(2026, 11, 19, 9, 15, 3);

JournalScope scope({
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalScope(notebookId: notebookId, epochId: epochId);

JournalCreateEntry createOp({
  String operationId = 'op-1',
  int sequence = 1,
  String entryId = 'entry-1',
  String text = '我会考完雅思。',
  String actorId = 'dev-alpha',
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalCreateEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: _now,
  entryId: entryId,
  text: text,
  createdOn: CivilDate.parse('2026-11-19'),
);

JournalReviseEntry reviseOp({
  String operationId = 'op-2',
  int sequence = 2,
  String entryId = 'entry-1',
  String text = '第二稿',
  String actorId = 'dev-alpha',
  String epochId = _epochId,
}) => JournalReviseEntry(
  notebookId: _notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: _now,
  entryId: entryId,
  text: text,
);

Notebook notebookWithEntry({String text = '我会考完雅思。'}) => Notebook(
  volume: 1,
  volumeName: '第一卷',
  entries: [
    JournalEntry(
      id: 'entry-1',
      text: text,
      createdAt: _now,
      createdOn: DateTime.utc(2026, 11, 19),
      due: DateTime.utc(2026, 11, 30),
      status: EntryStatus.pending,
    ),
  ],
);

NotebookEnvelope emptyEnvelope({int revision = 1}) => NotebookEnvelope(
  revision: revision,
  notebook: Notebook.empty(),
  journal: Journal(notebookId: _notebookId, epochId: _epochId),
);

void main() {
  late Directory dir;
  late File envelopeFile;
  late File appNotebookFile;
  late AtomicNotebookStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-envelope-');
    envelopeFile = File('${dir.path}/notebook-envelope.json');
    appNotebookFile = File('${dir.path}/notebook.json');
    store = AtomicNotebookStore(envelopeFile, scope: scope());
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> writeEnvelope(NotebookEnvelope envelope) =>
      envelopeFile.writeAsString(envelope.encode());

  group('reload', () {
    test(
      'a committed envelope reloads with the same notebook and journal',
      () async {
        final base = emptyEnvelope();
        await writeEnvelope(base);
        final result = await store.commit(
          base: base,
          notebook: notebookWithEntry(),
          operation: createOp(),
        );
        expect(result.status, EnvelopeCommitStatus.committed);
        expect(result.envelope!.revision, 2);

        final reloaded = await store.read();
        expect(reloaded!.revision, 2);
        expect(
          jsonEncode(reloaded.notebook.toJson()),
          jsonEncode(notebookWithEntry().toJson()),
        );
        expect(reloaded.journal.length, 1);
        expect(reloaded.journal.operations.single.operationId, 'op-1');
        expect(reloaded.encode(), result.envelope!.encode());
      },
    );

    test('a missing file reads as null instead of an empty notebook', () async {
      expect(await store.read(), isNull);
    });

    test('commit without a stored envelope is refused as stale', () async {
      final result = await store.commit(
        base: emptyEnvelope(),
        notebook: notebookWithEntry(),
        operation: createOp(),
      );
      expect(result.status, EnvelopeCommitStatus.stale);
      expect(await envelopeFile.exists(), isFalse);
    });
  });

  group('Unicode', () {
    test('text survives the commit and reload byte for byte', () async {
      const text = '日记 😀 ﷽ и кириллица e\u0301 \u{1F1E8}\u{1F1F3}';
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final result = await store.commit(
        base: base,
        notebook: notebookWithEntry(text: text),
        operation: createOp(text: text),
      );
      expect(result.status, EnvelopeCommitStatus.committed);

      final reloaded = await store.read();
      expect(reloaded!.notebook.entries.single.text, text);
      expect(reloaded.journal.operations.single.text, text);
    });
  });

  group('scope', () {
    test('an envelope from another notebook is refused on read', () async {
      final other = NotebookEnvelope(
        revision: 1,
        notebook: Notebook.empty(),
        journal: Journal(notebookId: 'nb-other', epochId: _epochId),
      );
      await writeEnvelope(other);
      await expectLater(store.read(), throwsA(isA<EnvelopeScopeMismatch>()));
    });

    test(
      'an operation for another epoch is refused and nothing is written',
      () async {
        final base = emptyEnvelope();
        await writeEnvelope(base);
        final before = await envelopeFile.readAsString();

        final result = await store.commit(
          base: base,
          notebook: notebookWithEntry(),
          operation: createOp(epochId: 'ep-99'),
        );
        expect(result.status, EnvelopeCommitStatus.scopeMismatch);
        expect(await envelopeFile.readAsString(), before);
      },
    );

    test(
      'a store bound to another scope refuses to read a valid envelope',
      () async {
        await writeEnvelope(emptyEnvelope());
        final otherStore = AtomicNotebookStore(
          envelopeFile,
          scope: scope(notebookId: 'nb-other'),
        );
        await expectLater(
          otherStore.read(),
          throwsA(isA<EnvelopeScopeMismatch>()),
        );
      },
    );
  });

  group('malformed and unsupported envelopes', () {
    Future<void> expectRejected(String text) async {
      await envelopeFile.writeAsString(text);
      final before = await envelopeFile.readAsString();
      await expectLater(store.read(), throwsA(isA<EnvelopeFormatException>()));
      expect(await envelopeFile.readAsString(), before);
    }

    test('invalid JSON is rejected without rewriting the file', () async {
      await expectRejected('{not json');
    });

    test('an unsupported envelope version is rejected', () async {
      await expectRejected(
        jsonEncode({
          ...emptyEnvelope().toJson(),
          'schemaVersion': envelopeSchemaVersion + 1,
        }),
      );
    });

    test('an unsupported notebook schema version is rejected', () async {
      final json = emptyEnvelope().toJson();
      (json['notebook']! as Map<String, Object?>)['schemaVersion'] =
          Notebook.storageVersion + 1;
      await expectRejected(jsonEncode(json));
    });

    test('an unknown or missing key is rejected', () async {
      await expectRejected(
        jsonEncode({...emptyEnvelope().toJson(), 'extra': true}),
      );
      final missing = Map<String, Object?>.from(emptyEnvelope().toJson())
        ..remove('journal');
      await expectRejected(jsonEncode(missing));
    });

    test('a non-canonical notebook snapshot is rejected', () async {
      final json = emptyEnvelope().toJson();
      final notebook = json['notebook']! as Map<String, Object?>;
      // A valid JSON value that the model would normalise away on round trip.
      notebook['sortOrder'] = 'unknown-order';
      await expectRejected(jsonEncode(json));
    });

    test('a duplicate operation inside the journal is rejected', () async {
      final op = createOp();
      final journal = Journal(
        notebookId: _notebookId,
        epochId: _epochId,
        operations: [op],
      );
      final json = NotebookEnvelope(
        revision: 1,
        notebook: notebookWithEntry(),
        journal: journal,
      ).toJson();
      final operations =
          (json['journal']! as Map<String, Object?>)['operations']! as List;
      operations.add(op.toJson());
      await expectRejected(jsonEncode(json));
    });

    test('a journal for another scope inside the file is rejected', () async {
      final json = emptyEnvelope().toJson();
      (json['journal']! as Map<String, Object?>)['notebookId'] = 'nb-other';
      await envelopeFile.writeAsString(jsonEncode(json));
      final before = await envelopeFile.readAsString();
      await expectLater(store.read(), throwsA(isA<EnvelopeScopeMismatch>()));
      expect(await envelopeFile.readAsString(), before);
    });
  });

  group('disruption immediately before replacement', () {
    test('a failure before rename leaves the previous pair intact', () async {
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final first = await store.commit(
        base: base,
        notebook: notebookWithEntry(),
        operation: createOp(),
      );
      expect(first.status, EnvelopeCommitStatus.committed);
      final committedBytes = await envelopeFile.readAsString();

      final interrupted = AtomicNotebookStore(
        envelopeFile,
        scope: scope(),
        beforeReplace: () async => throw const FileSystemException('crash'),
      );
      final second = await interrupted.commit(
        base: first.envelope!,
        notebook: notebookWithEntry(text: '第二稿'),
        operation: reviseOp(),
      );
      expect(second.status, EnvelopeCommitStatus.failed);
      expect(second.isCommitted, isFalse);
      expect(await envelopeFile.readAsString(), committedBytes);

      final reloaded = await store.read();
      expect(reloaded!.revision, 2);
      expect(reloaded.notebook.entries.single.text, '我会考完雅思。');
      expect(reloaded.journal.length, 1);
      expect(reloaded.journal.operations.single.operationId, 'op-1');
      expect(await File('${envelopeFile.path}.tmp').exists(), isFalse);
    });

    test(
      'the interrupted commit can be retried to the same revision',
      () async {
        final base = emptyEnvelope();
        await writeEnvelope(base);
        final failing = AtomicNotebookStore(
          envelopeFile,
          scope: scope(),
          beforeReplace: () async => throw const FileSystemException('crash'),
        );
        expect(
          (await failing.commit(
            base: base,
            notebook: notebookWithEntry(),
            operation: createOp(),
          )).status,
          EnvelopeCommitStatus.failed,
        );
        final retried = await store.commit(
          base: base,
          notebook: notebookWithEntry(),
          operation: createOp(),
        );
        expect(retried.status, EnvelopeCommitStatus.committed);
        expect(retried.envelope!.revision, 2);
      },
    );
  });

  group('duplicate, no-op, conflict and stale updates', () {
    late NotebookEnvelope base;

    setUp(() async {
      base = emptyEnvelope();
      await writeEnvelope(base);
      final first = await store.commit(
        base: base,
        notebook: notebookWithEntry(),
        operation: createOp(),
      );
      expect(first.status, EnvelopeCommitStatus.committed);
      base = first.envelope!;
    });

    test('an exact replay is a no-op that writes nothing', () async {
      final before = await envelopeFile.readAsString();
      final result = await store.commit(
        base: base,
        notebook: base.notebook,
        operation: createOp(),
      );
      expect(result.status, EnvelopeCommitStatus.noChange);
      expect(result.isCommitted, isFalse);
      expect(result.envelope!.revision, base.revision);
      expect(await envelopeFile.readAsString(), before);
    });

    test(
      'a replay with a divergent snapshot is reported as duplicate',
      () async {
        final before = await envelopeFile.readAsString();
        final result = await store.commit(
          base: base,
          notebook: notebookWithEntry(text: '被改写的正文'),
          operation: createOp(),
        );
        expect(result.status, EnvelopeCommitStatus.duplicate);
        expect(await envelopeFile.readAsString(), before);
      },
    );

    test('a reused operation id with new content is a conflict', () async {
      final before = await envelopeFile.readAsString();
      final result = await store.commit(
        base: base,
        notebook: notebookWithEntry(text: '另一段正文'),
        operation: createOp(text: '另一段正文'),
      );
      expect(result.status, EnvelopeCommitStatus.conflict);
      expect(result.conflict!.isCollision, isTrue);
      expect(await envelopeFile.readAsString(), before);
    });

    test('a second creation of the same entry is a conflict', () async {
      final result = await store.commit(
        base: base,
        notebook: notebookWithEntry(text: '另一段正文'),
        operation: createOp(operationId: 'op-2', sequence: 2, text: '另一段正文'),
      );
      expect(result.status, EnvelopeCommitStatus.conflict);
      final reloaded = await store.read();
      expect(reloaded!.journal.length, 1);
    });

    test('a reused actor sequence is a conflict', () async {
      final result = await store.commit(
        base: base,
        notebook: notebookWithEntry(text: '另一段正文'),
        operation: createOp(operationId: 'op-2', text: '另一段正文'),
      );
      expect(result.status, EnvelopeCommitStatus.conflict);
    });

    test('a new operation with an unchanged snapshot is refused', () async {
      final before = await envelopeFile.readAsString();
      final result = await store.commit(
        base: base,
        notebook: base.notebook,
        operation: reviseOp(),
      );
      expect(result.status, EnvelopeCommitStatus.inconsistent);
      expect(result.isCommitted, isFalse);
      expect(await envelopeFile.readAsString(), before);
    });

    test(
      'a stale base revision is refused and the stored bytes survive',
      () async {
        final stale = emptyEnvelope();
        final before = await envelopeFile.readAsString();
        final result = await store.commit(
          base: stale,
          notebook: notebookWithEntry(text: '迟到的写入'),
          operation: createOp(operationId: 'op-2', sequence: 2, text: '迟到的写入'),
        );
        expect(result.status, EnvelopeCommitStatus.stale);
        expect(await envelopeFile.readAsString(), before);
        expect((await store.read())!.revision, base.revision);
      },
    );

    test(
      'a base with the stored revision but different content is stale',
      () async {
        final forged = NotebookEnvelope(
          revision: base.revision,
          notebook: Notebook.empty(),
          journal: base.journal,
        );
        final result = await store.commit(
          base: forged,
          notebook: notebookWithEntry(text: '伪造'),
          operation: createOp(operationId: 'op-2', sequence: 2, text: '伪造'),
        );
        expect(result.status, EnvelopeCommitStatus.stale);
      },
    );

    test('commits never mutate the caller\'s base journal', () async {
      final before = base.journal.length;
      await store.commit(
        base: base,
        notebook: notebookWithEntry(text: '第二稿'),
        operation: reviseOp(),
      );
      expect(base.journal.length, before);
      expect((await store.read())!.journal.length, before + 1);
    });

    test(
      'a refused commit never reports committed and never bumps revision',
      () async {
        final results = [
          await store.commit(
            base: base,
            notebook: base.notebook,
            operation: createOp(),
          ),
          await store.commit(
            base: base,
            notebook: notebookWithEntry(text: '冲突'),
            operation: createOp(text: '冲突'),
          ),
          await store.commit(
            base: emptyEnvelope(),
            notebook: notebookWithEntry(text: '过期'),
            operation: createOp(operationId: 'op-9', sequence: 9, text: '过期'),
          ),
        ];
        for (final result in results) {
          expect(result.isCommitted, isFalse);
          expect(result.envelope!.revision, base.revision);
        }
      },
    );
  });

  group('concurrent commits on one store', () {
    test('overlapping commits serialize and only one wins', () async {
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final results = await Future.wait([
        store.commit(
          base: base,
          notebook: notebookWithEntry(text: '甲'),
          operation: createOp(operationId: 'op-a', text: '甲'),
        ),
        store.commit(
          base: base,
          notebook: notebookWithEntry(text: '乙'),
          operation: createOp(operationId: 'op-b', sequence: 2, text: '乙'),
        ),
      ]);
      expect(
        results.where((r) => r.status == EnvelopeCommitStatus.committed).length,
        1,
      );
      expect(
        results.where((r) => r.status == EnvelopeCommitStatus.stale).length,
        1,
      );
      expect((await store.read())!.revision, 2);
    });
  });

  group('known gap: snapshot and journal correspondence', () {
    // The notebook model carries no notebook, epoch, or entry identity, so the
    // store cannot prove that a snapshot reflects an operation. These tests pin
    // that gap: production hookup is gated until replay (M3.3) defines and
    // checks the relationship.
    test('an operation for an absent entry is accepted as-is', () async {
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final result = await store.commit(
        base: base,
        notebook: notebookWithEntry(),
        operation: createOp(entryId: 'entry-absent'),
      );
      expect(result.status, EnvelopeCommitStatus.committed);
      expect((await store.read())!.notebook.entries.single.id, 'entry-1');
    });
  });

  group('invalid proposed snapshot', () {
    Notebook invalidNotebook() => Notebook(
      volume: 1,
      entries: [
        JournalEntry(
          id: 'entry-dup',
          text: '甲',
          createdAt: _now,
          createdOn: DateTime.utc(2026, 11, 19),
          due: DateTime.utc(2026, 11, 30),
          status: EntryStatus.pending,
        ),
        JournalEntry(
          id: 'entry-dup',
          text: '乙',
          createdAt: _now,
          createdOn: DateTime.utc(2026, 11, 19),
          due: DateTime.utc(2026, 11, 30),
          status: EntryStatus.pending,
        ),
      ],
    );

    test(
      'a snapshot the store would refuse is a typed failure, not a throw',
      () async {
        final base = emptyEnvelope();
        await writeEnvelope(base);
        final before = await envelopeFile.readAsBytes();

        final result = await store.commit(
          base: base,
          notebook: invalidNotebook(),
          operation: createOp(),
        );

        expect(result.status, EnvelopeCommitStatus.failed);
        expect(result.isCommitted, isFalse);
        expect(result.envelope!.revision, base.revision);
        expect(result.reason, isNot(contains('entry-dup')));
        expect(result.reason, isNot(contains('甲')));
        // The stored bytes are unchanged and still usable afterwards.
        expect(await envelopeFile.readAsBytes(), before);
        final reloaded = await store.read();
        expect(reloaded!.revision, base.revision);
        expect(reloaded.notebook.entries, isEmpty);
        expect(reloaded.journal.isEmpty, isTrue);
        expect(
          await dir.list().where((e) => e.path.endsWith('.tmp')).toList(),
          isEmpty,
        );
      },
    );

    test(
      'a later valid commit still succeeds after a refused snapshot',
      () async {
        final base = emptyEnvelope();
        await writeEnvelope(base);
        expect(
          (await store.commit(
            base: base,
            notebook: invalidNotebook(),
            operation: createOp(),
          )).status,
          EnvelopeCommitStatus.failed,
        );

        final retried = await store.commit(
          base: base,
          notebook: notebookWithEntry(),
          operation: createOp(),
        );

        expect(retried.status, EnvelopeCommitStatus.committed);
        expect(retried.envelope!.revision, 2);
      },
    );

    test('an unrelated error from the snapshot keeps propagating', () async {
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final before = await envelopeFile.readAsBytes();

      // Guard the guard: this snapshot encodes as valid JSON and differs from
      // the stored one, so the commit reaches the replacement envelope and the
      // StateError escapes the narrow `on EnvelopeFormatException` catch.
      expect(_RejectingSnapshot().toJson()['volumeName'], 'rejected');
      expect(
        () => NotebookEnvelope(
          revision: 2,
          notebook: _RejectingSnapshot(),
          journal: base.journal,
        ),
        throwsA(isA<StateError>()),
      );

      await expectLater(
        store.commit(
          base: base,
          notebook: _RejectingSnapshot(),
          operation: createOp(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await envelopeFile.readAsBytes(), before);
      expect((await store.read())!.revision, base.revision);
    });

    test(
      'a non-storage failure after the temp write leaves no temp file',
      () async {
        final base = emptyEnvelope();
        await writeEnvelope(base);
        final before = await envelopeFile.readAsBytes();

        final interrupted = AtomicNotebookStore(
          envelopeFile,
          scope: scope(),
          beforeReplace: () async => throw StateError('hook failed'),
        );
        await expectLater(
          interrupted.commit(
            base: base,
            notebook: notebookWithEntry(),
            operation: createOp(),
          ),
          throwsA(isA<StateError>()),
        );

        // Cleanup still ran: no stray temp file, stored bytes untouched.
        expect(await envelopeFile.readAsBytes(), before);
        expect(
          await dir.list().where((e) => e.path.endsWith('.tmp')).toList(),
          isEmpty,
        );
        expect((await store.read())!.revision, base.revision);

        // The failed attempt released the per-path chain, so a later commit on
        // the same instance still lands instead of waiting on a broken tail.
        final retried = await store.commit(
          base: base,
          notebook: notebookWithEntry(),
          operation: createOp(),
        );
        expect(retried.status, EnvelopeCommitStatus.committed);
        expect(retried.envelope!.revision, 2);
      },
    );
  });

  group('error messages', () {
    test('a malformed envelope never echoes stored diary text', () async {
      const secret = '这是不该出现在错误里的日记正文';
      await envelopeFile.writeAsString(
        jsonEncode({
          'schemaVersion': envelopeSchemaVersion,
          'format': envelopeFormatName,
          'revision': 1,
          'notebook': {'secret': secret},
          'journal': {'secret': secret},
        }),
      );
      try {
        await store.read();
        fail('expected an EnvelopeFormatException');
      } on EnvelopeFormatException catch (error) {
        expect(error.toString(), isNot(contains(secret)));
      }
    });
  });

  group('malformed data never echoes stored content', () {
    const secret = '这是不该出现在错误里的日记正文';

    void expectNoSecret(Object error) {
      final text = error.toString();
      expect(text, isNot(contains(secret)));
      if (error is JournalFormatException) {
        expect(error.message, isNot(contains(secret)));
        expect(error.field ?? '', isNot(contains(secret)));
      }
      if (error is EnvelopeFormatException) {
        expect(error.message, isNot(contains(secret)));
        expect(error.field ?? '', isNot(contains(secret)));
      }
    }

    test('an unknown envelope key is rejected without echoing the key', () {
      final json = emptyEnvelope().toJson()..[secret] = true;
      try {
        NotebookEnvelope.decode(jsonEncode(json));
        fail('expected an EnvelopeFormatException');
      } on EnvelopeFormatException catch (error) {
        expectNoSecret(error);
      }
    });

    test('an unknown journal key is rejected without echoing the key', () {
      final json = Journal(notebookId: _notebookId, epochId: _epochId).toJson()
        ..[secret] = true;
      try {
        Journal.fromJson(json);
        fail('expected a JournalFormatException');
      } on JournalFormatException catch (error) {
        expectNoSecret(error);
      }
    });

    test('an unknown operation key is rejected without echoing the key', () {
      final json = createOp().toJson()..[secret] = true;
      try {
        JournalOperation.fromJson(json);
        fail('expected a JournalFormatException');
      } on JournalFormatException catch (error) {
        expectNoSecret(error);
      }
    });

    test('an unsupported operation kind is rejected without echoing it', () {
      final json = createOp().toJson()..['kind'] = secret;
      try {
        JournalOperation.fromJson(json);
        fail('expected a JournalFormatException');
      } on JournalFormatException catch (error) {
        expectNoSecret(error);
      }
    });

    test('malformed UTF-8 fails closed and leaves the bytes alone', () async {
      final bytes = <int>[
        ...utf8.encode('{"schemaVersion":1,"format":"$envelopeFormatName"'),
        0xFF,
        0xFE,
        ...utf8.encode(secret),
      ];
      await envelopeFile.writeAsBytes(bytes);
      final before = await envelopeFile.readAsBytes();

      try {
        await store.read();
        fail('expected an EnvelopeFormatException');
      } on EnvelopeFormatException catch (error) {
        expectNoSecret(error);
      }
      expect(await envelopeFile.readAsBytes(), before);

      final result = await store.commit(
        base: emptyEnvelope(),
        notebook: notebookWithEntry(),
        operation: createOp(),
      );
      expect(result.status, EnvelopeCommitStatus.failed);
      expect(result.isCommitted, isFalse);
      expect(await envelopeFile.readAsBytes(), before);
    });

    test(
      'a malformed stored envelope makes commit fail instead of throw',
      () async {
        await envelopeFile.writeAsString('{not json');
        final before = await envelopeFile.readAsString();

        final result = await store.commit(
          base: emptyEnvelope(),
          notebook: notebookWithEntry(),
          operation: createOp(),
        );
        expect(result.status, EnvelopeCommitStatus.failed);
        expect(result.isCommitted, isFalse);
        expect(await envelopeFile.readAsString(), before);
      },
    );
  });

  group('production storage target', () {
    test(
      'a notebook.json target is refused before anything is written',
      () async {
        const appBytes = '{"schemaVersion":4,"volume":1,"entries":[]}';
        await appNotebookFile.writeAsString(appBytes);

        expect(
          () => AtomicNotebookStore(appNotebookFile, scope: scope()),
          throwsArgumentError,
        );
        expect(await appNotebookFile.readAsString(), appBytes);
        expect(await dir.list().map((e) => e.path.split('/').last).toList(), [
          'notebook.json',
        ]);
      },
    );

    test('ASCII case variants of notebook.json are refused everywhere', () async {
      const appBytes = '{"schemaVersion":4,"volume":1,"entries":[]}';
      await appNotebookFile.writeAsString(appBytes);

      // Refusal must not depend on the file system being case insensitive.
      for (final name in const [
        'NOTEBOOK.JSON',
        'Notebook.Json',
        'nOtEbOoK.jSoN',
        'notebook.JsOn',
      ]) {
        expect(
          () => AtomicNotebookStore(File('${dir.path}/$name'), scope: scope()),
          throwsArgumentError,
          reason: '$name must be refused like notebook.json',
        );
      }
      // Nothing was created for the refused names, and the real file is intact.
      expect(await appNotebookFile.readAsString(), appBytes);
      expect(
        (await dir.list().map((e) => e.path.split('/').last).toList())..sort(),
        ['notebook.json'],
      );
    });

    test('names that merely contain the reserved name stay usable', () async {
      for (final name in const [
        'notebook-envelope.json',
        'my-notebook.json',
        'notebook.json.bak',
        'notebook.json2',
      ]) {
        final candidate = AtomicNotebookStore(
          File('${dir.path}/$name'),
          scope: scope(),
        );
        expect(candidate.file.uri.pathSegments.last, name);
      }
    });

    test('an ASCII-case variant cannot be used as a live commit target', () async {
      // The constructor refusal is the only guard, so prove that no write lands
      // even when the app notebook document is spelled with another ASCII case
      // and the host file system would treat it as a different inode.
      const appBytes = '{"schemaVersion":4,"volume":1,"entries":[]}';
      await appNotebookFile.writeAsString(appBytes);
      final base = emptyEnvelope();
      await writeEnvelope(base);

      for (final name in const ['NOTEBOOK.JSON', 'NoTeBoOk.JsOn']) {
        final target = File('${dir.path}/$name');
        expect(
          () => AtomicNotebookStore(target, scope: scope()),
          throwsArgumentError,
        );
        // Nothing was written under the variant name either.
        expect(await target.exists(), isFalse);
      }
      expect(await appNotebookFile.readAsString(), appBytes);
      expect(
        (await dir.list().map((e) => e.path.split('/').last).toList())..sort(),
        ['notebook-envelope.json', 'notebook.json'],
      );
    });
  });

  group('two instances on one path', () {
    test('simultaneous commits never both report a durable change', () async {
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final first = AtomicNotebookStore(envelopeFile, scope: scope());
      final second = AtomicNotebookStore(envelopeFile, scope: scope());

      final results = await Future.wait([
        first.commit(
          base: base,
          notebook: notebookWithEntry(text: '甲'),
          operation: createOp(operationId: 'op-a', text: '甲'),
        ),
        second.commit(
          base: base,
          notebook: notebookWithEntry(text: '乙'),
          operation: createOp(operationId: 'op-b', sequence: 2, text: '乙'),
        ),
      ]);

      expect(results.where((r) => r.isCommitted).length, 1);
      expect(
        results.where((r) => r.status == EnvelopeCommitStatus.stale).length,
        1,
      );
      final reloaded = await AtomicNotebookStore(
        envelopeFile,
        scope: scope(),
      ).read();
      expect(reloaded!.revision, 2);
      expect(reloaded.journal.length, 1);
      expect(
        await dir
            .list()
            .where((entity) => entity.path.endsWith('.tmp'))
            .toList(),
        isEmpty,
      );
    });

    test('equivalent path spellings share one lock', () async {
      final base = emptyEnvelope();
      await writeEnvelope(base);
      final plain = AtomicNotebookStore(envelopeFile, scope: scope());
      final alias = AtomicNotebookStore(
        File('${dir.path}/./${envelopeFile.uri.pathSegments.last}'),
        scope: scope(),
      );

      final results = await Future.wait([
        plain.commit(
          base: base,
          notebook: notebookWithEntry(text: '甲'),
          operation: createOp(operationId: 'op-a', text: '甲'),
        ),
        alias.commit(
          base: base,
          notebook: notebookWithEntry(text: '乙'),
          operation: createOp(operationId: 'op-b', sequence: 2, text: '乙'),
        ),
      ]);

      expect(results.where((r) => r.isCommitted).length, 1);
      expect(
        results.where((r) => r.status == EnvelopeCommitStatus.stale).length,
        1,
      );
      expect((await plain.read())!.revision, 2);
    });
  });

  group('existing app file', () {
    test('commits leave notebook.json untouched', () async {
      const appBytes = '{"schemaVersion":4,"volume":3,"entries":[]}';
      await appNotebookFile.writeAsString(appBytes);
      final base = emptyEnvelope();
      await writeEnvelope(base);

      await store.commit(
        base: base,
        notebook: notebookWithEntry(),
        operation: createOp(),
      );
      await store.read();

      expect(await appNotebookFile.readAsString(), appBytes);
      expect(await envelopeFile.exists(), isTrue);
      expect(
        (await dir.list().map((e) => e.path).toList())..sort(),
        [envelopeFile.path, appNotebookFile.path]..sort(),
      );
    });
  });

  group('document shape', () {
    test('the envelope is a distinct versioned document', () {
      final json = emptyEnvelope().toJson();
      expect(json['schemaVersion'], envelopeSchemaVersion);
      expect(json['format'], envelopeFormatName);
      expect(
        json.keys,
        containsAll(<String>[
          'schemaVersion',
          'format',
          'revision',
          'notebook',
          'journal',
        ]),
      );
      expect(
        (json['notebook']! as Map)['schemaVersion'],
        Notebook.storageVersion,
      );
    });

    test('an envelope cannot be decoded as a notebook or vice versa', () {
      expect(
        () => Notebook.fromJson(
          Map<String, dynamic>.from(emptyEnvelope().toJson()),
        ),
        throwsA(anything),
      );
      expect(
        () => NotebookEnvelope.decode(jsonEncode(Notebook.empty().toJson())),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });
}

/// A snapshot that is valid and non-canonical as JSON, differs from the stored
/// one, and fails only when the replacement envelope validates it.
class _RejectingSnapshot extends Notebook {
  _RejectingSnapshot() : super(volume: 1, entries: const []);

  @override
  Map<String, dynamic> toJson() => {
    ...Notebook.empty().toJson(),
    'volumeName': 'rejected',
  };

  @override
  int get volume => throw StateError('snapshot rejected');
}

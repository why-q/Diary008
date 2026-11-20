import 'dart:convert';
import 'dart:io';

import 'package:diary008/journal/atomic_notebook_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_projection_gate.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-5f03';
const _epochId = 'ep-8a';
final _recordedAt = DateTime.utc(2026, 11, 20, 12, 40, 9);
const _volume = 2;

JournalScope _scope() =>
    JournalScope(notebookId: _notebookId, epochId: _epochId);

JournalCreateEntry _create({
  String operationId = 'op-create-1',
  String entryId = 'entry-new',
  String text = '新的日记。',
  String epochId = _epochId,
}) => JournalCreateEntry(
  notebookId: _notebookId,
  epochId: epochId,
  actorId: 'dev-alpha',
  sequence: 1,
  operationId: operationId,
  recordedAt: _recordedAt,
  entryId: entryId,
  text: text,
  createdOn: CivilDate(2026, 11, 20),
);

Notebook _baseNotebook() =>
    Notebook(volume: _volume, volumeName: '第二卷', entries: const []);

Notebook _projectedCreate(String text) => Notebook(
  volume: _volume,
  volumeName: '第二卷',
  entries: [
    JournalEntry(
      id: 'entry-new',
      text: text,
      createdAt: _recordedAt,
      createdOn: DateTime.utc(2026, 11, 20),
      status: EntryStatus.explanation,
    ),
  ],
);

NotebookEnvelope _envelope({
  Notebook? notebook,
  List<JournalOperation> operations = const [],
}) => NotebookEnvelope(
  revision: 1,
  notebook: notebook ?? _baseNotebook(),
  journal: Journal(
    notebookId: _notebookId,
    epochId: _epochId,
    operations: operations,
  ),
);

/// Encodes honestly, but throws from [toJson] itself.
class _ThrowingToJson extends Notebook {
  _ThrowingToJson({required Notebook honest})
    : super(
        volume: honest.volume,
        volumeName: honest.volumeName,
        sortOrder: honest.sortOrder,
        entries: honest.entries,
        archives: honest.archives,
      );

  @override
  Map<String, dynamic> toJson() => throw StateError('snapshot refused');
}

/// Valid values in every field, but the [sortOrder] getter is broken. Only
/// [toJson] reaches it, so it probes the encoding boundary alone.
class _ThrowingSortOrder extends Notebook {
  _ThrowingSortOrder()
    : super(volume: _volume, volumeName: '第二卷', entries: const []);

  @override
  NotebookSortOrder get sortOrder => throw StateError('sort order refused');
}

/// Valid, encodable values, but the [volume] getter is broken. Both the
/// snapshot invariant check and [toJson] read it.
class _ThrowingVolume extends Notebook {
  _ThrowingVolume()
    : super(volume: _volume, volumeName: '第二卷', entries: const []);

  @override
  int get volume => throw StateError('volume refused');
}

/// Every getter is broken, but the serialized form is an honest snapshot.
class _HonestEncodingBrokenGetters extends Notebook {
  _HonestEncodingBrokenGetters({required Notebook honest})
    : _honest = honest,
      super(
        volume: honest.volume,
        volumeName: honest.volumeName,
        sortOrder: honest.sortOrder,
        entries: honest.entries,
        archives: honest.archives,
      );

  final Notebook _honest;

  @override
  Map<String, dynamic> toJson() => _honest.toJson();

  @override
  int get volume => throw StateError('getter must not be consulted');

  @override
  NotebookSortOrder get sortOrder =>
      throw StateError('getter must not be consulted');

  @override
  List<JournalEntry> get entries =>
      throw StateError('getter must not be consulted');

  @override
  List<NotebookArchive> get archives =>
      throw StateError('getter must not be consulted');

  @override
  String get volumeName => throw StateError('getter must not be consulted');
}

/// Getters report a snapshot that is not the journal projection, while the
/// encoding is the honest projection.
class _LyingGettersHonestEncoding extends Notebook {
  _LyingGettersHonestEncoding({required Notebook honest})
    : _honest = honest,
      super(
        volume: honest.volume,
        volumeName: honest.volumeName,
        sortOrder: honest.sortOrder,
        entries: honest.entries,
        archives: honest.archives,
      );

  final Notebook _honest;

  @override
  Map<String, dynamic> toJson() => _honest.toJson();

  @override
  String get volumeName => '骗人的卷名';

  @override
  NotebookSortOrder get sortOrder => NotebookSortOrder.deadline;
}

/// Encodes a snapshot the store would refuse to load again: an entry with
/// blank text.
class _InvalidEncoding extends Notebook {
  _InvalidEncoding({required Notebook honest})
    : _honest = honest,
      super(
        volume: honest.volume,
        volumeName: honest.volumeName,
        entries: honest.entries,
      );

  final Notebook _honest;

  @override
  Map<String, dynamic> toJson() => {
    ..._honest.toJson(),
    'entries': [
      for (final entry in _honest.entries) {...entry.toJson(), 'text': '   '},
    ],
  };
}

void main() {
  late Directory dir;
  late File envelopeFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-projection-boundary-');
    envelopeFile = File('${dir.path}/notebook-envelope.json');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> seed(NotebookEnvelope envelope) =>
      envelopeFile.writeAsString(envelope.encode());

  Future<List<int>> storedBytes() => envelopeFile.readAsBytes();

  Future<List<String>> directoryNames() async =>
      (await dir.list().map((entity) => entity.path.split('/').last).toList())
        ..sort();

  AtomicNotebookStore legacy() =>
      AtomicNotebookStore(envelopeFile, scope: _scope());

  AtomicNotebookStore validated() => AtomicNotebookStore.projectionValidated(
    envelopeFile,
    scope: _scope(),
    baseline: JournalProjectionBaseline(
      notebook: _baseNotebook(),
      scope: _scope(),
    ),
  );

  group('legacy path keeps the published storage boundaries', () {
    test('a throwing toJson propagates and leaves the stored bytes', () async {
      await seed(_envelope());
      final before = await storedBytes();

      await expectLater(
        legacy().commit(
          base: _envelope(),
          notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
          operation: _create(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await storedBytes(), before);
      expect((await legacy().read())!.revision, 1);
      expect(await directoryNames(), ['notebook-envelope.json']);
    });

    test(
      'a throwing sortOrder getter propagates through the encoding',
      () async {
        await seed(_envelope());
        final before = await storedBytes();

        await expectLater(
          legacy().commit(
            base: _envelope(),
            notebook: _ThrowingSortOrder(),
            operation: _create(),
          ),
          throwsA(isA<StateError>()),
        );

        expect(await storedBytes(), before);
        expect(await directoryNames(), ['notebook-envelope.json']);
      },
    );

    test(
      'a throwing volume getter propagates from the snapshot check',
      () async {
        await seed(_envelope());
        final before = await storedBytes();

        await expectLater(
          legacy().commit(
            base: _envelope(),
            notebook: _ThrowingVolume(),
            operation: _create(),
          ),
          throwsA(isA<StateError>()),
        );

        expect(await storedBytes(), before);
      },
    );

    test(
      'a rejected operation decides before the snapshot is consulted',
      () async {
        await seed(_envelope());
        final before = await storedBytes();

        final result = await legacy().commit(
          base: _envelope(),
          notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
          operation: _create(epochId: 'ep-other'),
        );

        expect(result.status, EnvelopeCommitStatus.scopeMismatch);
        expect(result.reason, 'operation does not belong to this journal');
        expect(await storedBytes(), before);
      },
    );

    test(
      'a collided operation decides before the snapshot is consulted',
      () async {
        await seed(_envelope(operations: [_create()]));
        final before = await storedBytes();

        final result = await legacy().commit(
          base: _envelope(operations: [_create()]),
          notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
          operation: _create(text: '不同的文字。'),
        );

        expect(result.status, EnvelopeCommitStatus.conflict);
        expect(await storedBytes(), before);
      },
    );

    test('a stale base decides before the snapshot is consulted', () async {
      await seed(_envelope());
      final before = await storedBytes();

      final result = await legacy().commit(
        base: _envelope(notebook: Notebook.empty()),
        notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.stale);
      expect(await storedBytes(), before);
    });

    test('a replayed operation still consults the snapshot', () async {
      await seed(_envelope(operations: [_create()]));

      await expectLater(
        legacy().commit(
          base: _envelope(operations: [_create()]),
          notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
          operation: _create(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the returned envelope is built from the caller snapshot', () async {
      await seed(_envelope());
      final offered = _projectedCreate('新的日记。');

      final result = await legacy().commit(
        base: _envelope(),
        notebook: offered,
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.committed);
      expect(identical(result.envelope!.notebook, offered), isTrue);
      expect(result.envelope!.encode(), await envelopeFile.readAsString());
    });

    test('a snapshot the store would refuse is a typed failure', () async {
      await seed(_envelope());
      final before = await storedBytes();

      final result = await legacy().commit(
        base: _envelope(),
        notebook: _InvalidEncoding(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.failed);
      expect(await storedBytes(), before);
    });
  });

  group('projection path is canonical only', () {
    test('caller getters are never consulted', () async {
      await seed(_envelope());

      final result = await validated().commit(
        base: _envelope(),
        notebook: _HonestEncodingBrokenGetters(
          honest: _projectedCreate('新的日记。'),
        ),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.committed);
      final reloaded = await validated().read();
      expect(reloaded!.revision, 2);
      expect(reloaded.notebook.entries.single.text, '新的日记。');
    });

    test('lying getters cannot change what is persisted', () async {
      await seed(_envelope());

      final result = await validated().commit(
        base: _envelope(),
        notebook: _LyingGettersHonestEncoding(
          honest: _projectedCreate('新的日记。'),
        ),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.committed);
      final reloaded = await validated().read();
      expect(reloaded!.notebook.volumeName, '第二卷');
      expect(reloaded.notebook.sortOrder, NotebookSortOrder.writing);
    });

    test('an honest serialized projection still commits', () async {
      await seed(_envelope());

      final result = await validated().commit(
        base: _envelope(),
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.committed);
      expect((await validated().read())!.revision, 2);
      expect(await directoryNames(), ['notebook-envelope.json']);
    });

    test('a snapshot that cannot serialize is a typed mismatch', () async {
      await seed(_envelope());
      final before = await storedBytes();

      final result = await validated().commit(
        base: _envelope(),
        notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.reason, 'journal.projection.projectionMismatch');
      expect(result.isCommitted, isFalse);
      expect(await storedBytes(), before);
      expect(await directoryNames(), ['notebook-envelope.json']);
    });

    test(
      'a broken getter reached only by the encoding is a typed mismatch',
      () async {
        await seed(_envelope());
        final before = await storedBytes();

        final result = await validated().commit(
          base: _envelope(),
          notebook: _ThrowingSortOrder(),
          operation: _create(),
        );

        expect(result.status, EnvelopeCommitStatus.projectionMismatch);
        expect(await storedBytes(), before);
      },
    );

    test('invalid serialized content is a typed mismatch', () async {
      await seed(_envelope());
      final before = await storedBytes();

      final result = await validated().commit(
        base: _envelope(),
        notebook: _InvalidEncoding(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.isCommitted, isFalse);
      expect(await storedBytes(), before);
      expect(await directoryNames(), ['notebook-envelope.json']);
    });

    test('a refusal leaves the bytes untouched and a retry commits', () async {
      await seed(_envelope());
      final before = await storedBytes();

      final refused = await validated().commit(
        base: _envelope(),
        notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );
      expect(refused.status, EnvelopeCommitStatus.projectionMismatch);
      expect(await storedBytes(), before);

      final retried = await validated().commit(
        base: _envelope(),
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );
      expect(retried.status, EnvelopeCommitStatus.committed);

      final after = await storedBytes();
      final written = NotebookEnvelope.decode(utf8.decode(after));
      expect(written.revision, 2);
      expect(written.notebook.entries.single.text, '新的日记。');
      expect(written.journal.length, 1);
    });

    test('the stored projection decides before the offered snapshot', () async {
      // The persisted snapshot already drifted from its journal, and the
      // offered snapshot cannot even serialize.
      final corrupt = _envelope(
        notebook: _projectedCreate('被改过的文字。'),
        operations: [_create()],
      );
      await seed(corrupt);
      final before = await storedBytes();

      final result = await validated().commit(
        base: corrupt,
        notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.reason, 'journal.projection.baselineMismatch');
      expect(await storedBytes(), before);
    });

    test('a stale base decides before the offered snapshot', () async {
      await seed(_envelope());
      final before = await storedBytes();

      final result = await validated().commit(
        base: _envelope(notebook: Notebook.empty()),
        notebook: _ThrowingToJson(honest: _projectedCreate('新的日记。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.stale);
      expect(await storedBytes(), before);
    });
  });
}

import 'dart:io';

import 'package:diary008/journal/atomic_notebook_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_projection_gate.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-77c2';
const _epochId = 'ep-09';
final _recordedAt = DateTime.utc(2026, 11, 20, 11, 30, 2);
const _volume = 2;

JournalScope _scope({String epochId = _epochId}) =>
    JournalScope(notebookId: _notebookId, epochId: epochId);

JournalCreateEntry _create({
  String operationId = 'op-create-1',
  String entryId = 'entry-new',
  String text = '真实的文字。',
  int sequence = 1,
}) => JournalCreateEntry(
  notebookId: _notebookId,
  epochId: _epochId,
  actorId: 'dev-alpha',
  sequence: sequence,
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
  int revision = 1,
  Notebook? notebook,
  List<JournalOperation> operations = const [],
}) => NotebookEnvelope(
  revision: revision,
  notebook: notebook ?? _baseNotebook(),
  journal: Journal(
    notebookId: _notebookId,
    epochId: _epochId,
    operations: operations,
  ),
);

/// A snapshot that reports journal-equivalent values through its getters but
/// serializes different text, so the persisted bytes disagree with what every
/// structural comparison sees.
class _LyingNotebook extends Notebook {
  _LyingNotebook({required Notebook honest})
    : _honest = honest,
      super(
        volume: honest.volume,
        volumeName: honest.volumeName,
        sortOrder: honest.sortOrder,
        entries: honest.entries,
        archives: honest.archives,
      );

  final Notebook _honest;

  /// What [toJson] writes, which never appears in the getters below.
  final String serializedText = '被改过的文字。';

  @override
  Map<String, dynamic> toJson() {
    final json = _honest.toJson();
    return {
      ...json,
      'entries': [
        for (final entry in _honest.entries)
          if (entry.id == _honest.entries.first.id)
            {...entry.toJson(), 'text': serializedText}
          else
            entry.toJson(),
      ],
    };
  }
}

/// A baseline that reports honest values when constructed but would serialize
/// something else on every later call.
class _DriftingBaseline extends Notebook {
  _DriftingBaseline({required Notebook honest})
    : _honest = honest,
      super(
        volume: honest.volume,
        volumeName: honest.volumeName,
        sortOrder: honest.sortOrder,
        entries: honest.entries,
        archives: honest.archives,
      );

  final Notebook _honest;
  int serializations = 0;

  @override
  Map<String, dynamic> toJson() {
    serializations++;
    return {..._honest.toJson(), 'volumeName': '第$serializations次不同的卷名'};
  }
}

void main() {
  late Directory dir;
  late File envelopeFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-projection-canonical-');
    envelopeFile = File('${dir.path}/notebook-envelope.json');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> seed(NotebookEnvelope envelope) =>
      envelopeFile.writeAsString(envelope.encode());

  AtomicNotebookStore validated(Notebook baseline) =>
      AtomicNotebookStore.projectionValidated(
        envelopeFile,
        scope: _scope(),
        baseline: JournalProjectionBaseline(
          notebook: baseline,
          scope: _scope(),
        ),
      );

  group('offered snapshot honesty', () {
    test('a snapshot whose getters and encoding disagree is refused', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());
      final before = await envelopeFile.readAsString();

      final lying = _LyingNotebook(honest: _projectedCreate('真实的文字。'));
      final result = await store.commit(
        base: _envelope(),
        notebook: lying,
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.isCommitted, isFalse);
      expect(await envelopeFile.readAsString(), before);
      expect((await store.read())!.revision, 1);
    });

    test(
      'a refused lying snapshot does not block the next genuine commit',
      () async {
        await seed(_envelope());
        final store = validated(_baseNotebook());

        final lying = _LyingNotebook(honest: _projectedCreate('真实的文字。'));
        final refused = await store.commit(
          base: _envelope(),
          notebook: lying,
          operation: _create(),
        );
        expect(refused.status, EnvelopeCommitStatus.projectionMismatch);

        final genuine = await store.commit(
          base: _envelope(),
          notebook: _projectedCreate('真实的文字。'),
          operation: _create(),
        );
        expect(genuine.status, EnvelopeCommitStatus.committed);
        final reloaded = await store.read();
        expect(reloaded!.revision, 2);
        expect(reloaded.notebook.entries.single.text, '真实的文字。');
      },
    );

    test('a metadata-only lie is refused too', () async {
      // The lie is confined to a notebook field, so every entry getter still
      // looks correct and only the serialized bytes reveal the disagreement.
      await seed(_envelope());
      final store = validated(_baseNotebook());
      final before = await envelopeFile.readAsString();

      final result = await store.commit(
        base: _envelope(),
        notebook: _MetadataLiar(honest: _projectedCreate('真实的文字。')),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.isCommitted, isFalse);
      expect(await envelopeFile.readAsString(), before);
    });
  });

  group('canonical snapshot', () {
    test('an honest snapshot canonicalizes to an equal encoding', () {
      final honest = _projectedCreate('真实的文字。');
      final canonical = CanonicalSnapshot.tryCanonicalize(honest)!;

      expect(identical(canonical.notebook, honest), isFalse);
      expect(canonical.notebook.toJson(), honest.toJson());
    });

    test('canonicalization is idempotent', () {
      final once = CanonicalSnapshot.tryCanonicalize(
        _projectedCreate('真实的文字。'),
      )!;
      final twice = CanonicalSnapshot.tryCanonicalize(once.notebook)!;
      expect(twice.notebook.toJson(), once.notebook.toJson());
    });

    test('a snapshot that cannot be encoded yields no canonical value', () {
      expect(CanonicalSnapshot.tryCanonicalize(_UnencodableNotebook()), isNull);
      expect(CanonicalSnapshot.tryCanonicalize(null), isNull);
    });
  });

  group('baseline honesty', () {
    test('the baseline is detached at construction and cannot drift later', () {
      final drifting = _DriftingBaseline(honest: _baseNotebook());
      final baseline = JournalProjectionBaseline(
        notebook: drifting,
        scope: _scope(),
      );
      final firstEncoding = baseline.notebook.toJson();

      expect(identical(baseline.notebook, drifting), isFalse);
      expect(drifting.serializations, greaterThan(0));

      final secondEncoding = baseline.notebook.toJson();
      expect(secondEncoding, firstEncoding);
      expect(drifting.serializations, 1);
    });

    test('a baseline that cannot serialize a valid snapshot is refused', () {
      expect(
        () => JournalProjectionBaseline(
          notebook: _UnencodableNotebook(),
          scope: _scope(),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a baseline that serializes an invalid snapshot is refused', () {
      expect(
        () => JournalProjectionBaseline(
          notebook: _EmptyTextNotebook(honest: _baseNotebook()),
          scope: _scope(),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a lying baseline fails closed on the first commit', () async {
      await seed(_envelope());
      final store = AtomicNotebookStore.projectionValidated(
        envelopeFile,
        scope: _scope(),
        baseline: JournalProjectionBaseline(
          notebook: _DriftingBaseline(honest: _baseNotebook()),
          scope: _scope(),
        ),
      );
      final before = await envelopeFile.readAsString();

      final result = await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('真实的文字。'),
        operation: _create(),
      );

      expect(result.isCommitted, isFalse);
      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(await envelopeFile.readAsString(), before);
    });
  });

  group('returned state', () {
    test(
      'a commit returns the persisted envelope, not the caller object',
      () async {
        await seed(_envelope());
        final store = validated(_baseNotebook());
        final offered = _projectedCreate('真实的文字。');

        final result = await store.commit(
          base: _envelope(),
          notebook: offered,
          operation: _create(),
        );

        expect(result.status, EnvelopeCommitStatus.committed);
        expect(identical(result.envelope!.notebook, offered), isFalse);
        expect(result.envelope!.encode(), await envelopeFile.readAsString());
      },
    );

    test(
      'a committing snapshot subclass cannot leak into the result',
      () async {
        await seed(_envelope());
        final store = AtomicNotebookStore(envelopeFile, scope: _scope());
        final honest = _projectedCreate('真实的文字。');

        final result = await store.commit(
          base: _envelope(),
          notebook: honest,
          operation: _create(),
        );

        expect(result.status, EnvelopeCommitStatus.committed);
        expect(identical(result.envelope!.notebook, honest), isFalse);
        expect(result.envelope!.encode(), await envelopeFile.readAsString());
      },
    );

    test('a refused commit returns the stored envelope unchanged', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());

      final result = await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('别的文字。'),
        operation: _create(),
      );

      expect(result.isCommitted, isFalse);
      expect(result.envelope!.revision, 1);
      expect(result.envelope!.encode(), await envelopeFile.readAsString());
    });
  });
}

class _MetadataLiar extends Notebook {
  _MetadataLiar({required Notebook honest})
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
  Map<String, dynamic> toJson() => {..._honest.toJson(), 'volumeName': '骗人的卷名'};
}

class _UnencodableNotebook extends Notebook {
  _UnencodableNotebook() : super(volume: 1, entries: const []);

  @override
  Map<String, dynamic> toJson() =>
      throw UnsupportedError('this snapshot refuses to serialize');
}

class _EmptyTextNotebook extends Notebook {
  _EmptyTextNotebook({required Notebook honest})
    : _honest = honest,
      super(volume: honest.volume, entries: honest.entries);

  final Notebook _honest;

  @override
  Map<String, dynamic> toJson() => {
    ..._honest.toJson(),
    'entries': [
      {'id': 'entry-x', 'text': '   ', 'createdAt': '2026-11-01T09:00:00.000Z'},
    ],
  };
}

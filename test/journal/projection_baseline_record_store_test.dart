import 'dart:io';

import 'package:diary008/journal/atomic_notebook_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_projection_gate.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/journal/projection_baseline_record.dart';
import 'package:diary008/journal/projection_baseline_record_store.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-7a42';
const _epochId = 'ep-19';
final _recordedAt = DateTime.utc(2026, 11, 20, 12, 5, 44);

JournalScope _scope({
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalScope(notebookId: notebookId, epochId: epochId);

final _baselineEntry = JournalEntry(
  id: 'entry-baseline',
  text: '基线条目。',
  createdAt: DateTime.utc(2026, 11, 2, 8),
  createdOn: DateTime.utc(2026, 11, 2),
  due: DateTime.utc(2026, 11, 29),
  status: EntryStatus.pending,
);

Notebook _nonEmptyBaseline() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: [_baselineEntry],
);

Notebook _emptyBaseline() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: const [],
);

/// The notebook one create projects to onto [_nonEmptyBaseline].
Notebook _projectedCreate() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: [
    _baselineEntry,
    JournalEntry(
      id: 'entry-new',
      text: '新的日记。',
      createdAt: _recordedAt,
      createdOn: DateTime.utc(2026, 11, 20),
      status: EntryStatus.explanation,
    ),
  ],
);

/// The notebook a second create projects to onto [_projectedCreate].
Notebook _projectedSecondCreate() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: [
    ..._projectedCreate().entries,
    JournalEntry(
      id: 'entry-later',
      text: '后来的日记。',
      createdAt: _recordedAt,
      createdOn: DateTime.utc(2026, 11, 20),
      status: EntryStatus.explanation,
    ),
  ],
);

ProjectionBaselineRecord _record({Notebook? notebook, JournalScope? scope}) =>
    ProjectionBaselineRecord(
      scope: scope ?? _scope(),
      notebook: notebook ?? _nonEmptyBaseline(),
    );

JournalCreateEntry _create() => JournalCreateEntry(
  notebookId: _notebookId,
  epochId: _epochId,
  actorId: 'dev-alpha',
  sequence: 1,
  operationId: 'op-create-1',
  recordedAt: _recordedAt,
  entryId: 'entry-new',
  text: '新的日记。',
  createdOn: CivilDate(2026, 11, 20),
);

JournalCreateEntry _secondCreate() => JournalCreateEntry(
  notebookId: _notebookId,
  epochId: _epochId,
  actorId: 'dev-alpha',
  sequence: 2,
  operationId: 'op-create-2',
  recordedAt: _recordedAt,
  entryId: 'entry-later',
  text: '后来的日记。',
  createdOn: CivilDate(2026, 11, 20),
);

void main() {
  late Directory dir;
  late File recordFile;
  late File envelopeFile;
  late File appNotebookFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-baseline-');
    recordFile = File('${dir.path}/projection-baseline.json');
    envelopeFile = File('${dir.path}/notebook-envelope.json');
    appNotebookFile = File('${dir.path}/notebook.json');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  ProjectionBaselineRecordStore storeFor({
    File? file,
    File? envelope,
    Future<void> Function()? beforeReplace,
    String notebookId = _notebookId,
    String epochId = _epochId,
  }) => ProjectionBaselineRecordStore(
    file ?? recordFile,
    notebookId: notebookId,
    epochId: epochId,
    envelopeFile: envelope ?? envelopeFile,
    beforeReplace: beforeReplace,
  );

  Future<List<String>> names() async {
    final list = await dir
        .list()
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .toList();
    list.sort();
    return list;
  }

  group('create', () {
    test('creates the record and it reloads identically', () async {
      final result = await storeFor().create(_record());

      expect(result.status, ProjectionBaselineWriteStatus.created);
      expect(result.isCreated, isTrue);
      expect(result.record!.hasSameContentAs(_record()), isTrue);

      final reloaded = await storeFor().read();
      expect(reloaded!.hasSameContentAs(_record()), isTrue);
      expect(reloaded.scope, _scope());
      expect(await names(), ['projection-baseline.json']);
      expect(await envelopeFile.exists(), isFalse);
    });

    test('a retry of the same baseline does not overwrite', () async {
      final first = await storeFor().create(_record());
      expect(first.isCreated, isTrue);
      final bytes = await recordFile.readAsBytes();

      final retry = await storeFor().create(_record());
      expect(retry.status, ProjectionBaselineWriteStatus.alreadyExists);
      expect(retry.matchesOffered, isTrue);
      expect(retry.record!.hasSameContentAs(_record()), isTrue);
      expect(await recordFile.readAsBytes(), bytes);
      expect(await names(), ['projection-baseline.json']);
    });

    test('a different baseline is refused and the first is kept', () async {
      await storeFor().create(_record());
      final bytes = await recordFile.readAsBytes();

      final second = await storeFor().create(
        _record(notebook: _emptyBaseline()),
      );
      expect(second.status, ProjectionBaselineWriteStatus.alreadyExists);
      expect(second.matchesOffered, isFalse);
      expect(await recordFile.readAsBytes(), bytes);
      expect((await storeFor().read())!.hasSameContentAs(_record()), isTrue);
    });

    test(
      'a record for another scope is refused and nothing is written',
      () async {
        final result = await storeFor().create(
          _record(scope: _scope(epochId: 'ep-other')),
        );
        expect(result.status, ProjectionBaselineWriteStatus.scopeMismatch);
        expect(await names(), isEmpty);
      },
    );

    test('a corrupt destination is reported and left byte-identical', () async {
      const corrupt = '{"schemaVersion":1,"format":"diary008.projection-';
      await recordFile.writeAsString(corrupt);

      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.corruptDestination);
      expect(await recordFile.readAsString(), corrupt);
      expect(await names(), ['projection-baseline.json']);
    });

    test('a non-UTF-8 destination is reported as corrupt', () async {
      final bytes = [0x7b, 0xff, 0xfe, 0x7d];
      await recordFile.writeAsBytes(bytes);

      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.corruptDestination);
      expect(await recordFile.readAsBytes(), bytes);
    });

    test('a destination that is a directory is refused', () async {
      await Directory(recordFile.path).create();
      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.corruptDestination);
      expect(await FileSystemEntity.isDirectory(recordFile.path), isTrue);
    });

    test('a stored record for another scope is a scope mismatch', () async {
      await recordFile.writeAsString(
        _record(scope: _scope(notebookId: 'nb-other')).encode(),
      );
      final bytes = await recordFile.readAsBytes();

      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.scopeMismatch);
      expect(await recordFile.readAsBytes(), bytes);
    });

    test('read throws for a corrupt destination', () async {
      await recordFile.writeAsString('not a record');
      await expectLater(
        storeFor().read(),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('read throws for a record from another scope', () async {
      await recordFile.writeAsString(
        _record(scope: _scope(epochId: 'ep-other')).encode(),
      );
      await expectLater(
        storeFor().read(),
        throwsA(isA<ProjectionBaselineScopeMismatch>()),
      );
    });

    test('read returns null for an absent destination', () async {
      expect(await storeFor().read(), isNull);
    });
  });

  group('envelope path must stay free', () {
    test('an existing envelope file refuses backfill', () async {
      await envelopeFile.writeAsString('{}');

      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.envelopeOccupied);
      expect(await envelopeFile.readAsString(), '{}');
      expect(await recordFile.exists(), isFalse);
    });

    test('an existing envelope directory refuses backfill', () async {
      await Directory(envelopeFile.path).create();
      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.envelopeOccupied);
      expect(await recordFile.exists(), isFalse);
    });

    test('an occupied envelope path decides before the destination', () async {
      // Both are occupied: the envelope check runs first, so the answer does
      // not depend on the destination's contents.
      await envelopeFile.writeAsString('{}');
      await recordFile.writeAsString('not a record');

      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.envelopeOccupied);
      expect(await recordFile.readAsString(), 'not a record');
      expect(await envelopeFile.readAsString(), '{}');
    });

    test('a dangling symlink at the envelope path refuses backfill', () async {
      try {
        await Link(envelopeFile.path).create('${dir.path}/absent-target.json');
      } on FileSystemException {
        // Platforms without symlink support skip this shape.
        return;
      }
      final result = await storeFor().create(_record());
      expect(result.status, ProjectionBaselineWriteStatus.envelopeOccupied);
      expect(await recordFile.exists(), isFalse);
    });

    test('the record path and envelope path must differ', () {
      expect(() => storeFor(envelope: recordFile), throwsArgumentError);
      // A lexical `..` spelling of the same file is the same path.
      expect(
        () => storeFor(
          envelope: File('${dir.path}/sub/../projection-baseline.json'),
        ),
        throwsArgumentError,
      );
    });

    test('a distinct envelope path is accepted', () {
      expect(storeFor(), isNotNull);
      expect(
        storeFor(envelope: File('${dir.path}/other-envelope.json')),
        isNotNull,
      );
    });

    test('notebook.json is refused as either path, in any ASCII case', () {
      for (final name in ['notebook.json', 'Notebook.JSON', 'NOTEBOOK.json']) {
        expect(
          () => storeFor(file: File('${dir.path}/$name')),
          throwsArgumentError,
          reason: '$name must be refused as the record path',
        );
        expect(
          () => storeFor(envelope: File('${dir.path}/$name')),
          throwsArgumentError,
          reason: '$name must be refused as the envelope path',
        );
      }
      expect(
        storeFor(file: File('${dir.path}/my-notebook.json-backup')),
        isNotNull,
      );
    });
  });

  group('interrupted writes', () {
    test(
      'a failure before the rename leaves no destination and no temp',
      () async {
        final store = storeFor(
          beforeReplace: () async => throw StateError('interrupted'),
        );
        await expectLater(store.create(_record()), throwsA(isA<StateError>()));
        expect(await recordFile.exists(), isFalse);
        expect(await names(), isEmpty);
      },
    );

    test(
      'the same store retries after the interruption and creates once',
      () async {
        var attempts = 0;
        final store = storeFor(
          beforeReplace: () async {
            attempts++;
            if (attempts == 1) throw StateError('interrupted');
          },
        );
        await expectLater(store.create(_record()), throwsA(isA<StateError>()));
        expect(await recordFile.exists(), isFalse);

        final retry = await store.create(_record());
        expect(retry.status, ProjectionBaselineWriteStatus.created);
        expect(attempts, 2);
        expect(await names(), ['projection-baseline.json']);
        expect((await storeFor().read())!.hasSameContentAs(_record()), isTrue);
      },
    );

    test(
      'a destination that appears before the rename is not overwritten',
      () async {
        final contender = _record(notebook: _emptyBaseline());
        final store = storeFor(
          beforeReplace: () async {
            await recordFile.writeAsString(contender.encode());
          },
        );

        final result = await store.create(_record());
        expect(result.status, ProjectionBaselineWriteStatus.alreadyExists);
        expect(result.matchesOffered, isFalse);
        expect((await storeFor().read())!.hasSameContentAs(contender), isTrue);
        expect(await names(), ['projection-baseline.json']);
      },
    );
  });

  group('same-isolate contenders', () {
    test('two stores on one normalized path create exactly once', () async {
      // A `..` spelling and a direct spelling normalize to one key.
      await Directory('${dir.path}/sub').create();
      final other = File('${dir.path}/sub/../projection-baseline.json');

      final results = await Future.wait([
        storeFor().create(_record()),
        storeFor(file: other).create(_record(notebook: _emptyBaseline())),
      ]);

      expect(results.where((result) => result.isCreated), hasLength(1));
      expect(
        results.where(
          (result) =>
              result.status == ProjectionBaselineWriteStatus.alreadyExists,
        ),
        hasLength(1),
      );
      final stored = (await storeFor().read())!;
      final offered = [_record(), _record(notebook: _emptyBaseline())];
      expect(
        offered.any((candidate) => stored.hasSameContentAs(candidate)),
        isTrue,
      );
      expect(await names(), ['projection-baseline.json', 'sub']);
    });

    test('a contender that loses keeps the winner bytes', () async {
      final results = await Future.wait([
        storeFor().create(_record()),
        storeFor(file: File(recordFile.path))
            .create(_record(notebook: _emptyBaseline())),
      ]);

      expect(results.where((result) => result.isCreated), hasLength(1));
      final winner = results.firstWhere((result) => result.isCreated);
      expect(await recordFile.readAsString(), winner.record!.encode());
    });
  });

  group('seeding a projection-validated store from the persisted record', () {
    NotebookEnvelope firstEnvelope(Notebook notebook) => NotebookEnvelope(
      revision: 1,
      notebook: notebook,
      journal: Journal(notebookId: _notebookId, epochId: _epochId),
    );

    AtomicNotebookStore seededStore(ProjectionBaselineRecord record) =>
        AtomicNotebookStore.projectionValidated(
          envelopeFile,
          scope: _scope(),
          baseline: JournalProjectionBaseline(
            notebook: record.notebook,
            scope: record.scope,
          ),
        );

    test('revision 1 binds, then revision 2 reopens from the record', () async {
      expect((await storeFor().create(_record())).isCreated, isTrue);
      final persisted = (await storeFor().read())!;

      final base = firstEnvelope(persisted.notebook);
      await envelopeFile.writeAsString(base.encode());
      expect(
        persisted.verifyEnvelope(base),
        ProjectionBaselineVerification.valid,
      );

      final committed = await seededStore(
        persisted,
      ).commit(base: base, notebook: _projectedCreate(), operation: _create());
      expect(committed.status, EnvelopeCommitStatus.committed);
      expect(committed.envelope!.revision, 2);

      // Reopened from disk, the persisted record still verifies revision 2.
      // A revision-1-only loader would refuse this.
      final reopenedRecord = (await storeFor().read())!;
      final reopenedEnvelope = await AtomicNotebookStore(
        envelopeFile,
        scope: _scope(),
      ).read();
      expect(reopenedEnvelope!.revision, 2);
      expect(reopenedEnvelope.notebook.entries.length, 2);
      expect(
        reopenedRecord.verifyEnvelope(reopenedEnvelope),
        ProjectionBaselineVerification.valid,
      );

      // A fresh store seeded from the record continues at revision 3.
      final next = await seededStore(reopenedRecord).commit(
        base: reopenedEnvelope,
        notebook: _projectedSecondCreate(),
        operation: _secondCreate(),
      );
      expect(next.status, EnvelopeCommitStatus.committed);
      expect(next.envelope!.revision, 3);
      expect(
        reopenedRecord.verifyEnvelope(next.envelope!),
        ProjectionBaselineVerification.valid,
      );
    });

    test(
      'replay is anchored to the persisted baseline, not to the envelope',
      () async {
        expect((await storeFor().create(_record())).isCreated, isTrue);
        final persisted = (await storeFor().read())!;
        final envelope = NotebookEnvelope(
          revision: 2,
          notebook: _projectedCreate(),
          journal: Journal(
            notebookId: _notebookId,
            epochId: _epochId,
            operations: [_create()],
          ),
        );

        expect(
          persisted.verifyEnvelope(envelope),
          ProjectionBaselineVerification.valid,
        );
        // The same envelope against a baseline that lost the pre-existing entry
        // does not project to the same snapshot, so the record is load-bearing.
        expect(
          _record(notebook: _emptyBaseline()).verifyEnvelope(envelope),
          ProjectionBaselineVerification.snapshotMismatch,
        );
      },
    );

    test('a revision 1 envelope with a non-empty journal is refused', () async {
      expect((await storeFor().create(_record())).isCreated, isTrue);
      final persisted = (await storeFor().read())!;
      final envelope = NotebookEnvelope(
        revision: 1,
        notebook: persisted.notebook,
        journal: Journal(
          notebookId: _notebookId,
          epochId: _epochId,
          operations: [_create()],
        ),
      );
      expect(
        persisted.verifyEnvelope(envelope),
        ProjectionBaselineVerification.initialJournalNotEmpty,
      );
    });
  });

  group('no production path is touched', () {
    test('notebook.json and the envelope stay untouched', () async {
      const appBytes = '{"schemaVersion":4,"volume":2,"entries":[]}';
      await appNotebookFile.writeAsString(appBytes);

      expect((await storeFor().create(_record())).isCreated, isTrue);
      expect(await appNotebookFile.readAsString(), appBytes);
      expect(await envelopeFile.exists(), isFalse);
      expect(await names(), ['notebook.json', 'projection-baseline.json']);
    });

    test('the record file is not a loadable notebook envelope', () async {
      await storeFor().create(_record());
      final text = await recordFile.readAsString();
      expect(
        () => NotebookEnvelope.decode(text),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('the record file is not an atomic-store document', () async {
      await storeFor().create(_record());
      final store = AtomicNotebookStore(envelopeFile, scope: _scope());
      // The envelope path is still absent, so the store reports nothing to
      // update rather than reading the baseline as its own document.
      expect(await store.read(), isNull);
    });
  });
}

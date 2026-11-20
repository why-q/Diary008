import 'dart:io';

import 'package:diary008/journal/atomic_notebook_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_projection_gate.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-91bd';
const _epochId = 'ep-04';
final _recordedAt = DateTime.utc(2026, 11, 20, 10, 0, 5);
const _volume = 2;

JournalScope _scope({
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalScope(notebookId: notebookId, epochId: epochId);

JournalCreateEntry _create({
  String operationId = 'op-create-1',
  String entryId = 'entry-new',
  String text = '新的日记。',
  String actorId = 'dev-alpha',
  int sequence = 1,
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalCreateEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: _recordedAt,
  entryId: entryId,
  text: text,
  createdOn: CivilDate(2026, 11, 20),
);

JournalReviseEntry _revise({
  String operationId = 'op-revise-1',
  String entryId = 'entry-base',
  String text = '补充说明。',
  String actorId = 'dev-alpha',
  int sequence = 2,
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalReviseEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: _recordedAt,
  entryId: entryId,
  text: text,
);

final _baseEntry = JournalEntry(
  id: 'entry-base',
  text: '原有条目。',
  createdAt: DateTime.utc(2026, 11, 1, 9),
  createdOn: DateTime.utc(2026, 11, 1),
  due: DateTime.utc(2026, 11, 30),
  status: EntryStatus.pending,
);

Notebook _baseNotebook({bool withPendingEntry = false}) => Notebook(
  volume: _volume,
  volumeName: '第二卷',
  entries: withPendingEntry ? [_baseEntry] : const [],
  sortOrder: NotebookSortOrder.writing,
);

/// The notebook a create for [text] projects to onto [_baseNotebook].
Notebook _projectedCreate(String text) => Notebook(
  volume: _volume,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
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

/// The notebook one revision projects to onto a base holding [_baseEntry].
Notebook _projectedRevision(String text) => Notebook(
  volume: _volume,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: [
    _baseEntry.withStatus(EntryStatus.revised),
    JournalEntry(
      id: '$_volume-${_recordedAt.microsecondsSinceEpoch}-op-revise-1',
      parentId: 'entry-base',
      text: text,
      createdAt: _recordedAt,
      createdOn: DateTime.utc(2026, 11, 20),
      status: EntryStatus.explanation,
    ),
  ],
);

Journal _journal(List<JournalOperation> operations) =>
    Journal(notebookId: _notebookId, epochId: _epochId, operations: operations);

NotebookEnvelope _envelope({
  int revision = 1,
  Notebook? notebook,
  List<JournalOperation> operations = const [],
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => NotebookEnvelope(
  revision: revision,
  notebook: notebook ?? _baseNotebook(),
  journal: Journal(
    notebookId: notebookId,
    epochId: epochId,
    operations: operations,
  ),
);

void main() {
  group('gate, stored side', () {
    test('an empty journal over the baseline is valid', () {
      final baseline = JournalProjectionBaseline(
        notebook: _baseNotebook(),
        scope: _scope(),
      );
      final check = checkStoredProjection(
        baseline: baseline,
        stored: _envelope(),
      );
      expect(check.status, JournalProjectionStatus.valid);
      expect(check.diagnosticCode, 'journal.projection.valid');
    });

    test('a persisted snapshot that is not the projection is refused', () {
      final baseline = JournalProjectionBaseline(
        notebook: _baseNotebook(),
        scope: _scope(),
      );
      final drifted = _envelope(
        notebook: _projectedCreate('改过的文字。'),
        operations: [_create()],
      );
      final check = checkStoredProjection(baseline: baseline, stored: drifted);
      expect(check.status, JournalProjectionStatus.baselineMismatch);
    });

    test('a persisted journal that projects to a conflict is refused', () {
      final baseline = JournalProjectionBaseline(
        notebook: _baseNotebook(),
        scope: _scope(),
      );
      // The revision targets an entry that the baseline does not contain.
      final stored = _envelope(
        notebook: _baseNotebook(),
        operations: [_revise()],
      );
      final check = checkStoredProjection(baseline: baseline, stored: stored);
      expect(check.status, JournalProjectionStatus.baselineMismatch);
    });

    test('a baseline from another scope is refused', () {
      final baseline = JournalProjectionBaseline(
        notebook: _baseNotebook(),
        scope: _scope(epochId: 'ep-other'),
      );
      final check = checkStoredProjection(
        baseline: baseline,
        stored: _envelope(),
      );
      expect(check.status, JournalProjectionStatus.scopeMismatch);
    });
  });

  group('gate, offered side', () {
    late JournalProjectionBaseline baseline;

    setUp(() {
      baseline = JournalProjectionBaseline(
        notebook: _baseNotebook(),
        scope: _scope(),
      );
    });

    test('a matching create projection is valid', () {
      final check = checkOfferedProjection(
        baseline: baseline,
        journal: _journal([_create()]),
        notebook: _projectedCreate('新的日记。'),
      );
      expect(check.status, JournalProjectionStatus.valid);
      expect(check.nextProjection, isNotNull);
    });

    test('drifted text is refused', () {
      final check = checkOfferedProjection(
        baseline: baseline,
        journal: _journal([_create()]),
        notebook: _projectedCreate('别的文字。'),
      );
      expect(check.status, JournalProjectionStatus.projectionMismatch);
    });

    test('drifted metadata is refused', () {
      final drifted = Notebook(
        volume: _volume,
        volumeName: '第三卷',
        sortOrder: NotebookSortOrder.writing,
        entries: _projectedCreate('新的日记。').entries,
      );
      final check = checkOfferedProjection(
        baseline: baseline,
        journal: _journal([_create()]),
        notebook: drifted,
      );
      expect(check.status, JournalProjectionStatus.projectionMismatch);
    });

    test('drifted sort order is refused', () {
      final drifted = Notebook(
        volume: _volume,
        volumeName: '第二卷',
        sortOrder: NotebookSortOrder.deadline,
        entries: _projectedCreate('新的日记。').entries,
      );
      final check = checkOfferedProjection(
        baseline: baseline,
        journal: _journal([_create()]),
        notebook: drifted,
      );
      expect(check.status, JournalProjectionStatus.projectionMismatch);
    });

    test('a journal for another epoch is refused', () {
      final check = checkOfferedProjection(
        baseline: baseline,
        journal: Journal(
          notebookId: _notebookId,
          epochId: 'ep-other',
          operations: [_create(epochId: 'ep-other')],
        ),
        notebook: _projectedCreate('新的日记。'),
      );
      expect(check.status, JournalProjectionStatus.scopeMismatch);
    });

    test('an operation that cannot be projected is a conflict, not drift', () {
      final check = checkOfferedProjection(
        baseline: baseline,
        journal: _journal([_revise(entryId: 'entry-absent')]),
        notebook: _baseNotebook(),
      );
      expect(check.status, JournalProjectionStatus.projectionConflict);
      expect(check.nextProjection!.hasConflicts, isTrue);
    });

    test('competing actors on one entry are a conflict', () {
      final competing = [
        _revise(operationId: 'op-a', actorId: 'dev-alpha', sequence: 2),
        _revise(operationId: 'op-b', actorId: 'dev-beta', sequence: 1),
      ];
      final baselineWithEntry = JournalProjectionBaseline(
        notebook: _baseNotebook(withPendingEntry: true),
        scope: _scope(),
      );
      final check = checkOfferedProjection(
        baseline: baselineWithEntry,
        journal: _journal(competing),
        notebook: _projectedRevision('补充说明。'),
      );
      expect(check.status, JournalProjectionStatus.projectionConflict);
    });
  });

  group('gate, composed', () {
    test('the stored side is decided before the offered side', () {
      final baseline = JournalProjectionBaseline(
        notebook: _baseNotebook(),
        scope: _scope(),
      );
      final stored = _envelope(
        notebook: _projectedCreate('改过的文字。'),
        operations: [_create()],
      );
      final check = checkProjectionBackedSnapshots(
        baseline: baseline,
        stored: stored,
        journal: _journal([
          _create(),
          _create(operationId: 'op-2', entryId: 'entry-two', sequence: 2),
        ]),
        notebook: _projectedCreate('别的文字。'),
      );
      expect(check.status, JournalProjectionStatus.baselineMismatch);
      expect(check.nextProjection, isNull);
    });
  });

  group('baseline preconditions', () {
    test('a snapshot with duplicate entry ids is refused at construction', () {
      final duplicated = Notebook(
        volume: _volume,
        entries: [_baseEntry, _baseEntry],
      );
      expect(
        () => JournalProjectionBaseline(notebook: duplicated, scope: _scope()),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a snapshot with a due-less pending entry is refused', () {
      final invalid = Notebook(
        volume: _volume,
        entries: [
          JournalEntry(
            id: 'entry-x',
            text: '文字。',
            createdAt: DateTime.utc(2026, 11, 1),
            createdOn: DateTime.utc(2026, 11, 1),
            status: EntryStatus.pending,
          ),
        ],
      );
      expect(
        () => JournalProjectionBaseline(notebook: invalid, scope: _scope()),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });

  group('store, projection-validated commits', () {
    late Directory dir;
    late File envelopeFile;
    late File appNotebookFile;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('diary-projection-');
      envelopeFile = File('${dir.path}/notebook-envelope.json');
      appNotebookFile = File('${dir.path}/notebook.json');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    AtomicNotebookStore validated(Notebook baselineNotebook) =>
        AtomicNotebookStore.projectionValidated(
          envelopeFile,
          scope: _scope(),
          baseline: JournalProjectionBaseline(
            notebook: baselineNotebook,
            scope: _scope(),
          ),
        );

    Future<void> seed(NotebookEnvelope envelope) =>
        envelopeFile.writeAsString(envelope.encode());

    Future<List<String>> names() async =>
        (await dir.list().map((entity) => entity.path.split('/').last).toList())
          ..sort();

    test('a create that matches the projection commits', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());

      final result = await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.committed);
      expect(result.envelope!.revision, 2);
      final reloaded = await store.read();
      expect(reloaded!.revision, 2);
      expect(reloaded.journal.length, 1);
      expect(reloaded.notebook.entries.single.id, 'entry-new');
      expect(reloaded.notebook.entries.single.text, '新的日记。');
      expect(await names(), ['notebook-envelope.json']);
    });

    test('a revision that matches the projection commits', () async {
      final baseNotebook = _baseNotebook(withPendingEntry: true);
      final base = _envelope(notebook: baseNotebook);
      await seed(base);
      final store = validated(baseNotebook);

      final result = await store.commit(
        base: base,
        notebook: _projectedRevision('补充说明。'),
        operation: _revise(),
      );

      expect(result.status, EnvelopeCommitStatus.committed);
      final reloaded = await store.read();
      expect(reloaded!.notebook.entries.length, 2);
      expect(reloaded.notebook.entries.first.status, EntryStatus.revised);
      expect(reloaded.notebook.entries.last.parentId, 'entry-base');
    });

    test(
      'drifted offered text is refused before anything is written',
      () async {
        await seed(_envelope());
        final store = validated(_baseNotebook());
        final before = await envelopeFile.readAsString();

        final result = await store.commit(
          base: _envelope(),
          notebook: _projectedCreate('别的文字。'),
          operation: _create(),
        );

        expect(result.status, EnvelopeCommitStatus.projectionMismatch);
        expect(result.reason, 'journal.projection.projectionMismatch');
        expect(result.isCommitted, isFalse);
        expect(await envelopeFile.readAsString(), before);
        expect(await names(), ['notebook-envelope.json']);
      },
    );

    test('drifted offered metadata is refused', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());
      final drifted = Notebook(
        volume: _volume,
        volumeName: '另一个卷名',
        sortOrder: NotebookSortOrder.writing,
        entries: _projectedCreate('新的日记。').entries,
      );

      final result = await store.commit(
        base: _envelope(),
        notebook: drifted,
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(await names(), ['notebook-envelope.json']);
    });

    test('an already corrupt persisted projection is refused', () async {
      final corrupt = _envelope(
        notebook: _projectedCreate('被改过的文字。'),
        operations: [_create()],
      );
      await seed(corrupt);
      final store = validated(_baseNotebook());
      final before = await envelopeFile.readAsString();

      final result = await store.commit(
        base: corrupt,
        notebook: _projectedCreate('新的日记。'),
        operation: _create(operationId: 'op-create-2', entryId: 'entry-two'),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.reason, 'journal.projection.baselineMismatch');
      expect(await envelopeFile.readAsString(), before);
      expect(await names(), ['notebook-envelope.json']);
    });

    test(
      'a replay is refused when the persisted projection is corrupt',
      () async {
        final corrupt = _envelope(
          notebook: _projectedCreate('被改过的文字。'),
          operations: [_create()],
        );
        await seed(corrupt);
        final store = validated(_baseNotebook());
        final before = await envelopeFile.readAsString();

        // The operation is already stored, so admission alone would answer
        // noChange. The persisted projection is checked first instead.
        final result = await store.commit(
          base: corrupt,
          notebook: _projectedCreate('被改过的文字。'),
          operation: _create(),
        );

        expect(result.status, EnvelopeCommitStatus.projectionMismatch);
        expect(result.reason, 'journal.projection.baselineMismatch');
        expect(await envelopeFile.readAsString(), before);
      },
    );

    test(
      'an operation whose effect is absent from the snapshot is refused',
      () async {
        final base = _envelope(notebook: _baseNotebook(withPendingEntry: true));
        await seed(base);
        final store = validated(_baseNotebook(withPendingEntry: true));
        final before = await envelopeFile.readAsString();

        final result = await store.commit(
          base: base,
          notebook: _baseNotebook(withPendingEntry: true),
          operation: _revise(),
        );

        expect(result.status, EnvelopeCommitStatus.projectionMismatch);
        expect(await envelopeFile.readAsString(), before);
      },
    );

    test('a persisted metadata drift is refused', () async {
      final driftedNotebook = Notebook(
        volume: _volume,
        volumeName: '被改过的卷名',
        sortOrder: NotebookSortOrder.writing,
        entries: _projectedCreate('新的日记。').entries,
      );
      final drifted = _envelope(
        notebook: driftedNotebook,
        operations: [_create()],
      );
      await seed(drifted);
      final store = validated(_baseNotebook());
      final before = await envelopeFile.readAsString();

      final result = await store.commit(
        base: drifted,
        notebook: driftedNotebook,
        operation: _create(operationId: 'op-create-2', entryId: 'entry-two'),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.reason, 'journal.projection.baselineMismatch');
      expect(await envelopeFile.readAsString(), before);
    });

    test('an unknown revision target is a projection conflict', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());
      final before = await envelopeFile.readAsString();

      final result = await store.commit(
        base: _envelope(),
        notebook: _baseNotebook(),
        operation: _revise(entryId: 'entry-absent'),
      );

      expect(result.status, EnvelopeCommitStatus.projectionConflict);
      expect(result.reason, 'journal.projection.projectionConflict');
      expect(await envelopeFile.readAsString(), before);
      expect(await names(), ['notebook-envelope.json']);
    });

    test('competing edits are a projection conflict', () async {
      final baseNotebook = _baseNotebook(withPendingEntry: true);
      final first = _envelope(notebook: baseNotebook);
      await seed(first);
      final store = validated(baseNotebook);

      // The first actor commits a revision.
      final committed = await store.commit(
        base: first,
        notebook: _projectedRevision('补充说明。'),
        operation: _revise(),
      );
      expect(committed.status, EnvelopeCommitStatus.committed);
      final afterFirst = await envelopeFile.readAsString();

      // The second actor revises the same entry, which replay keeps but flags.
      final second = JournalReviseEntry(
        notebookId: _notebookId,
        epochId: _epochId,
        actorId: 'dev-beta',
        sequence: 1,
        operationId: 'op-revise-2',
        recordedAt: _recordedAt,
        entryId: 'entry-base',
        text: '另一个补充。',
      );
      final result = await store.commit(
        base: committed.envelope!,
        notebook: _projectedRevision('另一个补充。'),
        operation: second,
      );

      expect(result.status, EnvelopeCommitStatus.projectionConflict);
      expect(await envelopeFile.readAsString(), afterFirst);
      expect(await names(), ['notebook-envelope.json']);
    });

    test('a retried operation reports no change and writes nothing', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());
      final first = await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );
      expect(first.status, EnvelopeCommitStatus.committed);
      final afterFirst = await envelopeFile.readAsString();

      final retry = await store.commit(
        base: first.envelope!,
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );
      expect(retry.status, EnvelopeCommitStatus.noChange);
      expect(await envelopeFile.readAsString(), afterFirst);

      final retryDrifted = await store.commit(
        base: first.envelope!,
        notebook: _projectedCreate('不同的文字。'),
        operation: _create(),
      );
      expect(retryDrifted.status, EnvelopeCommitStatus.duplicate);
      expect(await envelopeFile.readAsString(), afterFirst);
    });

    test('a first envelope that is not the baseline is refused', () async {
      final notBaseline = _envelope(notebook: _projectedCreate('新的日记。'));
      await seed(notBaseline);
      final store = validated(_baseNotebook());
      final before = await envelopeFile.readAsString();

      final result = await store.commit(
        base: notBaseline,
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );

      expect(result.status, EnvelopeCommitStatus.projectionMismatch);
      expect(result.reason, 'journal.projection.baselineMismatch');
      expect(await envelopeFile.readAsString(), before);
    });

    test('a stale base is refused before projection runs', () async {
      await seed(_envelope());
      final store = validated(_baseNotebook());
      await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );
      final afterFirst = await envelopeFile.readAsString();

      final stale = await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('另一个条目。'),
        operation: _create(operationId: 'op-create-2', entryId: 'entry-two'),
      );

      expect(stale.status, EnvelopeCommitStatus.stale);
      expect(await envelopeFile.readAsString(), afterFirst);
      expect(await names(), ['notebook-envelope.json']);
    });

    test(
      'the unvalidated store still accepts a caller-asserted snapshot',
      () async {
        await seed(_envelope());
        final store = AtomicNotebookStore(envelopeFile, scope: _scope());
        expect(store.projectionBaseline, isNull);

        final result = await store.commit(
          base: _envelope(),
          notebook: _projectedCreate('别的文字。'),
          operation: _create(),
        );

        expect(result.status, EnvelopeCommitStatus.committed);
      },
    );

    test('a baseline from another scope is refused at construction', () {
      expect(
        () => AtomicNotebookStore.projectionValidated(
          envelopeFile,
          scope: _scope(),
          baseline: JournalProjectionBaseline(
            notebook: _baseNotebook(),
            scope: _scope(notebookId: 'nb-other'),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a projection-validated store still refuses notebook.json', () {
      expect(
        () => AtomicNotebookStore.projectionValidated(
          appNotebookFile,
          scope: _scope(),
          baseline: JournalProjectionBaseline(
            notebook: _baseNotebook(),
            scope: _scope(),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('commits leave notebook.json untouched', () async {
      const appBytes = '{"schemaVersion":4,"volume":2,"entries":[]}';
      await appNotebookFile.writeAsString(appBytes);
      await seed(_envelope());
      final store = validated(_baseNotebook());

      await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('新的日记。'),
        operation: _create(),
      );
      await store.commit(
        base: _envelope(),
        notebook: _projectedCreate('别的文字。'),
        operation: _create(operationId: 'op-create-2', entryId: 'entry-two'),
      );

      expect(await appNotebookFile.readAsString(), appBytes);
    });
  });
}

import 'dart:io';

import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/epoch_history_envelope.dart';
import 'package:diary008/journal/epoch_history_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-4c71';
const _epoch = 'ep-02';
final _now = DateTime.utc(2026, 11, 19, 9, 15, 3);

JournalCreateEntry createOp({
  String operationId = 'op-1',
  int sequence = 1,
  String epochId = _epoch,
}) => JournalCreateEntry(
  notebookId: _notebook,
  epochId: epochId,
  actorId: 'dev-alpha',
  sequence: sequence,
  operationId: operationId,
  recordedAt: _now,
  entryId: 'entry-1',
  text: 'synthetic fixture text',
  createdOn: CivilDate.parse('2026-11-19'),
);

Notebook notebookWithEntry() => Notebook(
  volume: 1,
  volumeName: '第一卷',
  entries: [
    JournalEntry(
      id: 'entry-1',
      text: 'synthetic fixture text',
      createdAt: _now,
      createdOn: DateTime.utc(2026, 11, 19),
      due: DateTime.utc(2026, 11, 30),
      status: EntryStatus.pending,
    ),
  ],
);

Journal journalWithOperation({String epochId = _epoch}) {
  final journal = Journal(notebookId: _notebook, epochId: epochId);
  journal.admit(createOp(epochId: epochId));
  return journal;
}

/// A historical V2 record with content, used as a codec fixture. It is only
/// ever built and decoded as a value; no adapter can persist it.
EpochHistoryEnvelope populated() => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: 2,
    notebook: notebookWithEntry(),
    journal: journalWithOperation(),
  ),
  history: EpochHistory(notebookId: _notebook, epochs: const ['ep-01', _epoch]),
);

void main() {
  late Directory dir;
  late File file;
  late EpochHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-reset-guard-');
    file = File('${dir.path}/notebook-envelope.json');
    store = EpochHistoryStore(file, notebookId: _notebook);
    await file.writeAsString(populated().encode());
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('no store operation can persist a scope replacement', () async {
    final before = await file.readAsBytes();
    final stored = (await store.read())!;

    // A destructive reset is still expressible as a value, so a future
    // reviewed operation can be designed against it.
    final reset = stored.advance(
      revision: 3,
      notebook: Notebook.empty(),
      journal: Journal(notebookId: _notebook, epochId: 'ep-03'),
      history: stored.history.append('ep-03'),
    );
    expect(reset.envelope.notebook.entries, isEmpty);
    expect(reset.history.epochs, ['ep-01', _epoch, 'ep-03']);

    // But the adapter cannot write it: there is no operation that takes a
    // replacement document, and create refuses an existing target.
    final created = await store.create(reset);
    expect(created.status, EpochHistoryWriteStatus.alreadyExists);
    expect(await file.readAsBytes(), before);

    final after = (await store.read())!;
    expect(after.envelope.notebook.entries, hasLength(1));
    expect(after.envelope.journal.epochId, _epoch);
    expect(after.history.epochs, ['ep-01', _epoch]);
  });

  test(
    'a same-epoch drop of journal and notebook cannot be persisted',
    () async {
      final before = await file.readAsBytes();
      final stored = (await store.read())!;

      // The earlier adapter accepted this: same epoch, emptied notebook, empty
      // journal, bumped revision. That is the reproduced HOLD.
      final shrunk = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 3,
          notebook: Notebook.empty(),
          journal: Journal(notebookId: _notebook, epochId: _epoch),
        ),
        history: stored.history,
      );

      final result = await store.create(shrunk);

      expect(result.status, EpochHistoryWriteStatus.alreadyExists);
      expect(await file.readAsBytes(), before);
      expect((await store.read())!.envelope.notebook.entries, hasLength(1));
    },
  );

  test('a historical V2 record stays a single co-located document', () {
    // The reset shape is proven by the codec: notebook, journal, and ledger
    // round trip together, so a future reset cannot split across files.
    final reset = populated().advance(
      revision: 3,
      notebook: Notebook.empty(),
      journal: Journal(notebookId: _notebook, epochId: 'ep-03'),
      history: EpochHistory(
        notebookId: _notebook,
        epochs: const ['ep-01', _epoch, 'ep-03'],
      ),
    );

    final decoded = EpochHistoryEnvelope.decode(reset.encode());

    expect(decoded.hasSameContentAs(reset), isTrue);
    expect(decoded.envelope.notebook.entries, isEmpty);
    expect(decoded.envelope.journal.isEmpty, isTrue);
    expect(decoded.envelope.journal.epochId, 'ep-03');
    expect(decoded.history.epochs, ['ep-01', _epoch, 'ep-03']);
    expect(decoded.envelope.revision, 3);
  });
}

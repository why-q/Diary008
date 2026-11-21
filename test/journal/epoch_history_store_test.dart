import 'dart:convert';
import 'dart:io';

import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/epoch_history_envelope.dart';
import 'package:diary008/journal/epoch_history_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-4c71';
const _epoch = 'ep-02';

Journal emptyJournal({String epochId = _epoch}) =>
    Journal(notebookId: _notebook, epochId: epochId);

/// A valid initial document: revision 1, empty notebook, empty journal, and a
/// ledger whose newest epoch is that journal's epoch.
EpochHistoryEnvelope initial({String epochId = _epoch}) => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: 1,
    notebook: Notebook.empty(),
    journal: emptyJournal(epochId: epochId),
  ),
  history: EpochHistory(notebookId: _notebook, epochs: [epochId]),
);

void main() {
  late Directory dir;
  late File file;
  late EpochHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-epoch-');
    file = File('${dir.path}/notebook-envelope.json');
    store = EpochHistoryStore(file, notebookId: _notebook);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('creation is explicit and bounded', () {
    test('an absent target accepts exactly one initial document', () async {
      final result = await store.create(initial());

      expect(result.status, EpochHistoryWriteStatus.committed);
      expect(result.document!.envelope.revision, 1);
      expect((await store.read())!.history.epochs, [_epoch]);
    });

    test('a second create never replaces the stored document', () async {
      await store.create(initial());
      final before = await file.readAsBytes();

      final result = await store.create(initial(epochId: 'ep-03'));

      expect(result.status, EpochHistoryWriteStatus.alreadyExists);
      expect(await file.readAsBytes(), before);
      expect((await store.read())!.history.epochs, [_epoch]);
    });

    test(
      'an existing target is never bootstrapped from an empty file',
      () async {
        await file.writeAsString('');
        final result = await store.create(initial());

        expect(result.status, EpochHistoryWriteStatus.alreadyExists);
        expect(await file.readAsString(), isEmpty);
      },
    );

    test('revision 2 is not an initial document', () async {
      final document = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 2,
          notebook: Notebook.empty(),
          journal: emptyJournal(),
        ),
        history: EpochHistory(notebookId: _notebook, epochs: const [_epoch]),
      );

      final result = await store.create(document);

      expect(result.status, EpochHistoryWriteStatus.notInitializable);
      expect(await file.exists(), isFalse);
    });

    test('a non-empty notebook is not an initial document', () async {
      final document = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 1,
          notebook: Notebook(
            volume: 1,
            volumeName: '第一卷',
            entries: [
              JournalEntry(
                id: 'entry-1',
                text: 'synthetic fixture text',
                createdAt: DateTime.utc(2026, 11, 19, 9, 15, 3),
                createdOn: DateTime.utc(2026, 11, 19),
                due: DateTime.utc(2026, 11, 30),
                status: EntryStatus.pending,
              ),
            ],
          ),
          journal: emptyJournal(),
        ),
        history: EpochHistory(notebookId: _notebook, epochs: const [_epoch]),
      );

      final result = await store.create(document);

      expect(result.status, EpochHistoryWriteStatus.notInitializable);
      expect(await file.exists(), isFalse);
    });

    test('a two-entry ledger is not an initial document', () async {
      final document = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 1,
          notebook: Notebook.empty(),
          journal: emptyJournal(),
        ),
        history: EpochHistory(
          notebookId: _notebook,
          epochs: const ['ep-01', _epoch],
        ),
      );

      final result = await store.create(document);

      expect(result.status, EpochHistoryWriteStatus.notInitializable);
      expect(await file.exists(), isFalse);
    });

    test('a ledger that does not prove the journal epoch cannot be built', () {
      // Refused at construction, one layer earlier than the store: a document
      // whose ledger stops before the journal epoch cannot exist at all.
      expect(
        () => EpochHistoryEnvelope(
          envelope: NotebookEnvelope(
            revision: 1,
            notebook: Notebook.empty(),
            journal: emptyJournal(epochId: 'ep-09'),
          ),
          history: EpochHistory(notebookId: _notebook, epochs: const [_epoch]),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a document for another notebook is a scope mismatch', () async {
      final document = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 1,
          notebook: Notebook.empty(),
          journal: Journal(notebookId: 'nb-other', epochId: _epoch),
        ),
        history: EpochHistory(notebookId: 'nb-other', epochs: const [_epoch]),
      );

      final result = await store.create(document);

      expect(result.status, EpochHistoryWriteStatus.scopeMismatch);
      expect(await file.exists(), isFalse);
    });
  });

  group('no unrestricted replacement API exists', () {
    test('the store exposes read, create, and one bounded reset', () {
      // Pins the surface: a future generic replacement entry point must be a
      // deliberate, reviewed change rather than an accident.
      final source = File('lib/journal/epoch_history_store.dart')
          .readAsStringSync();

      expect(source, contains('Future<EpochHistoryWriteResult> create('));
      expect(source, contains('Future<EpochHistoryEnvelope?> read()'));
      expect(source, contains('Future<EpochResetOutcome> reset({'));
      // No entry point takes a caller-supplied replacement document, and none
      // is named commit or append.
      expect(source, isNot(contains('required EpochHistoryEnvelope next')));
      expect(
        source,
        isNot(contains('Future<EpochHistoryWriteResult> commit(')),
      );
      expect(
        source,
        isNot(contains('Future<EpochHistoryWriteResult> append(')),
      );
    });
  });

  group('legacy and malformed state fail closed', () {
    test(
      'a stored V1 envelope is historyMissing, never bootstrapped',
      () async {
        final v1 = NotebookEnvelope(
          revision: 4,
          notebook: Notebook.empty(),
          journal: emptyJournal(),
        );
        await file.writeAsString(v1.encode());
        final before = await file.readAsBytes();

        await expectLater(
          store.read(),
          throwsA(isA<EpochHistoryMissingException>()),
        );
        final result = await store.create(initial());
        expect(result.status, EpochHistoryWriteStatus.alreadyExists);
        expect(await file.readAsBytes(), before);
      },
    );

    test('a malformed stored document is never overwritten', () async {
      await file.writeAsString('{"format":"something-else"}');
      final before = await file.readAsBytes();

      await expectLater(store.read(), throwsA(isA<EnvelopeFormatException>()));
      expect(await file.readAsBytes(), before);
    });

    test('non-UTF-8 bytes are a typed failure', () async {
      await file.writeAsBytes([0xFF, 0xFE, 0x00]);
      final before = await file.readAsBytes();

      await expectLater(store.read(), throwsA(isA<EnvelopeFormatException>()));
      expect(await file.readAsBytes(), before);
    });

    test(
      'a V2 document with a broken history is damage, not historyMissing',
      () async {
        final good = initial().encode();
        final broken = good.replaceFirst(
          '"epochs":["$_epoch"]',
          '"epochs":["ep-99"]',
        );
        expect(broken, isNot(good), reason: 'fixture must actually differ');
        await file.writeAsString(broken);
        final before = await file.readAsBytes();

        await expectLater(
          store.read(),
          throwsA(isA<EnvelopeFormatException>()),
        );
        expect(await file.readAsBytes(), before);
      },
    );
  });

  group('scope is mandatory', () {
    test('a document for another notebook is refused on read', () async {
      final other = EpochHistoryEnvelope(
        envelope: NotebookEnvelope(
          revision: 1,
          notebook: Notebook.empty(),
          journal: Journal(notebookId: 'nb-other', epochId: _epoch),
        ),
        history: EpochHistory(notebookId: 'nb-other', epochs: const [_epoch]),
      );
      await file.writeAsString(other.encode());

      await expectLater(
        store.read(),
        throwsA(isA<EpochHistoryScopeMismatch>()),
      );
    });

    test('an unbound store cannot be constructed', () {
      // A store without a notebook could read or write another notebook's
      // document, so the parameter is required rather than optional.
      final dynamic constructor = EpochHistoryStore.new;
      expect(
        () => constructor(File('${dir.path}/unbound.json')),
        throwsA(isA<NoSuchMethodError>()),
      );
    });
  });

  group('target safety', () {
    test('notebook.json is refused as a target', () {
      for (final name in ['notebook.json', 'Notebook.JSON', 'NOTEBOOK.json']) {
        expect(
          () => EpochHistoryStore(
            File('${dir.path}/$name'),
            notebookId: _notebook,
          ),
          throwsA(isA<ArgumentError>()),
          reason: name,
        );
      }
    });

    test('a store never creates notebook.json', () async {
      final notebookFile = File('${dir.path}/notebook.json');
      await store.create(initial());

      expect(await notebookFile.exists(), isFalse);
      expect(await file.exists(), isTrue);
    });
  });

  group('creation is crash safe', () {
    test('an interrupted creation leaves no target and no temp file', () async {
      final failing = EpochHistoryStore(
        file,
        notebookId: _notebook,
        beforeReplace: () async => throw const FileSystemException('boom'),
      );

      final result = await failing.create(initial());

      expect(result.status, EpochHistoryWriteStatus.failed);
      expect(await file.exists(), isFalse);
      expect(
        dir.listSync().where((entity) => entity.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('a successful creation leaves no temp file behind', () async {
      await store.create(initial());

      expect(
        dir.listSync().where((entity) => entity.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('the stored bytes are valid UTF-8 JSON that decodes back', () async {
      await store.create(initial());
      final text = utf8.decode(await file.readAsBytes());

      expect(
        EpochHistoryEnvelope.decode(text).hasSameContentAs(initial()),
        isTrue,
      );
    });
  });
}

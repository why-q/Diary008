import 'dart:convert';
import 'dart:io';

import 'package:diary008/journal/epoch_history.dart';
import 'package:diary008/journal/epoch_history_barrier.dart';
import 'package:diary008/journal/epoch_history_envelope.dart';
import 'package:diary008/journal/epoch_history_reset.dart';
import 'package:diary008/journal/epoch_history_store.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-7d21';
const _epoch = 'ep-01';
const _fresh = 'ep-02';
final _now = DateTime.utc(2026, 11, 20, 14, 5, 7);

Journal emptyJournal({String epochId = _epoch}) =>
    Journal(notebookId: _notebook, epochId: epochId);

/// A valid initial document, the only shape [EpochHistoryStore.create] accepts.
EpochHistoryEnvelope initial({String epochId = _epoch}) => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: 1,
    notebook: Notebook.empty(),
    journal: emptyJournal(epochId: epochId),
  ),
  history: EpochHistory(notebookId: _notebook, epochs: [epochId]),
);

/// A synthetically seeded V2 document whose journal retains one operation. No
/// adapter creates this shape: it is written directly so the policy's pending
/// check has something real to refuse. It is a fixture, not a supported path.
EpochHistoryEnvelope withPendingOperation() => EpochHistoryEnvelope(
  envelope: NotebookEnvelope(
    revision: 1,
    notebook: Notebook.empty(),
    journal: Journal(
      notebookId: _notebook,
      epochId: _epoch,
      operations: [
        JournalCreateEntry(
          notebookId: _notebook,
          epochId: _epoch,
          actorId: 'dev-alpha',
          sequence: 1,
          operationId: 'op-1',
          recordedAt: _now,
          entryId: 'entry-a1',
          text: 'synthetic pending fixture',
          createdOn: CivilDate(2026, 11, 20),
        ),
      ],
    ),
  ),
  history: EpochHistory(notebookId: _notebook, epochs: [_epoch]),
);

Notebook backupSnapshot() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  entries: [
    JournalEntry(
      id: 'entry-b1',
      text: 'synthetic restore fixture',
      createdAt: _now,
      createdOn: DateTime.utc(2026, 11, 20),
      due: DateTime.utc(2026, 11, 30),
      status: EntryStatus.pending,
    ),
  ],
);

EpochResetExpectation expectation(
  int revision, {
  String notebookId = _notebook,
  String epochId = _epoch,
}) => EpochResetExpectation(
  notebookId: notebookId,
  revision: revision,
  epochId: epochId,
);

void main() {
  late Directory dir;
  late File file;
  late EpochHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-reset-');
    file = File('${dir.path}/notebook-envelope.json');
    store = EpochHistoryStore(file, notebookId: _notebook);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> seed(EpochHistoryEnvelope document) async {
    await file.writeAsString(document.encode(), flush: true);
  }

  List<File> tempFiles() => dir
      .listSync()
      .whereType<File>()
      .where((entity) => entity.path.endsWith('.tmp'))
      .toList();

  group('a restore replaces notebook, journal, and ledger together', () {
    test('one commit adopts the fresh epoch and empties the journal', () async {
      await store.create(initial());

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(backupSnapshot()),
      );

      expect(result.status, EpochResetStatus.committed);
      expect(result.isCommitted, isTrue);
      expect(result.revision, 2);
      expect(result.epochId, _fresh);

      final stored = (await store.read())!;
      expect(stored.envelope.revision, 2);
      expect(stored.history.epochs, [_epoch, _fresh]);
      expect(stored.envelope.journal.epochId, _fresh);
      expect(stored.envelope.journal.isEmpty, isTrue);
      expect(stored.envelope.notebook.entries.single.id, 'entry-b1');
      expect(stored.envelope.notebook.volume, 2);
      expect(tempFiles(), isEmpty);
    });

    test('the persisted snapshot is the canonical decoded payload', () async {
      await store.create(initial());
      final backup = backupSnapshot();

      await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(backup),
      );

      final expected = CanonicalSnapshot.tryCanonicalize(backup)!.notebook;
      final stored = (await store.read())!;
      expect(
        jsonEncode(stored.envelope.notebook.toJson()),
        jsonEncode(expected.toJson()),
      );
    });

    test('a wipe keeps the notebook identifier and clears data', () async {
      await store.create(initial());

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.committed);
      final stored = (await store.read())!;
      expect(stored.envelope.notebook.entries, isEmpty);
      expect(stored.envelope.notebook.archives, isEmpty);
      expect(stored.envelope.journal.epochId, _fresh);
      expect(stored.history.notebookId, _notebook);
    });

    test('chained resets append one epoch each time', () async {
      await store.create(initial());
      await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch('ep-02'),
        payload: const JournalWipePayload(),
      );
      await store.reset(
        expected: expectation(2, epochId: 'ep-02'),
        epoch: JournalResetEpoch('ep-03'),
        payload: JournalRestorePayload(backupSnapshot()),
      );
      final result = await store.reset(
        expected: expectation(3, epochId: 'ep-03'),
        epoch: JournalResetEpoch('ep-04'),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.committed);
      final stored = (await store.read())!;
      expect(stored.envelope.revision, 4);
      expect(stored.history.epochs, ['ep-01', 'ep-02', 'ep-03', 'ep-04']);
      expect(stored.envelope.journal.epochId, 'ep-04');
    });

    test('the whole reset is one document and one file', () async {
      await store.create(initial());
      await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(backupSnapshot()),
      );

      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.path, file.path);

      // One document, so one rename: notebook, journal, and ledger cannot
      // diverge across files.
      final decoded = EpochHistoryEnvelope.decode(
        utf8.decode(await file.readAsBytes()),
      );
      expect(decoded.history.epochs, [_epoch, _fresh]);
      expect(decoded.envelope.journal.epochId, _fresh);
    });
  });

  group('a reset is refused without touching the stored bytes', () {
    Future<List<int>> bytes() => file.readAsBytes();

    test('a stale revision', () async {
      await store.create(initial());
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(5),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.stale);
      expect(result.revision, 1);
      expect(result.epochId, _epoch);
      expect(await bytes(), before);
      expect(tempFiles(), isEmpty);
    });

    test('a request for another notebook is a scope mismatch', () async {
      await store.create(initial());
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(1, notebookId: 'nb-other'),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.scopeMismatch);
      expect(await bytes(), before);
    });

    test('a retained operation keeps the version 1 block', () async {
      await seed(withPendingOperation());
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.policyRefused);
      expect(result.barrier, isNotNull);
      expect(result.barrier!.barrier.reason.name, 'pendingOperations');
      expect(await bytes(), before);
      expect((await store.read())!.envelope.journal.length, 1);
    });

    test('a recorded epoch cannot be adopted again', () async {
      await store.create(initial());
      await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(2, epochId: _fresh),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.policyRefused);
      expect(await bytes(), before);
      expect((await store.read())!.history.epochs, [_epoch, _fresh]);
    });

    test('an older recorded epoch cannot be adopted again', () async {
      await store.create(initial());
      await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );
      final before = await bytes();

      // ep-01 is in the ledger but not the journal epoch, so only the ledger
      // can refuse this. It is precisely the case the version 1 helper misses.
      final result = await store.reset(
        expected: expectation(2, epochId: _fresh),
        epoch: JournalResetEpoch(_epoch),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.policyRefused);
      expect(result.barrier!.status, HistoricalBarrierStatus.freshEpochReused);
      expect(await bytes(), before);
    });

    test('an invalid restore payload', () async {
      await store.create(initial());
      final before = await bytes();
      final duplicated = Notebook(
        volume: 1,
        entries: [
          JournalEntry(
            id: 'entry-dup',
            text: 'first',
            createdAt: _now,
            createdOn: DateTime.utc(2026, 11, 20),
            due: DateTime.utc(2026, 11, 30),
            status: EntryStatus.pending,
          ),
          JournalEntry(
            id: 'entry-dup',
            text: 'second',
            createdAt: _now,
            createdOn: DateTime.utc(2026, 11, 20),
            due: DateTime.utc(2026, 11, 30),
            status: EntryStatus.pending,
          ),
        ],
      );

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: JournalRestorePayload(duplicated),
      );

      expect(result.status, EpochResetStatus.payloadInvalid);
      expect(await bytes(), before);
      expect(result.document, isNull);
    });

    test('an absent document is missing, never created', () async {
      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.missing);
      expect(await file.exists(), isFalse);
      expect(tempFiles(), isEmpty);
    });

    test('a legacy version 1 document is never upgraded', () async {
      await file.writeAsString(
        NotebookEnvelope(
          revision: 1,
          notebook: Notebook.empty(),
          journal: emptyJournal(),
        ).encode(),
        flush: true,
      );
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.legacyDocument);
      expect(await bytes(), before);
    });

    test('a malformed document is never repaired', () async {
      await file.writeAsString('{"not":"an envelope"', flush: true);
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.failed);
      expect(await bytes(), before);
    });

    test('a foreign notebook on disk is a scope mismatch', () async {
      // The document is internally consistent for nb-other, so it decodes
      // cleanly and only the store binding can refuse it.
      await file.writeAsString(
        EpochHistoryEnvelope(
          envelope: NotebookEnvelope(
            revision: 1,
            notebook: Notebook.empty(),
            journal: Journal(notebookId: 'nb-other', epochId: _epoch),
          ),
          history: EpochHistory(notebookId: 'nb-other', epochs: [_epoch]),
        ).encode(),
        flush: true,
      );
      final before = await bytes();

      final result = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.scopeMismatch);
      expect(await bytes(), before);
    });

    test('no refusal adds an epoch to the ledger', () async {
      await store.create(initial());
      final before = await store.read();

      final attempts = <EpochResetOutcome>[
        await store.reset(
          expected: expectation(9),
          epoch: JournalResetEpoch(_fresh),
          payload: const JournalWipePayload(),
        ),
        await store.reset(
          expected: expectation(1, notebookId: 'nb-other'),
          epoch: JournalResetEpoch(_fresh),
          payload: const JournalWipePayload(),
        ),
        await store.reset(
          expected: expectation(1),
          epoch: JournalResetEpoch(_epoch),
          payload: const JournalWipePayload(),
        ),
      ];

      for (final attempt in attempts) {
        expect(attempt.isCommitted, isFalse);
        expect(attempt.document, isNull);
      }
      final after = await store.read();
      expect(after!.history.epochs, before!.history.epochs);
      expect(after.envelope.revision, before.envelope.revision);
    });
  });

  group('interrupted and competing writes', () {
    test('a failed replacement leaves the document and no temp file', () async {
      await store.create(initial());
      final before = await file.readAsBytes();
      final failing = EpochHistoryStore(
        file,
        notebookId: _notebook,
        beforeReplace: () async => throw const FileSystemException('boom'),
      );

      final result = await failing.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.failed);
      expect(await file.readAsBytes(), before);
      expect(tempFiles(), isEmpty);
      expect((await store.read())!.envelope.revision, 1);
    });

    test('a retry after a failed replacement commits', () async {
      await store.create(initial());
      final failing = EpochHistoryStore(
        file,
        notebookId: _notebook,
        beforeReplace: () async => throw const FileSystemException('boom'),
      );
      await failing.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      final retried = await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(retried.status, EpochResetStatus.committed);
      expect((await store.read())!.envelope.revision, 2);
      expect(tempFiles(), isEmpty);
    });

    test(
      'a non-storage hook error propagates and cleans its temp file',
      () async {
        await store.create(initial());
        final before = await file.readAsBytes();
        final failing = EpochHistoryStore(
          file,
          notebookId: _notebook,
          beforeReplace: () async => throw StateError('hook'),
        );

        await expectLater(
          failing.reset(
            expected: expectation(1),
            epoch: JournalResetEpoch(_fresh),
            payload: const JournalWipePayload(),
          ),
          throwsA(isA<StateError>()),
        );

        expect(await file.readAsBytes(), before);
        expect(tempFiles(), isEmpty);
      },
    );

    test(
      'two stores on one path never both commit the same transition',
      () async {
        await store.create(initial());
        final other = EpochHistoryStore(file, notebookId: _notebook);

        final results = await Future.wait([
          store.reset(
            expected: expectation(1),
            epoch: JournalResetEpoch(_fresh),
            payload: const JournalWipePayload(),
          ),
          other.reset(
            expected: expectation(1),
            epoch: JournalResetEpoch(_fresh),
            payload: const JournalWipePayload(),
          ),
        ]);

        final committed = results.where((r) => r.isCommitted).toList();
        expect(committed, hasLength(1));
        expect(
          results.where((r) => r.status == EpochResetStatus.stale),
          hasLength(1),
        );
        expect((await store.read())!.history.epochs, [_epoch, _fresh]);
        expect(tempFiles(), isEmpty);
      },
    );

    test('two stores never adopt two different epochs from one base', () async {
      await store.create(initial());
      final other = EpochHistoryStore(file, notebookId: _notebook);

      final results = await Future.wait([
        store.reset(
          expected: expectation(1),
          epoch: JournalResetEpoch('ep-02'),
          payload: const JournalWipePayload(),
        ),
        other.reset(
          expected: expectation(1),
          epoch: JournalResetEpoch('ep-03'),
          payload: const JournalWipePayload(),
        ),
      ]);

      expect(results.where((r) => r.isCommitted), hasLength(1));
      final stored = (await store.read())!;
      // Exactly one epoch was adopted, and the ledger gained exactly one entry.
      expect(stored.history.epochs, hasLength(2));
      expect(stored.envelope.revision, 2);
    });

    test(
      'an external write revealed by the hook is never overwritten',
      () async {
        await store.create(initial());
        final external = EpochHistoryEnvelope(
          envelope: NotebookEnvelope(
            revision: 7,
            notebook: Notebook.empty(),
            journal: emptyJournal(),
          ),
          history: EpochHistory(notebookId: _notebook, epochs: [_epoch]),
        );
        var externalBytes = <int>[];
        final hooked = EpochHistoryStore(
          file,
          notebookId: _notebook,
          beforeReplace: () async {
            // Simulates a writer the lexical path queue cannot see.
            await file.writeAsString(external.encode(), flush: true);
            externalBytes = await file.readAsBytes();
          },
        );

        final result = await hooked.reset(
          expected: expectation(1),
          epoch: JournalResetEpoch(_fresh),
          payload: const JournalWipePayload(),
        );

        expect(result.status, EpochResetStatus.stale);
        // The external document survives byte for byte, and the outcome reports
        // what the guard actually found.
        expect(await file.readAsBytes(), externalBytes);
        expect(result.revision, 7);
        expect(result.epochId, _epoch);
        expect(tempFiles(), isEmpty);
        expect((await store.read())!.envelope.revision, 7);
      },
    );

    test('a removed target revealed by the hook is never recreated', () async {
      await store.create(initial());
      final hooked = EpochHistoryStore(
        file,
        notebookId: _notebook,
        beforeReplace: () async => file.delete(),
      );

      final result = await hooked.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      expect(result.status, EpochResetStatus.stale);
      expect(await file.exists(), isFalse);
      expect(tempFiles(), isEmpty);
    });
  });

  group('published create and target rules are unchanged', () {
    test('reset did not widen the target rule', () {
      expect(
        () => EpochHistoryStore(
          File('${dir.path}/notebook.json'),
          notebookId: _notebook,
        ),
        throwsArgumentError,
      );
    });

    test('create still refuses an existing target after a reset', () async {
      await store.create(initial());
      await store.reset(
        expected: expectation(1),
        epoch: JournalResetEpoch(_fresh),
        payload: const JournalWipePayload(),
      );

      final result = await store.create(initial(epochId: 'ep-09'));

      expect(result.status, EpochHistoryWriteStatus.alreadyExists);
      expect(result.reason, contains('never bootstrapped or replaced'));
    });

    test('create keeps its failure reason string', () async {
      final failing = EpochHistoryStore(
        file,
        notebookId: _notebook,
        beforeReplace: () async => throw const FileSystemException('boom'),
      );

      final result = await failing.create(initial());

      expect(result.status, EpochHistoryWriteStatus.failed);
      expect(
        result.reason,
        contains('creation failed with FileSystemException'),
      );
    });

    test('create has no pre-rename re-read', () async {
      // The guard belongs to reset only. A create hook that changes the target
      // keeps the published create behaviour and is not silently redefined.
      final hooked = EpochHistoryStore(
        file,
        notebookId: _notebook,
        beforeReplace: () async {
          await file.writeAsString('{"external":true}', flush: true);
        },
      );

      final result = await hooked.create(initial());

      expect(result.status, EpochHistoryWriteStatus.committed);
    });
  });

  group('the reset surface stays closed', () {
    test('no parameter accepts a replacement document', () {
      final source = File('lib/journal/epoch_history_store.dart')
          .readAsStringSync();
      final start = source.indexOf('Future<EpochResetOutcome> reset({');
      final declaration = source.substring(
        start,
        source.indexOf('}) {', start),
      );

      expect(declaration, contains('required EpochResetExpectation expected'));
      expect(declaration, contains('required JournalResetEpoch epoch'));
      expect(declaration, contains('required JournalResetPayload payload'));
      expect(declaration, isNot(contains('EpochHistoryEnvelope')));
      expect(declaration, isNot(contains('Notebook ')));
      expect(declaration, isNot(contains('Journal ')));
    });

    test('no module outside lib/journal imports the reset helper', () {
      for (final entry in Directory('lib').listSync(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.dart')) continue;
        if (entry.path.contains('/journal/')) continue;
        final text = entry.readAsStringSync();
        expect(
          text,
          isNot(contains('epoch_history_reset')),
          reason: entry.path,
        );
      }
    });
  });
}

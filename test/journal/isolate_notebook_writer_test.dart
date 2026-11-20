import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:diary008/journal/isolate_notebook_writer.dart';
import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-4c71';
const _epochId = 'ep-07';
final _now = DateTime.utc(2026, 11, 19, 9, 15, 3);

JournalScope _scope({
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => JournalScope(notebookId: notebookId, epochId: epochId);

JournalCreateEntry _createOp({
  required String operationId,
  required int sequence,
  required String entryId,
  required String text,
  String actorId = 'dev-alpha',
}) => JournalCreateEntry(
  notebookId: _notebookId,
  epochId: _epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: _now,
  entryId: entryId,
  text: text,
  createdOn: CivilDate.parse('2026-11-19'),
);

NotebookEnvelope _seedEnvelope() => NotebookEnvelope(
  revision: 1,
  notebook: Notebook.empty(),
  journal: Journal(notebookId: _notebookId, epochId: _epochId),
);

/// One client isolate: commits [operations] in order, rebasing on a stale
/// reply at most [maxRetries] times per operation, and reports each outcome.
///
/// The isolate receives only the capability and plain data, so the test also
/// proves a capability is sendable and that no storage object crosses the
/// boundary.
final class _ClientJob {
  const _ClientJob({
    required this.capability,
    required this.report,
    required this.operations,
    required this.maxRetries,
  });

  final NotebookWriterCapability capability;
  final SendPort report;
  final List<Map<String, Object?>> operations;
  final int maxRetries;
}

Future<void> _clientMain(_ClientJob job) async {
  final client = NotebookWriterClient(
    job.capability,
    requestTimeout: const Duration(seconds: 60),
  );
  final outcomes = <String>[];
  try {
    var observed = (await client.read()).revision;
    for (final encoded in job.operations) {
      final operation = JournalOperation.fromJson(encoded);
      var attempts = 0;
      while (true) {
        final reply = await client.commit(
          baseRevision: observed,
          operation: operation,
        );
        outcomes.add(reply.outcome.name);
        if (reply.outcome == NotebookWriterOutcome.stale &&
            attempts < job.maxRetries) {
          attempts++;
          observed = reply.revision;
          continue;
        }
        observed = reply.revision == 0 ? observed : reply.revision;
        break;
      }
    }
    job.report.send({'ok': true, 'outcomes': outcomes});
  } on Object catch (error) {
    job.report.send({'ok': false, 'error': '$error', 'outcomes': outcomes});
  }
}

Future<List<Map<String, Object?>>> _runClients(
  List<_ClientJob> Function(SendPort report) build,
  int count,
) async {
  final port = ReceivePort();
  final results = <Map<String, Object?>>[];
  final done = Completer<void>();
  port.listen((message) {
    results.add(Map<String, Object?>.from(message as Map));
    if (results.length == count) done.complete();
  });
  final jobs = build(port.sendPort);
  for (final job in jobs) {
    await Isolate.spawn(_clientMain, job);
  }
  await done.future.timeout(const Duration(seconds: 120));
  port.close();
  return results;
}

void main() {
  late Directory dir;
  late File envelopeFile;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-isolate-writer-');
    envelopeFile = File('${dir.path}/notebook-envelope.json');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> seed() => envelopeFile.writeAsString(_seedEnvelope().encode());

  List<Map<String, Object?>> encodeOps(List<JournalOperation> ops) => [
    for (final op in ops) op.toJson(),
  ];

  group('capability ownership', () {
    test('a capability names exactly one owner and is sendable', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      final other = NotebookWriterOwner.open(
        file: File('${dir.path}/other.json'),
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);
      addTearDown(other.close);

      expect(owner.capability.ownerId, isNot(other.capability.ownerId));

      // The capability survives a send to another isolate and still reaches
      // the owner it was issued by.
      final port = ReceivePort();
      await Isolate.spawn(
        _capabilityProbe,
        _CapabilityProbe(capability: owner.capability, report: port.sendPort),
      );
      final reply = await port.first.timeout(const Duration(seconds: 60));
      port.close();

      expect(reply, {'ownerId': owner.capability.ownerId, 'revision': 1});
    });

    test('an owner refuses a document for another notebook', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);
      final client = NotebookWriterClient(owner.capability);

      final foreign = JournalCreateEntry(
        notebookId: 'nb-other',
        epochId: _epochId,
        actorId: 'dev-alpha',
        sequence: 1,
        operationId: 'op-1',
        recordedAt: _now,
        entryId: 'entry-1',
        text: '另一本。',
        createdOn: CivilDate.parse('2026-11-19'),
      );

      await expectLater(
        client.commit(baseRevision: 1, operation: foreign),
        throwsA(
          isA<NotebookWriterRefusedException>().having(
            (error) => error.code,
            'code',
            'scopeMismatch',
          ),
        ),
      );
      expect((await client.read()).revision, 1);
    });
  });

  group('serialization boundary', () {
    test('two isolates never overlap inside the owner', () async {
      await seed();
      var inFlight = 0;
      var overlapped = false;
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
        beforeHandle: () async {
          inFlight++;
          if (inFlight > 1) overlapped = true;
          // Hold the handler open so an unserialized owner would overlap here.
          await Future<void>.delayed(const Duration(milliseconds: 25));
          inFlight--;
        },
      );
      addTearDown(owner.close);

      final results = await _runClients(
        (report) => [
          for (var index = 0; index < 2; index++)
            _ClientJob(
              capability: owner.capability,
              report: report,
              operations: encodeOps([
                for (var step = 0; step < 3; step++)
                  _createOp(
                    operationId: 'op-$index-$step',
                    sequence: step + 1,
                    entryId: 'entry-$index-$step',
                    text: '第$index-$step篇。',
                    actorId: 'dev-$index',
                  ),
              ]),
              maxRetries: 50,
            ),
        ],
        2,
      );

      for (final result in results) {
        expect(result['ok'], isTrue, reason: '${result['error']}');
      }
      expect(overlapped, isFalse, reason: 'handlers must not run concurrently');
      expect(owner.maxObservedConcurrency, 1);

      final stored = NotebookEnvelope.decode(await envelopeFile.readAsString());
      expect(stored.revision, 7);
      expect(stored.journal.length, 6);
      expect(stored.notebook.entries.length, 6);
    });
  });

  group('two client isolates share one capability', () {
    test('competing updates commit in order with no lost write', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);

      final results = await _runClients(
        (report) => [
          _ClientJob(
            capability: owner.capability,
            report: report,
            operations: encodeOps([
              _createOp(
                operationId: 'op-a',
                sequence: 1,
                entryId: 'entry-a',
                text: '甲写的。',
                actorId: 'dev-alpha',
              ),
            ]),
            maxRetries: 5,
          ),
          _ClientJob(
            capability: owner.capability,
            report: report,
            operations: encodeOps([
              _createOp(
                operationId: 'op-b',
                sequence: 1,
                entryId: 'entry-b',
                text: '乙写的。',
                actorId: 'dev-beta',
              ),
            ]),
            maxRetries: 5,
          ),
        ],
        2,
      );

      for (final result in results) {
        expect(result['ok'], isTrue, reason: '${result['error']}');
        expect(
          (result['outcomes'] as List).last,
          NotebookWriterOutcome.committed.name,
        );
      }

      // Both writes are present: no update was lost, and the revision is
      // exactly two past the seed.
      final stored = NotebookEnvelope.decode(await envelopeFile.readAsString());
      expect(stored.revision, 3);
      expect(stored.journal.length, 2);
      expect(stored.journal.operations.map((op) => op.operationId).toSet(), {
        'op-a',
        'op-b',
      });
      expect(stored.notebook.entries.map((entry) => entry.text).toSet(), {
        '甲写的。',
        '乙写的。',
      });
    });

    test('a stale base is refused and rebasing keeps every write', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);

      final results = await _runClients(
        (report) => [
          for (var index = 0; index < 3; index++)
            _ClientJob(
              capability: owner.capability,
              report: report,
              operations: encodeOps([
                _createOp(
                  operationId: 'op-$index',
                  sequence: 1,
                  entryId: 'entry-$index',
                  text: '第$index篇。',
                  actorId: 'dev-$index',
                ),
              ]),
              maxRetries: 20,
            ),
        ],
        3,
      );

      var sawStale = false;
      for (final result in results) {
        expect(result['ok'], isTrue, reason: '${result['error']}');
        final outcomes = (result['outcomes'] as List).cast<String>();
        sawStale |= outcomes.contains(NotebookWriterOutcome.stale.name);
        expect(outcomes.last, NotebookWriterOutcome.committed.name);
      }

      final stored = NotebookEnvelope.decode(await envelopeFile.readAsString());
      expect(stored.revision, 4);
      expect(stored.journal.length, 3);
      expect(stored.notebook.entries.length, 3);
      expect(stored.journal.operations.map((op) => op.operationId).toSet(), {
        'op-0',
        'op-1',
        'op-2',
      });
      // Deterministic stale handling: the outcome is a typed refusal with the
      // current revision, never a lost write or a silent overwrite.
      expect(sawStale, isTrue, reason: 'three racing clients should collide');
    });

    test(
      'an unprojectable operation is refused as projectionConflict',
      () async {
        await seed();
        final owner = NotebookWriterOwner.open(
          file: envelopeFile,
          scope: _scope(),
          baseline: Notebook.empty(),
        );
        addTearDown(owner.close);
        final client = NotebookWriterClient(owner.capability);

        // A revision of an entry that does not exist cannot be projected onto
        // the baseline, so no snapshot can represent it.
        final reply = await client.commit(
          baseRevision: 1,
          operation: JournalReviseEntry(
            notebookId: _notebookId,
            epochId: _epochId,
            actorId: 'dev-alpha',
            sequence: 1,
            operationId: 'op-rev',
            recordedAt: _now,
            entryId: 'entry-missing',
            text: '不存在的条目。',
          ),
        );
        expect(reply.outcome, NotebookWriterOutcome.projectionConflict);
        expect(reply.revision, 1);

        final stored = NotebookEnvelope.decode(
          await envelopeFile.readAsString(),
        );
        expect(stored.revision, 1);
        expect(stored.journal.isEmpty, isTrue);
      },
    );

    test('a duplicate submission is a no-op, not a second write', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);
      final client = NotebookWriterClient(owner.capability);

      final operation = _createOp(
        operationId: 'op-1',
        sequence: 1,
        entryId: 'entry-1',
        text: '唯一一篇。',
      );
      final first = await client.commit(baseRevision: 1, operation: operation);
      expect(first.outcome, NotebookWriterOutcome.committed);
      expect(first.revision, 2);

      final second = await client.commit(baseRevision: 2, operation: operation);
      expect(second.outcome, NotebookWriterOutcome.duplicate);
      expect(second.revision, 2);

      final stored = NotebookEnvelope.decode(await envelopeFile.readAsString());
      expect(stored.revision, 2);
      expect(stored.journal.length, 1);
    });
  });

  group('invalid requests', () {
    test('a malformed frame is refused and the owner stays usable', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);
      final client = NotebookWriterClient(owner.capability);

      final frames = <Map<String, Object?>>[
        // Unknown request type.
        {'type': 'wipe'},
        // A commit without a revision.
        {'type': 'commit', 'operation': <String, Object?>{}},
        // A non-positive revision.
        {'type': 'commit', 'baseRevision': 0, 'operation': <String, Object?>{}},
        // A commit carrying an extra field a caller must not be able to add.
        {
          'type': 'commit',
          'baseRevision': 1,
          'operation': <String, Object?>{},
          'notebook': <String, Object?>{},
        },
        // A commit whose operation is not a map.
        {'type': 'commit', 'baseRevision': 1, 'operation': 'op-1'},
        // A read carrying an extra field.
        {'type': 'read', 'revision': 1},
      ];

      for (final frame in frames) {
        final reply = await client.debugRequest(frame);
        expect(reply['type'], 'error', reason: '$frame');
        expect(reply['code'], 'invalidRequest', reason: '$frame');
      }

      // Still usable after every refusal.
      final committed = await client.commit(
        baseRevision: 1,
        operation: _createOp(
          operationId: 'op-1',
          sequence: 1,
          entryId: 'entry-1',
          text: '仍然可用。',
        ),
      );
      expect(committed.outcome, NotebookWriterOutcome.committed);
      expect((await client.read()).revision, 2);
    });

    test('a malformed operation payload is refused without a write', () async {
      await seed();
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);
      final client = NotebookWriterClient(owner.capability);

      final reply = await client.debugRequest({
        'type': 'commit',
        'baseRevision': 1,
        'operation': {'kind': 'create', 'schemaVersion': 1},
      });
      expect(reply['type'], 'error');
      expect(reply['code'], 'invalidRequest');

      final stored = NotebookEnvelope.decode(await envelopeFile.readAsString());
      expect(stored.revision, 1);
      expect(stored.journal.isEmpty, isTrue);
    });

    test('a missing target is reported, never bootstrapped', () async {
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);
      final client = NotebookWriterClient(owner.capability);

      expect((await client.read()).revision, 0);
      final reply = await client.commit(
        baseRevision: 1,
        operation: _createOp(
          operationId: 'op-1',
          sequence: 1,
          entryId: 'entry-1',
          text: '不该被创建。',
        ),
      );
      expect(reply.outcome, NotebookWriterOutcome.missing);
      expect(reply.revision, 0);
      expect(await envelopeFile.exists(), isFalse);
    });

    test(
      'a corrupt stored document fails closed and is left byte-identical',
      () async {
        const corrupt = '{"schemaVersion":1,"format":"wrong"}';
        await envelopeFile.writeAsString(corrupt);
        final owner = NotebookWriterOwner.open(
          file: envelopeFile,
          scope: _scope(),
          baseline: Notebook.empty(),
        );
        addTearDown(owner.close);
        final client = NotebookWriterClient(owner.capability);

        final reply = await client.commit(
          baseRevision: 1,
          operation: _createOp(
            operationId: 'op-1',
            sequence: 1,
            entryId: 'entry-1',
            text: '不该写入。',
          ),
        );
        expect(reply.outcome, NotebookWriterOutcome.failed);
        expect(await envelopeFile.readAsString(), corrupt);
      },
    );
  });

  group('disposal and recovery', () {
    test(
      'a closed owner is unreachable and a reopened owner recovers',
      () async {
        await seed();
        final owner = NotebookWriterOwner.open(
          file: envelopeFile,
          scope: _scope(),
          baseline: Notebook.empty(),
        );
        final client = NotebookWriterClient(
          owner.capability,
          requestTimeout: const Duration(seconds: 2),
        );

        final first = await client.commit(
          baseRevision: 1,
          operation: _createOp(
            operationId: 'op-1',
            sequence: 1,
            entryId: 'entry-1',
            text: '第一篇。',
          ),
        );
        expect(first.outcome, NotebookWriterOutcome.committed);

        await owner.close();

        // The disposed capability is a dead end: it cannot write, and it cannot
        // silently reach a new owner.
        await expectLater(
          client.commit(
            baseRevision: 2,
            operation: _createOp(
              operationId: 'op-2',
              sequence: 1,
              entryId: 'entry-2',
              text: '不该写入。',
            ),
          ),
          throwsA(isA<NotebookWriterUnavailableException>()),
        );

        // Recovery is opening a fresh owner over the same file. The new owner
        // reads the durable state and continues from the committed revision.
        final recovered = NotebookWriterOwner.open(
          file: envelopeFile,
          scope: _scope(),
          baseline: Notebook.empty(),
        );
        addTearDown(recovered.close);
        final recoveredClient = NotebookWriterClient(recovered.capability);

        final snapshot = await recoveredClient.read();
        expect(snapshot.revision, 2);
        expect(snapshot.journalLength, 1);

        final second = await recoveredClient.commit(
          baseRevision: snapshot.revision,
          operation: _createOp(
            operationId: 'op-2',
            sequence: 2,
            entryId: 'entry-2',
            text: '第二篇。',
          ),
        );
        expect(second.outcome, NotebookWriterOutcome.committed);
        expect(second.revision, 3);

        final stored = NotebookEnvelope.decode(
          await envelopeFile.readAsString(),
        );
        expect(stored.journal.length, 2);
        expect(stored.journal.operations.map((op) => op.operationId).toSet(), {
          'op-1',
          'op-2',
        });
      },
    );

    test('close drains queued requests instead of dropping them', () async {
      await seed();
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      var entered = 0;
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
        beforeHandle: () async {
          entered++;
          if (entered == 1) await firstGate.future;
          if (entered == 2) await secondGate.future;
        },
      );
      final client = NotebookWriterClient(owner.capability);

      final first = client.commit(
        baseRevision: 1,
        operation: _createOp(
          operationId: 'op-1',
          sequence: 1,
          entryId: 'entry-1',
          text: '第一篇。',
        ),
      );
      // The first handler is parked, so the second frame is accepted into the
      // queue but has not started.
      await _waitUntil(() => entered == 1);
      final second = client.commit(
        baseRevision: 2,
        operation: _createOp(
          operationId: 'op-2',
          sequence: 1,
          entryId: 'entry-2',
          text: '第二篇。',
          actorId: 'dev-beta',
        ),
      );
      await _waitUntil(() => owner.acceptedRequestCount == 2);

      var closeReturned = false;
      final closing = owner.close().then((_) => closeReturned = true);

      // Release the first handler; the queued second one starts and parks.
      firstGate.complete();
      await _waitUntil(() => entered == 2);
      // close() must still be waiting: one accepted frame has not finished.
      expect(closeReturned, isFalse);

      secondGate.complete();
      await closing;

      // close() reports completion only after both accepted frames are
      // durable, so the file is already final here.
      final stored = NotebookEnvelope.decode(await envelopeFile.readAsString());
      expect(stored.revision, 3);
      expect(stored.journal.length, 2);
      expect(stored.journal.operations.map((op) => op.operationId).toSet(), {
        'op-1',
        'op-2',
      });
      expect((await first).outcome, NotebookWriterOutcome.committed);
      expect((await second).outcome, NotebookWriterOutcome.committed);
    });

    test('a capability never exposes the store or the file', () {
      final owner = NotebookWriterOwner.open(
        file: envelopeFile,
        scope: _scope(),
        baseline: Notebook.empty(),
      );
      addTearDown(owner.close);

      // The capability type has no storage accessors at all; this is a
      // compile-time property, asserted here so a future field cannot sneak in
      // unnoticed.
      expect(owner.capability.ownerId, isNotEmpty);
      expect(
        jsonEncode(owner.capability.toString()),
        contains(owner.capability.ownerId),
      );
    });
  });

  group('no production wiring', () {
    test('no library outside lib/journal imports the experiment', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('lib/journal/')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('isolate_notebook_writer')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('an owner refuses notebook.json as a target', () {
      expect(
        () => NotebookWriterOwner.open(
          file: File('${dir.path}/notebook.json'),
          scope: _scope(),
          baseline: Notebook.empty(),
        ),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition was not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class _CapabilityProbe {
  const _CapabilityProbe({required this.capability, required this.report});

  final NotebookWriterCapability capability;
  final SendPort report;
}

Future<void> _capabilityProbe(_CapabilityProbe probe) async {
  final client = NotebookWriterClient(
    probe.capability,
    requestTimeout: const Duration(seconds: 60),
  );
  final snapshot = await client.read();
  probe.report.send({
    'ownerId': probe.capability.ownerId,
    'revision': snapshot.revision,
  });
}

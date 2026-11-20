import 'dart:convert';

import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/journal/notebook_envelope.dart';
import 'package:diary008/journal/projection_baseline_record.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebookId = 'nb-31c8';
const _epochId = 'ep-11';
final _recordedAt = DateTime.utc(2026, 11, 20, 11, 20, 31);

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

/// A synthetic, deliberately non-empty baseline: one pending entry in volume 2.
Notebook _nonEmptyBaseline() => Notebook(
  volume: 2,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: [_baselineEntry],
);

Notebook _emptyBaseline() =>
    Notebook(volume: 2, volumeName: '第二卷', entries: const []);

/// The notebook one create projects to onto [_nonEmptyBaseline].
Notebook _projectedCreate(String text) => Notebook(
  volume: 2,
  volumeName: '第二卷',
  sortOrder: NotebookSortOrder.writing,
  entries: [
    _baselineEntry,
    JournalEntry(
      id: 'entry-new',
      text: text,
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

NotebookEnvelope _envelope({
  int revision = 1,
  Notebook? notebook,
  List<JournalOperation> operations = const [],
  String notebookId = _notebookId,
  String epochId = _epochId,
}) => NotebookEnvelope(
  revision: revision,
  notebook: notebook ?? _nonEmptyBaseline(),
  journal: Journal(
    notebookId: notebookId,
    epochId: epochId,
    operations: operations,
  ),
);

Map<String, dynamic> _encodedRecord() =>
    jsonDecode(_record().encode()) as Map<String, dynamic>;

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

/// Encodes honestly, but reports a volume the notebook invariants refuse.
class _InvalidVolume extends Notebook {
  _InvalidVolume() : super(volume: 2, volumeName: '第二卷', entries: const []);

  @override
  int get volume => 0;
}

void main() {
  group('record codec', () {
    test('round trips with Unicode text and a non-empty baseline', () {
      final record = _record();
      final decoded = ProjectionBaselineRecord.decode(record.encode());

      expect(decoded.hasSameContentAs(record), isTrue);
      expect(decoded.scope, _scope());
      expect(decoded.notebook.entries.single.text, '基线条目。');
      expect(decoded.notebook.volumeName, '第二卷');
      expect(decoded.encode(), record.encode());
    });

    test('an empty baseline round trips too', () {
      final record = _record(notebook: _emptyBaseline());
      final decoded = ProjectionBaselineRecord.decode(record.encode());
      expect(decoded.notebook.entries, isEmpty);
      expect(decoded.hasSameContentAs(record), isTrue);
    });

    test('the document is versioned and discriminated', () {
      final json = _encodedRecord();
      expect(json['schemaVersion'], 1);
      expect(json['format'], 'diary008.projection-baseline');
      expect(json['initialRevision'], 1);
      expect(json['initialJournalOperationCount'], 0);
      expect(json['scope'], {'notebookId': _notebookId, 'epochId': _epochId});
    });

    test('an unknown key is refused without echoing it', () {
      final json = _encodedRecord();
      json['secretDiaryText'] = '不应出现';
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(
          isA<EnvelopeFormatException>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('不应出现')),
          ),
        ),
      );
    });

    test('a missing key is refused', () {
      final json = _encodedRecord();
      json.remove('initialRevision');
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('an unsupported schema version is refused', () {
      final json = _encodedRecord();
      json['schemaVersion'] = 2;
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a wrong format discriminator is refused', () {
      final json = _encodedRecord();
      json['format'] = 'diary008.notebook-envelope';
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a baseline bound to another revision is refused', () {
      for (final value in [0, 2, '1', null]) {
        final json = _encodedRecord();
        json['initialRevision'] = value;
        expect(
          () => ProjectionBaselineRecord.fromJson(json),
          throwsA(isA<EnvelopeFormatException>()),
          reason: 'initialRevision $value must be refused',
        );
      }
    });

    test('a baseline bound to a non-empty journal is refused', () {
      for (final value in [1, -1, '0', null]) {
        final json = _encodedRecord();
        json['initialJournalOperationCount'] = value;
        expect(
          () => ProjectionBaselineRecord.fromJson(json),
          throwsA(isA<EnvelopeFormatException>()),
          reason: 'initialJournalOperationCount $value must be refused',
        );
      }
    });

    test('a numeric-only scope identifier is refused', () {
      final json = _encodedRecord();
      (json['scope'] as Map<String, dynamic>)['epochId'] = '12';
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a scope with an unknown key is refused', () {
      final json = _encodedRecord();
      (json['scope'] as Map<String, dynamic>)['volume'] = 2;
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('an unsupported notebook schema version is refused', () {
      final json = _encodedRecord();
      (json['notebook'] as Map<String, dynamic>)['schemaVersion'] = 3;
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a non-canonical notebook snapshot is refused', () {
      // A non-UTC offset decodes to the same instant but re-encodes as `Z`, so
      // the stored bytes are not the canonical form of what they decode to.
      final json = _encodedRecord();
      final entries =
          (json['notebook'] as Map<String, dynamic>)['entries'] as List;
      (entries.single as Map<String, dynamic>)['createdAt'] =
          '2026-11-02T10:00:00.000+02:00';
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a snapshot violating notebook invariants is refused', () {
      // A pending entry without a due date is not a loadable notebook entry.
      final json = _encodedRecord();
      final entries =
          (json['notebook'] as Map<String, dynamic>)['entries'] as List;
      (entries.single as Map<String, dynamic>)['due'] = null;
      expect(
        () => ProjectionBaselineRecord.fromJson(json),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('malformed JSON and non-objects are refused', () {
      expect(
        () => ProjectionBaselineRecord.decode('{not json'),
        throwsA(isA<EnvelopeFormatException>()),
      );
      expect(
        () => ProjectionBaselineRecord.fromJson(const []),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });
  });

  group('construction', () {
    test('a snapshot that cannot serialize is refused', () {
      expect(
        () => ProjectionBaselineRecord(
          scope: _scope(),
          notebook: _ThrowingToJson(honest: _nonEmptyBaseline()),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('a snapshot violating notebook invariants is refused', () {
      expect(
        () => ProjectionBaselineRecord(
          scope: _scope(),
          notebook: _InvalidVolume(),
        ),
        throwsA(isA<EnvelopeFormatException>()),
      );
    });

    test('the record is detached from the caller snapshot', () {
      final source = _nonEmptyBaseline();
      final record = ProjectionBaselineRecord(
        scope: _scope(),
        notebook: source,
      );
      final before = record.encode();

      expect(identical(record.notebook, source), isFalse);
      expect(record.encode(), before);
    });

    test('a diagnostic code names only the status', () {
      for (final status in ProjectionBaselineVerification.values) {
        expect(status.diagnosticCode, 'journal.baseline.${status.name}');
        expect(status.diagnosticCode, isNot(contains('基线')));
      }
    });
  });

  group('revision 1 binding', () {
    test('an empty journal with the baseline snapshot is valid', () {
      expect(
        _record().verifyEnvelope(_envelope()),
        ProjectionBaselineVerification.valid,
      );
    });

    test('a revision 1 journal that is not empty is refused', () {
      expect(
        _record().verifyEnvelope(_envelope(operations: [_create()])),
        ProjectionBaselineVerification.initialJournalNotEmpty,
      );
    });

    test('a revision 1 snapshot that is not the baseline is refused', () {
      expect(
        _record().verifyEnvelope(_envelope(notebook: _emptyBaseline())),
        ProjectionBaselineVerification.snapshotMismatch,
      );
    });

    test('an envelope from another scope is refused', () {
      final record = _record();
      expect(
        record.verifyEnvelope(_envelope(epochId: 'ep-other')),
        ProjectionBaselineVerification.scopeMismatch,
      );
      expect(
        record.verifyEnvelope(_envelope(notebookId: 'nb-other')),
        ProjectionBaselineVerification.scopeMismatch,
      );
    });
  });

  group('later revisions replay onto the persisted baseline', () {
    test('a revision 2 create over the baseline is valid', () {
      final envelope = _envelope(
        revision: 2,
        notebook: _projectedCreate('新的日记。'),
        operations: [_create()],
      );
      expect(
        _record().verifyEnvelope(envelope),
        ProjectionBaselineVerification.valid,
      );
    });

    test('a revision 2 snapshot that drifted from replay is refused', () {
      final envelope = _envelope(
        revision: 2,
        notebook: _projectedCreate('被篡改的文字。'),
        operations: [_create()],
      );
      expect(
        _record().verifyEnvelope(envelope),
        ProjectionBaselineVerification.snapshotMismatch,
      );
    });

    test('a revision 2 journal that cannot be projected is a conflict', () {
      final envelope = _envelope(
        revision: 2,
        operations: [
          JournalReviseEntry(
            notebookId: _notebookId,
            epochId: _epochId,
            actorId: 'dev-alpha',
            sequence: 1,
            operationId: 'op-revise-1',
            recordedAt: _recordedAt,
            entryId: 'entry-absent',
            text: '补充说明。',
          ),
        ],
      );
      expect(
        _record().verifyEnvelope(envelope),
        ProjectionBaselineVerification.projectionConflict,
      );
    });

    test('replay uses the baseline, not the envelope snapshot', () {
      final envelope = _envelope(
        revision: 2,
        notebook: _projectedCreate('新的日记。'),
        operations: [_create()],
      );
      // The same envelope, judged against a baseline that lost the pre-existing
      // entry, no longer matches its projection.
      expect(
        _record(notebook: _emptyBaseline()).verifyEnvelope(envelope),
        ProjectionBaselineVerification.snapshotMismatch,
      );
    });
  });

  group('stated limits', () {
    test('a coherent record and envelope pair verifies without provenance', () {
      // Pins the documented limitation: verification is internal consistency
      // only. A different synthetic baseline with a matching envelope is
      // accepted, so this is not a defence against an external swap or a
      // rollback to an earlier coherent pair.
      final swapped = _record(notebook: _emptyBaseline());
      expect(
        swapped.verifyEnvelope(_envelope(notebook: _emptyBaseline())),
        ProjectionBaselineVerification.valid,
      );
    });
  });
}

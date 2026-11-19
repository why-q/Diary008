import 'package:diary008/journal/journal.dart';
import 'package:diary008/journal/journal_operation.dart';
import 'package:diary008/journal/journal_replay.dart';
import 'package:diary008/journal/journal_snapshot_equivalence.dart';
import 'package:diary008/journal/journal_values.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

const _notebook = 'nb-8f2c';
const _epoch = 'ep-01';
const _volume = 3;

DateTime _at(int second) => DateTime.utc(2026, 11, 19, 12, 0, second);

JournalCreateEntry _create({
  String operationId = 'op-create-a',
  String actorId = 'dev-alpha',
  int sequence = 1,
  String entryId = 'entry-new',
  String text = '新条目。',
  String createdOn = '2026-11-19',
  DateTime? recordedAt,
  String notebookId = _notebook,
  String epochId = _epoch,
}) => JournalCreateEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: recordedAt ?? _at(10),
  entryId: entryId,
  text: text,
  createdOn: CivilDate.parse(createdOn),
);

JournalReviseEntry _revise({
  String operationId = 'op-revise-a',
  String actorId = 'dev-alpha',
  int sequence = 2,
  String entryId = 'entry-pending',
  String text = '补充说明。',
  DateTime? recordedAt,
  String notebookId = _notebook,
  String epochId = _epoch,
}) => JournalReviseEntry(
  notebookId: notebookId,
  epochId: epochId,
  actorId: actorId,
  sequence: sequence,
  operationId: operationId,
  recordedAt: recordedAt ?? _at(20),
  entryId: entryId,
  text: text,
);

JournalEntry _entry({
  required String id,
  String text = '原有条目。',
  DateTime? createdAt,
  DateTime? createdOn,
  DateTime? due,
  String? parentId,
  EntryStatus status = EntryStatus.pending,
}) => JournalEntry(
  id: id,
  text: text,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 1, 9),
  createdOn: createdOn ?? DateTime.utc(2026, 11, 1),
  due: due,
  parentId: parentId,
  status: status,
);

Notebook _base({
  List<JournalEntry>? entries,
  List<NotebookArchive> archives = const [],
  String volumeName = '第三卷',
  NotebookSortOrder sortOrder = NotebookSortOrder.deadline,
}) => Notebook(
  volume: _volume,
  volumeName: volumeName,
  entries: entries ?? [_entry(id: 'entry-pending', due: DateTime.utc(2026, 12, 1))],
  sortOrder: sortOrder,
  archives: archives,
);

Journal _journal(List<JournalOperation> operations) {
  final journal = Journal(notebookId: _notebook, epochId: _epoch);
  for (final operation in operations) {
    final result = journal.admit(operation);
    expect(
      result.admission,
      JournalAdmission.appended,
      reason: 'fixture must admit ${operation.operationId}',
    );
  }
  return journal;
}

JournalReplayResult _project(Journal journal, {Notebook? base}) =>
    JournalReplay.project(
      notebookId: _notebook,
      epochId: _epoch,
      base: base ?? _base(),
      journal: journal,
    );

void main() {
  group('scope', () {
    test('rejects a journal recorded for another notebook', () {
      final journal = _journal([_create()]);

      expect(
        () => JournalReplay.project(
          notebookId: 'nb-other',
          epochId: _epoch,
          base: _base(),
          journal: journal,
        ),
        throwsA(
          isA<JournalFormatException>().having(
            (e) => e.field,
            'field',
            'notebookId',
          ),
        ),
      );
    });

    test('rejects a journal recorded for another epoch', () {
      final journal = _journal([_create()]);

      expect(
        () => JournalReplay.project(
          notebookId: _notebook,
          epochId: 'ep-02',
          base: _base(),
          journal: journal,
        ),
        throwsA(
          isA<JournalFormatException>().having((e) => e.field, 'field', 'epochId'),
        ),
      );
    });

    test('rejects invalid scope identifiers before any work', () {
      final journal = _journal([_create()]);

      expect(
        () => JournalReplay.project(
          notebookId: '2026-11-19',
          epochId: _epoch,
          base: _base(),
          journal: journal,
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('an empty journal reproduces the base exactly', () {
      final base = _base();
      final result = _project(_journal([]), base: base);

      expect(result.notebook.toJson(), base.toJson());
      expect(result.appliedOperations, isEmpty);
      expect(result.conflicts, isEmpty);
      expect(isSnapshotEquivalentToProjection(base, result), isTrue);
    });
  });

  group('creates', () {
    test('project as due-less explanations with exact id and verbatim text', () {
      const text = '  Emoji 😀, 中文, и кириллица, e\u0301  ';
      final operation = _create(
        entryId: 'entry-created',
        text: text,
        createdOn: '2026-11-17',
        recordedAt: DateTime.utc(2026, 11, 19, 23, 59, 59, 999, 999),
      );
      final result = _project(_journal([operation]));

      final created = result.notebook.entries.last;
      expect(created.id, 'entry-created');
      expect(created.text, text);
      expect(created.createdOn, DateTime.utc(2026, 11, 17));
      expect(created.createdAt, DateTime.utc(2026, 11, 19, 23, 59, 59, 999, 999));
      expect(created.due, isNull);
      expect(created.status, EntryStatus.explanation);
      expect(created.parentId, isNull);
      expect(result.notebook.volume, _volume);
      expect(result.conflicts, isEmpty);
      expect(result.appliedOperations.single, same(operation));
    });

    test('retain the explicit createdOn even when it differs from recordedAt', () {
      final result = _project(
        _journal([_create(createdOn: '2026-01-01', recordedAt: _at(5))]),
      );

      expect(result.notebook.entries.last.createdOn, DateTime.utc(2026, 1, 1));
    });

    test('collide with an existing current entry id instead of overwriting', () {
      final base = _base(
        entries: [
          _entry(id: 'entry-taken', text: '原件', due: DateTime.utc(2026, 12, 1)),
        ],
      );
      final operation = _create(entryId: 'entry-taken', text: '新的文本');
      final result = _project(_journal([operation]), base: base);

      expect(result.notebook.toJson(), base.toJson());
      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.entryIdCollision);
      expect(conflict.operation, same(operation));
      expect(conflict.operation.text, '新的文本');
      expect(conflict.target?.id, 'entry-taken');
    });

    test('collide with an archived entry id', () {
      final archived = _entry(
        id: 'entry-archived',
        text: '封存文本',
        status: EntryStatus.fulfilled,
        due: DateTime.utc(2026, 10, 1),
      );
      final base = _base(
        archives: [
          NotebookArchive(
            volume: 2,
            volumeName: '第二卷',
            entries: [archived],
            invalidatedAt: null,
            archivedAt: DateTime.utc(2026, 10, 2),
            reason: ArchiveReason.manualClosure,
            failedEntryIds: const {},
          ),
        ],
      );
      final result = _project(
        _journal([_create(entryId: 'entry-archived')]),
        base: base,
      );

      expect(result.conflicts.single.kind, JournalReplayConflictKind.entryIdCollision);
      expect(result.conflicts.single.target?.text, '封存文本');
      expect(result.notebook.archives.single.entries.single.text, '封存文本');
    });

    test('win over a supplement id the projection would generate', () {
      final base = _base();
      final revise = _revise(recordedAt: _at(20));
      final supplementId = '$_volume-${_at(20).microsecondsSinceEpoch}-op-revise-a';
      final create = _create(
        operationId: 'op-create-b',
        actorId: 'dev-beta',
        sequence: 1,
        entryId: supplementId,
        text: '抢用生成 id',
        recordedAt: _at(30),
      );
      final result = _project(_journal([revise, create]), base: base);

      // Explicit identity wins over a derived id; the revision yields.
      expect(result.appliedOperations, [create]);
      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.generatedIdCollision);
      expect(conflict.operation, same(revise));
      expect(conflict.operation.text, '补充说明。');
      expect(result.notebook.entries.map((e) => e.id), contains(supplementId));
      expect(result.notebook.entries, hasLength(2));
      expect(result.notebook.entries.first.status, EntryStatus.pending);
    });
  });

  group('revisions', () {
    test('mirror Notebook.revise with a supplement, not a replacement', () {
      final base = _base();
      final operation = _revise(text: '  补充 😀  ');
      final result = _project(_journal([operation]), base: base);

      final entries = result.notebook.entries;
      expect(entries, hasLength(2));
      expect(entries.first.id, 'entry-pending');
      expect(entries.first.text, '原有条目。');
      expect(entries.first.status, EntryStatus.revised);
      expect(entries.first.due, DateTime.utc(2026, 12, 1));
      expect(entries.last.parentId, 'entry-pending');
      expect(entries.last.text, '  补充 😀  ');
      expect(entries.last.due, isNull);
      expect(entries.last.status, EntryStatus.explanation);
      expect(entries.last.createdAt, operation.recordedAt);
      expect(result.conflicts, isEmpty);
    });

    test('use the UTC calendar date of the recorded instant for the supplement', () {
      final result = _project(
        _journal([_revise(recordedAt: DateTime.utc(2026, 11, 19, 23, 30))]),
      );

      expect(result.notebook.entries.last.createdOn, DateTime.utc(2026, 11, 19));
    });

    test('keep multiple revisions by one actor, in canonical order', () {
      final first = _revise(
        operationId: 'op-r1',
        sequence: 2,
        text: '第一次补充',
        recordedAt: _at(20),
      );
      final second = _revise(
        operationId: 'op-r2',
        sequence: 3,
        text: '第二次补充',
        recordedAt: _at(10),
      );
      final result = _project(_journal([first, second]));

      final supplements = result.notebook.entries.where(
        (e) => e.parentId == 'entry-pending',
      );
      expect(supplements.map((e) => e.text), ['第二次补充', '第一次补充']);
      expect(
        result.appliedRevisionsByEntry['entry-pending']!.map(
          (o) => o.operationId,
        ),
        ['op-r2', 'op-r1'],
      );
      expect(result.conflicts, isEmpty);
    });

    test('later revisions stay eligible after an earlier one was applied', () {
      final base = _base();
      final result = _project(
        _journal([
          _revise(operationId: 'op-r1', sequence: 2, recordedAt: _at(10)),
          _revise(operationId: 'op-r2', sequence: 3, recordedAt: _at(20)),
        ]),
        base: base,
      );

      expect(result.appliedOperations, hasLength(2));
      expect(result.conflicts, isEmpty);
      expect(
        result.notebook.entries.where((e) => e.parentId == 'entry-pending'),
        hasLength(2),
      );
    });

    test('report missing targets with the exact operation', () {
      final operation = _revise(entryId: 'entry-absent', text: '无主补充');
      final result = _project(_journal([operation]));

      expect(result.notebook.entries, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.missingTarget);
      expect(conflict.operation, same(operation));
      expect(conflict.operation.text, '无主补充');
      expect(conflict.target, isNull);
    });

    test('report archived targets', () {
      final archived = _entry(
        id: 'entry-old',
        status: EntryStatus.pending,
        due: DateTime.utc(2026, 10, 1),
      );
      final base = _base(
        archives: [
          NotebookArchive(
            volume: 2,
            entries: [archived],
            invalidatedAt: DateTime.utc(2026, 10, 2),
            archivedAt: DateTime.utc(2026, 10, 2),
            reason: ArchiveReason.missedDeadline,
            failedEntryIds: const {},
          ),
        ],
      );
      final result = _project(
        _journal([_revise(entryId: 'entry-old')]),
        base: base,
      );

      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.archivedTarget);
      expect(conflict.target?.id, 'entry-old');
      expect(result.notebook.archives.single.entries.single.status, EntryStatus.pending);
    });

    test('report ineligible non-pending targets', () {
      for (final status in [
        EntryStatus.fulfilled,
        EntryStatus.revised,
        EntryStatus.explanation,
      ]) {
        final base = _base(
          entries: [
            _entry(
              id: 'entry-pending',
              due: status == EntryStatus.explanation ? null : DateTime.utc(2026, 12, 1),
              status: status,
            ),
          ],
        );
        final result = _project(_journal([_revise()]), base: base);

        expect(
          result.conflicts.single.kind,
          JournalReplayConflictKind.ineligibleTarget,
          reason: 'status ${status.name}',
        );
        expect(result.notebook.toJson(), base.toJson());
      }
    });

    test('report due-less pending targets', () {
      final base = _base(entries: [_entry(id: 'entry-pending')]);
      final result = _project(_journal([_revise()]), base: base);

      expect(result.conflicts.single.kind, JournalReplayConflictKind.dueLessTarget);
      expect(result.notebook.toJson(), base.toJson());
    });

    test('report ambiguous targets duplicated in the base', () {
      final base = _base(
        entries: [
          _entry(id: 'entry-pending', due: DateTime.utc(2026, 12, 1)),
          _entry(id: 'entry-pending', text: '重复 id', due: DateTime.utc(2026, 12, 2)),
        ],
      );
      final result = _project(_journal([_revise()]), base: base);

      expect(result.conflicts.single.kind, JournalReplayConflictKind.ambiguousTarget);
      expect(result.notebook.toJson(), base.toJson());
    });

    test('report create-then-revise as a visible conflict', () {
      final create = _create(entryId: 'entry-fresh', text: '新条目');
      final revise = _revise(entryId: 'entry-fresh', text: '立刻补充');
      final result = _project(_journal([create, revise]));

      expect(result.appliedOperations, [create]);
      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.createThenRevise);
      expect(conflict.operation, same(revise));
      expect(conflict.operation.text, '立刻补充');
      expect(result.notebook.entries.last.status, EntryStatus.explanation);
      expect(result.notebook.entries, hasLength(2));
    });

    test('flag competing actors without choosing a winner', () {
      final alpha = _revise(
        operationId: 'op-alpha',
        actorId: 'dev-alpha',
        sequence: 2,
        text: '甲的补充',
        recordedAt: _at(20),
      );
      final beta = _revise(
        operationId: 'op-beta',
        actorId: 'dev-beta',
        sequence: 1,
        text: '乙的补充',
        recordedAt: _at(30),
      );
      final result = _project(_journal([alpha, beta]));

      expect(result.appliedOperations, [alpha, beta]);
      expect(
        result.notebook.entries.where((e) => e.parentId == 'entry-pending').map(
          (e) => e.text,
        ),
        ['甲的补充', '乙的补充'],
      );
      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.competingActors);
      expect(conflict.operation, same(alpha));
      expect(conflict.related.single, same(beta));
      expect(conflict.target?.id, 'entry-pending');
    });

    test('do not flag competing actors for a single actor', () {
      final result = _project(
        _journal([
          _revise(operationId: 'op-r1', sequence: 2, recordedAt: _at(10)),
          _revise(operationId: 'op-r2', sequence: 3, recordedAt: _at(20)),
        ]),
      );

      expect(result.conflicts, isEmpty);
    });

    test('collide when a supplement id already exists in the base', () {
      final recordedAt = _at(20);
      final supplementId =
          '$_volume-${recordedAt.microsecondsSinceEpoch}-op-revise-a';
      final base = _base(
        entries: [
          _entry(id: 'entry-pending', due: DateTime.utc(2026, 12, 1)),
          _entry(
            id: supplementId,
            text: '占位',
            status: EntryStatus.explanation,
            parentId: 'entry-pending',
          ),
        ],
      );
      final operation = _revise(recordedAt: recordedAt);
      final result = _project(_journal([operation]), base: base);

      final conflict = result.conflicts.single;
      expect(conflict.kind, JournalReplayConflictKind.generatedIdCollision);
      expect(conflict.operation, same(operation));
      expect(result.notebook.toJson(), base.toJson());
    });
  });

  group('determinism', () {
    test('every admission order yields the same notebook', () {
      final operations = <JournalOperation>[
        _create(
          operationId: 'op-c1',
          actorId: 'dev-alpha',
          sequence: 1,
          entryId: 'entry-c1',
          text: '甲的条目',
          recordedAt: _at(5),
        ),
        _create(
          operationId: 'op-c2',
          actorId: 'dev-beta',
          sequence: 1,
          entryId: 'entry-c2',
          text: '乙的条目',
          recordedAt: _at(5),
        ),
        _revise(
          operationId: 'op-r1',
          actorId: 'dev-alpha',
          sequence: 2,
          recordedAt: _at(10),
          text: '甲补充',
        ),
        _revise(
          operationId: 'op-r2',
          actorId: 'dev-beta',
          sequence: 2,
          recordedAt: _at(10),
          text: '乙补充',
        ),
        _revise(
          operationId: 'op-r3',
          actorId: 'dev-gamma',
          sequence: 1,
          entryId: 'entry-absent',
          text: '无主',
          recordedAt: _at(7),
        ),
      ];
      final expected = _project(_journal(operations));
      final expectedJson = expected.notebook.toJson();
      final expectedConflicts = [
        for (final c in expected.conflicts) '${c.kind.name}:${c.operation.operationId}',
      ];

      for (final order in _permutations(operations)) {
        final result = _project(_journal(order));
        expect(result.notebook.toJson(), expectedJson);
        expect(
          [
            for (final c in result.conflicts)
              '${c.kind.name}:${c.operation.operationId}',
          ],
          expectedConflicts,
        );
        expect(
          result.appliedOperations.map((o) => o.operationId),
          expected.appliedOperations.map((o) => o.operationId),
        );
      }
    });

    test('sort ties break on actor, sequence, then operation id', () {
      final a = _revise(
        operationId: 'op-z',
        actorId: 'dev-alpha',
        sequence: 3,
        text: 'alpha-3',
        recordedAt: _at(10),
      );
      final b = _revise(
        operationId: 'op-y',
        actorId: 'dev-beta',
        sequence: 1,
        text: 'beta-1',
        recordedAt: _at(10),
      );
      final result = _project(_journal([b, a]));

      expect(
        result.notebook.entries
            .where((e) => e.parentId == 'entry-pending')
            .map((e) => e.text),
        ['alpha-3', 'beta-1'],
      );
    });

    test('replaying the same input twice is identical', () {
      final journal = _journal([
        _create(),
        _revise(),
      ]);
      final first = _project(journal);
      final second = _project(journal);

      expect(first.notebook.toJson(), second.notebook.toJson());
      expect(
        first.accountedOperations.map((o) => o.operationId),
        second.accountedOperations.map((o) => o.operationId),
      );
    });
  });

  group('preservation', () {
    test('keeps legacy records, their order, and notebook metadata', () {
      final legacy = [
        _entry(
          id: 'legacy-1',
          text: '旧文本',
          createdAt: DateTime.utc(2025, 1, 1, 8),
          createdOn: DateTime.utc(2025, 1, 1),
          due: DateTime.utc(2026, 12, 5),
        ),
        _entry(
          id: 'legacy-2',
          text: '已完成',
          status: EntryStatus.fulfilled,
          due: DateTime.utc(2026, 1, 2),
        ),
        _entry(
          id: 'legacy-3',
          text: '说明',
          status: EntryStatus.explanation,
          parentId: 'legacy-2',
        ),
      ];
      final archive = NotebookArchive(
        volume: 2,
        volumeName: '旧卷',
        entries: [
          _entry(
            id: 'archived-1',
            text: '封存',
            status: EntryStatus.revised,
            due: DateTime.utc(2026, 2, 2),
          ),
        ],
        invalidatedAt: DateTime.utc(2026, 3, 1),
        archivedAt: DateTime.utc(2026, 3, 1),
        reason: ArchiveReason.missedDeadline,
        failedEntryIds: {'archived-1'},
      );
      final base = _base(
        entries: legacy,
        archives: [archive],
        volumeName: '  带空格的名字  ',
        sortOrder: NotebookSortOrder.writing,
      );
      final result = _project(_journal([_create(entryId: 'entry-new')]), base: base);

      expect(result.notebook.volume, base.volume);
      expect(result.notebook.volumeName, base.volumeName);
      expect(result.notebook.sortOrder, base.sortOrder);
      expect(result.notebook.archives.single.toJson(), archive.toJson());
      expect(
        result.notebook.entries.take(3).map((e) => e.toJson()),
        legacy.map((e) => e.toJson()),
      );
      expect(result.notebook.entries.last.id, 'entry-new');
    });

    test('do not mutate the base notebook or the journal', () {
      final base = _base();
      final baseJson = base.toJson();
      final journal = _journal([_create(), _revise()]);
      final journalJson = journal.toJson();
      final operations = journal.operations;

      _project(journal, base: base);

      expect(base.toJson(), baseJson);
      expect(journal.toJson(), journalJson);
      expect(journal.operations, operations);
      expect(journal.length, 2);
    });

    test('keep every accepted payload reachable', () {
      final operations = <JournalOperation>[
        _create(
          operationId: 'op-c1',
          entryId: 'entry-c1',
          text: '保留一',
          recordedAt: _at(1),
        ),
        _create(
          operationId: 'op-c2',
          actorId: 'dev-beta',
          sequence: 1,
          entryId: 'entry-pending',
          text: '撞 id 但保留',
          recordedAt: _at(2),
        ),
        _revise(operationId: 'op-r1', text: '保留补充', recordedAt: _at(3)),
        _revise(
          operationId: 'op-r2',
          actorId: 'dev-beta',
          sequence: 2,
          entryId: 'entry-missing',
          text: '保留无主',
          recordedAt: _at(4),
        ),
      ];
      final result = _project(_journal(operations));

      expect(result.hasConflicts, isTrue);
      final accounted = result.accountedOperations;
      expect(accounted.map((o) => o.operationId), [
        'op-c1',
        'op-c2',
        'op-r1',
        'op-r2',
      ]);
      expect(
        accounted.map((o) => o.text),
        containsAll(['保留一', '撞 id 但保留', '保留补充', '保留无主']),
      );
      for (final operation in operations) {
        expect(
          accounted.any((o) => o.operationId == operation.operationId),
          isTrue,
        );
      }
    });

    test('conflict diagnostics never embed diary text', () {
      final result = _project(
        _journal([
          _revise(entryId: 'entry-missing', text: '秘密文本'),
          _create(entryId: 'entry-pending', text: '另一个秘密'),
        ]),
      );

      expect(result.conflicts, hasLength(2));
      for (final conflict in result.conflicts) {
        expect(conflict.toString(), isNot(contains('秘密')));
      }
    });
  });

  group('snapshot equivalence checker', () {
    test('accepts a snapshot that matches the projection', () {
      final result = _project(_journal([_create(), _revise()]));
      final snapshot = Notebook.fromJson(result.notebook.toJson());

      expect(isSnapshotEquivalentToProjection(snapshot, result), isTrue);
    });

    test('fails closed when the projection has conflicts', () {
      final result = _project(_journal([_revise(entryId: 'entry-missing')]));

      expect(result.hasConflicts, isTrue);
      expect(isSnapshotEquivalentToProjection(result.notebook, result), isFalse);
    });

    test('rejects a drifted snapshot', () {
      final result = _project(_journal([_create()]));
      final drifted = Notebook(
        volume: result.notebook.volume,
        volumeName: result.notebook.volumeName,
        entries: [
          for (final entry in result.notebook.entries)
            JournalEntry(
              id: entry.id,
              text: '${entry.text}漂移',
              createdAt: entry.createdAt,
              createdOn: entry.createdOn,
              due: entry.due,
              parentId: entry.parentId,
              status: entry.status,
            ),
        ],
        sortOrder: result.notebook.sortOrder,
        archives: result.notebook.archives,
      );

      expect(isSnapshotEquivalentToProjection(drifted, result), isFalse);
    });

    test('rejects metadata drift', () {
      final result = _project(_journal([_create()]));
      final renamed = Notebook(
        volume: result.notebook.volume,
        volumeName: '改了名字',
        entries: result.notebook.entries,
        sortOrder: result.notebook.sortOrder,
        archives: result.notebook.archives,
      );

      expect(isSnapshotEquivalentToProjection(renamed, result), isFalse);
    });
  });
}

/// All permutations of [items]; the fixture stays small enough to enumerate.
Iterable<List<T>> _permutations<T>(List<T> items) sync* {
  if (items.length <= 1) {
    yield List.of(items);
    return;
  }
  for (var i = 0; i < items.length; i++) {
    final rest = [...items]..removeAt(i);
    for (final tail in _permutations(rest)) {
      yield [items[i], ...tail];
    }
  }
}

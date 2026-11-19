import 'dart:io';

import 'package:diary008/application/notebook_application.dart';
import 'package:diary008/application/notebook_queries.dart';
import 'package:diary008/json_notebook_repository.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/notebook_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingRepository implements NotebookRepository {
  _FailingRepository(this._inner);

  final NotebookRepository _inner;
  int saves = 0;

  @override
  Future<Notebook> load({bool migrate = true}) => _inner.load(migrate: migrate);

  @override
  Future<void> save(Notebook notebook) async {
    saves++;
    throw const FileSystemException('disk full');
  }
}

class _CountingRepository implements NotebookRepository {
  _CountingRepository(this._inner);

  final NotebookRepository _inner;
  int saves = 0;
  Notebook? lastSaved;

  @override
  Future<Notebook> load({bool migrate = true}) => _inner.load(migrate: migrate);

  @override
  Future<void> save(Notebook notebook) async {
    saves++;
    lastSaved = notebook;
    await _inner.save(notebook);
  }
}

void main() {
  final now = DateTime(2026, 10, 21, 12);

  late Directory dir;
  late NotebookRepository repository;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('diary-application-');
    repository = JsonNotebookRepository(File('${dir.path}/notebook.json'));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<NotebookApplication> open() async =>
      NotebookApplication(repository, await repository.load());

  group('commands', () {
    test(
      'add writes through the repository and advances the notebook',
      () async {
        final app = await open();

        final result = await app.addEntry(
          text: '我会考完雅思。',
          due: DateTime(2026, 11, 21),
          now: now,
        );

        expect(result.applied, isTrue);
        expect(result.notebook.entries.single.text, '我会考完雅思。');
        expect(app.notebook.entries.single.text, '我会考完雅思。');
        final stored = await repository.load();
        expect(stored.toJson(), app.notebook.toJson());
      },
    );

    test('empty text is rejected without writing', () async {
      final counting = _CountingRepository(repository);
      final app = NotebookApplication(counting, await repository.load());

      final result = await app.addEntry(
        text: '   ',
        due: DateTime(2026, 11, 21),
        now: now,
      );

      expect(result.rejected, isTrue);
      expect(result.rejection, NotebookCommandRejection.invalidArgument);
      expect(result.error, isA<ArgumentError>());
      expect(counting.saves, 0);
      expect(app.notebook.entries, isEmpty);
    });

    test('past due dates are rejected and keep the stored notebook', () async {
      final app = await open();
      await app.addEntry(text: '原有断言', due: DateTime(2026, 11, 21), now: now);
      final before = app.notebook;

      final result = await app.addEntry(
        text: '迟到的断言',
        due: DateTime(2026, 10, 20),
        now: now,
      );

      expect(result.rejected, isTrue);
      expect(result.notebook, same(before));
      expect((await repository.load()).toJson(), before.toJson());
    });

    test('revise keeps the original and appends the replacement', () async {
      final app = await open();
      await app.addEntry(text: '原断言', due: DateTime(2026, 11, 1), now: now);
      final root = app.notebook.entries.single;

      final result = await app.reviseEntry(
        entryId: root.id,
        text: '替代断言',
        due: DateTime(2026, 12, 1),
        now: now,
      );

      expect(result.applied, isTrue);
      expect(result.notebook.entries.first.status, EntryStatus.revised);
      expect(result.notebook.entries.last.parentId, root.id);
      expect((await repository.load()).toJson(), result.notebook.toJson());
    });

    test(
      'revising an already fulfilled entry is rejected as invalid state',
      () async {
        final app = await open();
        await app.addEntry(text: '断言', due: DateTime(2026, 11, 1), now: now);
        final id = app.notebook.entries.single.id;
        await app.fulfillEntry(entryId: id, now: now);
        final before = app.notebook;

        final result = await app.reviseEntry(
          entryId: id,
          text: '迟到解释',
          now: now,
        );

        expect(result.rejected, isTrue);
        expect(result.rejection, NotebookCommandRejection.invalidState);
        expect(result.notebook, same(before));
        expect((await repository.load()).toJson(), before.toJson());
      },
    );

    test('fulfillment commits once and repeats are rejected', () async {
      final app = await open();
      await app.addEntry(text: '断言', due: DateTime(2026, 11, 1), now: now);
      final id = app.notebook.entries.single.id;

      final first = await app.fulfillEntry(entryId: id, now: now);
      final second = await app.fulfillEntry(entryId: id, now: now);

      expect(first.applied, isTrue);
      expect(first.notebook.entries.single.status, EntryStatus.fulfilled);
      expect(second.rejected, isTrue);
      expect(second.notebook.entries.single.status, EntryStatus.fulfilled);
      expect(
        (await repository.load()).entries.single.status,
        EntryStatus.fulfilled,
      );
    });

    test('expiration reconciliation is a no-op before the deadline', () async {
      final counting = _CountingRepository(repository);
      final app = NotebookApplication(
        counting,
        Notebook.empty().add('未到期', DateTime(2026, 10, 21), now),
      );

      final result = await app.reconcileExpiration(
        now: DateTime(2026, 10, 21, 23, 59),
      );

      expect(result.unchanged, isTrue);
      expect(counting.saves, 0);
      expect(result.notebook.volume, 1);
    });

    test(
      'expiration reconciliation archives the volume and persists it',
      () async {
        final app = await open();
        await app.addEntry(text: '到期断言', due: DateTime(2026, 10, 21), now: now);
        final failedId = app.notebook.entries.single.id;

        final result = await app.reconcileExpiration(
          now: DateTime(2026, 10, 22),
        );

        expect(result.applied, isTrue);
        expect(result.notebook.volume, 2);
        expect(result.notebook.entries, isEmpty);
        final archive = result.notebook.archives.single;
        expect(archive.reason, ArchiveReason.missedDeadline);
        expect(archive.failedEntryIds, {failedId});
        expect((await repository.load()).toJson(), result.notebook.toJson());
      },
    );

    test(
      'sort changes persist and identical order is left untouched',
      () async {
        final counting = _CountingRepository(repository);
        final app = NotebookApplication(
          counting,
          Notebook.empty().add('断言', DateTime(2026, 11, 1), now),
        );

        final same = await app.changeSortOrder(NotebookSortOrder.writing);
        final changed = await app.changeSortOrder(NotebookSortOrder.deadline);

        expect(same.unchanged, isTrue);
        expect(changed.applied, isTrue);
        expect(counting.saves, 1);
        expect((await repository.load()).sortOrder, NotebookSortOrder.deadline);
      },
    );

    test('volume archive scope follows the domain and rejects current volume deletion', () async {
      final app = await open();
      await app.addEntry(text: '第一卷', due: DateTime(2026, 11, 1), now: now);
      final sealed = await app.startNewVolume(
        name: '第二卷',
        now: DateTime(2026, 10, 22),
      );

      expect(sealed.applied, isTrue);
      expect(sealed.notebook.volume, 2);
      expect(
        sealed.notebook.archives.single.reason,
        ArchiveReason.manualClosure,
      );

      final current = await app.deleteArchivedVolume(2);
      expect(current.rejected, isTrue);
      expect(current.notebook.volume, 2);

      final deleted = await app.deleteArchivedVolume(1);
      expect(deleted.applied, isTrue);
      expect(deleted.notebook.archives, isEmpty);
      expect((await repository.load()).toJson(), deleted.notebook.toJson());
    });

    test('replacePersisted stores a restored notebook and adopts it', () async {
      final app = await open();
      await app.addEntry(text: '旧记录', due: DateTime(2026, 11, 1), now: now);
      final restored = Notebook.empty().add('备份记录', DateTime(2026, 12, 1), now);

      await app.replacePersisted(restored);

      expect(app.notebook.toJson(), restored.toJson());
      expect((await repository.load()).toJson(), restored.toJson());
      final next = await app.addEntry(
        text: '恢复后新增',
        due: DateTime(2026, 12, 2),
        now: now,
      );
      expect(next.applied, isTrue);
      expect(next.notebook.entries.map((e) => e.text), ['备份记录', '恢复后新增']);
    });

    test(
      'failed saves leave the previous notebook in memory and on disk',
      () async {
        final failing = _FailingRepository(repository);
        final app = NotebookApplication(failing, await repository.load());
        final before = app.notebook;

        final result = await app.addEntry(
          text: '不会落盘',
          due: DateTime(2026, 11, 1),
          now: now,
        );

        expect(result.saveFailed, isTrue);
        expect(result.error, isA<FileSystemException>());
        expect(app.notebook, same(before));
        expect((await repository.load()).entries, isEmpty);
      },
    );
  });

  group('queries', () {
    test(
      'current entries are filtered and sorted by the domain order',
      () async {
        final app = await open();
        await app.addEntry(text: '较远', due: DateTime(2026, 12, 1), now: now);
        await app.addEntry(text: '较近', due: DateTime(2026, 11, 1), now: now);
        await app.changeSortOrder(NotebookSortOrder.deadline);
        final id = app.notebook.entries.first.id;
        await app.fulfillEntry(entryId: id, now: now);

        final queries = NotebookQueries(app.notebook);
        final pending = queries.currentEntries(
          filter: NotebookFilter.pending,
          now: now,
        );
        final fulfilled = queries.currentEntries(
          filter: NotebookFilter.fulfilled,
          now: now,
        );

        expect(pending.map((e) => e.text), ['较近']);
        expect(fulfilled.map((e) => e.text), ['较远']);
        expect(queries.expired(now), isFalse);
      },
    );

    test(
      'archived entries stay frozen and are scoped to their volume',
      () async {
        final app = await open();
        await app.addEntry(text: '失败', due: DateTime(2026, 10, 21), now: now);
        await app.addEntry(text: '随卷封存', due: DateTime(2026, 10, 25), now: now);
        await app.reconcileExpiration(now: DateTime(2026, 12, 1));

        final queries = NotebookQueries(app.notebook);
        final future = DateTime(2030);

        expect(
          queries
              .archivedEntries(volume: 1, filter: NotebookFilter.pending)
              .map((e) => e.text),
          ['随卷封存'],
        );
        expect(
          queries
              .archivedEntries(volume: 1, filter: NotebookFilter.unfulfilled)
              .map((e) => e.text),
          ['失败'],
        );
        expect(queries.archive(1)?.reason, ArchiveReason.missedDeadline);
        expect(queries.archive(2), isNull);
        expect(
          queries.currentEntries(filter: NotebookFilter.all, now: future),
          isEmpty,
        );
      },
    );
  });
}

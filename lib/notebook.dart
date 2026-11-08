import 'dart:math' as math;

enum EntryStatus { pending, fulfilled, revised, explanation }

enum NotebookSortOrder { writing, deadline }

enum NotebookFilter { all, pending, fulfilled, unfulfilled }

enum ArchiveReason { missedDeadline, manualClosure }

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime _civilDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
DateTime _parseCivilDate(String value) =>
    _civilDate(DateTime.parse(value.split('T').first));
String _civilText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime calendarOffset(DateTime date, {int months = 0, int years = 0}) {
  final first = DateTime(date.year + years, date.month + months);
  final lastDay = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, math.min(date.day, lastDay));
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.createdOn,
    required this.status,
    this.due,
    this.parentId,
  });
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime createdOn;
  final DateTime? due;
  final String? parentId;
  final EntryStatus status;
  DateTime get deadline => DateTime(due!.year, due!.month, due!.day + 1);
  bool isExpired(DateTime now) =>
      status == EntryStatus.pending &&
      _civilDate(now).isAfter(_civilDate(due!));
  JournalEntry withStatus(EntryStatus value) => JournalEntry(
    id: id,
    text: text,
    createdAt: createdAt,
    createdOn: createdOn,
    due: due,
    parentId: parentId,
    status: value,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'createdOn': _civilText(createdOn),
    'due': due == null ? null : _civilText(due!),
    'parentId': parentId,
    'status': status.name,
  };
  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final created = DateTime.parse(json['createdAt'] as String);
    return JournalEntry(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: created.toUtc(),
      createdOn: json['createdOn'] == null
          ? _civilDate(created.toLocal())
          : _parseCivilDate(json['createdOn'] as String),
      due: json['due'] == null ? null : _parseCivilDate(json['due'] as String),
      parentId: json['parentId'] as String?,
      status: EntryStatus.values.byName(json['status'] as String),
    );
  }
}

class _EntryGroup {
  _EntryGroup(this.index);
  final int index;
  final entries = <JournalEntry>[];
  DateTime? pendingDue;
}

List<_EntryGroup> _groupEntries(
  List<JournalEntry> entries,
  Set<String> failedIds,
) {
  final groups = <_EntryGroup>[];
  final groupByEntry = <String, _EntryGroup>{};
  for (final entry in entries) {
    var group = groupByEntry[entry.parentId];
    if (group == null) {
      group = _EntryGroup(groups.length);
      groups.add(group);
    }
    groupByEntry[entry.id] = group;
    group.entries.add(entry);
    if (entry.status == EntryStatus.pending && !failedIds.contains(entry.id)) {
      group.pendingDue = entry.due;
    }
  }
  return groups;
}

List<JournalEntry> _selectEntries(
  List<_EntryGroup> groups,
  NotebookSortOrder order,
  NotebookFilter filter,
  DateTime now,
  Set<String> failedIds, {
  bool frozen = false,
}) {
  bool matches(JournalEntry entry) => switch (filter) {
    NotebookFilter.all => true,
    NotebookFilter.pending =>
      entry.status == EntryStatus.pending &&
          !failedIds.contains(entry.id) &&
          (frozen || !entry.isExpired(now)),
    NotebookFilter.fulfilled => entry.status == EntryStatus.fulfilled,
    NotebookFilter.unfulfilled =>
      entry.status == EntryStatus.revised || failedIds.contains(entry.id),
  };
  final selected = groups.where((g) => g.entries.any(matches)).toList();
  if (order == NotebookSortOrder.deadline) {
    selected.sort((a, b) {
      final aDue = a.pendingDue;
      final bDue = b.pendingDue;
      if (aDue == null && bDue != null) return 1;
      if (aDue != null && bDue == null) return -1;
      if (aDue != null && bDue != null) {
        final byDate = aDue.compareTo(bDue);
        if (byDate != 0) return byDate;
      }
      return a.index.compareTo(b.index);
    });
  }
  return List.unmodifiable(selected.expand((group) => group.entries));
}

class NotebookArchive {
  NotebookArchive({
    required this.volume,
    this.volumeName = '',
    required List<JournalEntry> entries,
    required this.invalidatedAt,
    required this.archivedAt,
    required this.reason,
    required Set<String> failedEntryIds,
  }) : entries = List.unmodifiable(entries),
       failedEntryIds = Set.unmodifiable(failedEntryIds);
  final int volume;
  final String volumeName;
  final List<JournalEntry> entries;
  final DateTime? invalidatedAt;
  final DateTime archivedAt;
  final ArchiveReason reason;
  final Set<String> failedEntryIds;
  late final _groups = _groupEntries(entries, failedEntryIds);
  Map<String, dynamic> toJson() => {
    'volume': volume,
    'volumeName': volumeName,
    'entries': entries.map((e) => e.toJson()).toList(),
    'invalidatedAt': invalidatedAt?.toUtc().toIso8601String(),
    'archivedAt': archivedAt.toUtc().toIso8601String(),
    'reason': reason.name,
    'failedEntryIds': failedEntryIds.toList(),
  };
  factory NotebookArchive.fromJson(Map<String, dynamic> json) =>
      NotebookArchive(
        volume: json['volume'] as int,
        volumeName: json['volumeName'] as String? ?? '',
        entries: (json['entries'] as List)
            .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        invalidatedAt: json['invalidatedAt'] == null
            ? null
            : DateTime.parse(json['invalidatedAt'] as String).toUtc(),
        archivedAt: DateTime.parse(json['archivedAt'] as String).toUtc(),
        reason: ArchiveReason.values.byName(json['reason'] as String),
        failedEntryIds: (json['failedEntryIds'] as List).cast<String>().toSet(),
      );
}

class Notebook {
  static const storageVersion = 4;
  Notebook({
    required this.volume,
    this.volumeName = '',
    required List<JournalEntry> entries,
    this.sortOrder = NotebookSortOrder.writing,
    List<NotebookArchive> archives = const [],
  }) : entries = List.unmodifiable(entries),
       archives = List.unmodifiable(archives);
  factory Notebook.empty() => Notebook(volume: 1, entries: []);
  final int volume;
  final String volumeName;
  final List<JournalEntry> entries;
  final List<NotebookArchive> archives;
  final NotebookSortOrder sortOrder;
  late final _groups = _groupEntries(entries, const {});
  late final List<JournalEntry> displayEntries = viewEntries();

  Notebook withSortOrder(NotebookSortOrder order) => Notebook(
    volume: volume,
    volumeName: volumeName,
    entries: entries,
    archives: archives,
    sortOrder: order,
  );

  Notebook withVolumeName(String name) => Notebook(
    volume: volume,
    volumeName: name.trim(),
    entries: entries,
    archives: archives,
    sortOrder: sortOrder,
  );

  Notebook startNewVolume(String name, DateTime now) {
    if (expired(now)) throw StateError('本卷已到期');
    return Notebook(
      volume: volume + 1,
      volumeName: name.trim(),
      entries: [],
      sortOrder: sortOrder,
      archives: [
        ...archives,
        NotebookArchive(
          volume: volume,
          volumeName: volumeName,
          entries: entries,
          invalidatedAt: null,
          archivedAt: now,
          reason: ArchiveReason.manualClosure,
          failedEntryIds: const {},
        ),
      ],
    );
  }

  Notebook deleteArchivedVolume(int volume) {
    if (this.volume == volume ||
        !archives.any((archive) => archive.volume == volume)) {
      throw StateError('只能删除已封存的卷');
    }
    return Notebook(
      volume: this.volume > volume ? this.volume - 1 : this.volume,
      volumeName: volumeName,
      entries: entries,
      sortOrder: sortOrder,
      archives: [
        for (final archive in archives)
          if (archive.volume != volume)
            archive.volume < volume
                ? archive
                : NotebookArchive(
                    volume: archive.volume - 1,
                    volumeName: archive.volumeName,
                    entries: archive.entries,
                    invalidatedAt: archive.invalidatedAt,
                    archivedAt: archive.archivedAt,
                    reason: archive.reason,
                    failedEntryIds: archive.failedEntryIds,
                  ),
      ],
    );
  }

  List<JournalEntry> viewEntries({
    NotebookFilter filter = NotebookFilter.all,
    DateTime? now,
    int? archivedVolume,
  }) {
    if (archivedVolume != null) {
      final archive = archives.firstWhere((a) => a.volume == archivedVolume);
      return _selectEntries(
        archive._groups,
        sortOrder,
        filter,
        archive.invalidatedAt ?? archive.archivedAt,
        archive.failedEntryIds,
        frozen: true,
      );
    }
    return _selectEntries(
      _groups,
      sortOrder,
      filter,
      now ?? DateTime.now(),
      const {},
    );
  }

  bool expired(DateTime now) => entries.any((entry) => entry.isExpired(now));
  Notebook reconcile(DateTime now) {
    if (!expired(now)) return this;
    final invalidatedAt = entries
        .where((e) => e.isExpired(now))
        .map((e) => e.deadline)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final archive = NotebookArchive(
      volume: volume,
      volumeName: volumeName,
      entries: entries,
      invalidatedAt: invalidatedAt,
      archivedAt: now,
      reason: ArchiveReason.missedDeadline,
      failedEntryIds: entries
          .where((e) => e.isExpired(invalidatedAt))
          .map((e) => e.id)
          .toSet(),
    );
    return Notebook(
      volume: volume + 1,
      entries: [],
      sortOrder: sortOrder,
      archives: [...archives, archive],
    );
  }

  void _validate(String text, DateTime? due, DateTime now) {
    if (text.trim().isEmpty) throw ArgumentError('正文不能为空');
    if (due != null && dateOnly(due).isBefore(dateOnly(now))) {
      throw ArgumentError('日期不能早于今天');
    }
  }

  Notebook add(String text, DateTime due, DateTime now) {
    _validate(text, due, now);
    return Notebook(
      volume: volume,
      volumeName: volumeName,
      sortOrder: sortOrder,
      archives: archives,
      entries: [
        ...entries,
        JournalEntry(
          id: '$volume-${now.microsecondsSinceEpoch}-${entries.length}',
          text: text.trim(),
          due: _civilDate(due),
          createdAt: now.toUtc(),
          createdOn: _civilDate(now),
          status: EntryStatus.pending,
        ),
      ],
    );
  }

  JournalEntry _pending(String id, DateTime now) {
    if (expired(now)) throw StateError('本卷已到期');
    final entry = entries.firstWhere((e) => e.id == id);
    if (entry.status != EntryStatus.pending) throw StateError('此记录不可修改');
    return entry;
  }

  Notebook fulfill(String id, DateTime now) {
    _pending(id, now);
    return Notebook(
      volume: volume,
      volumeName: volumeName,
      sortOrder: sortOrder,
      archives: archives,
      entries: entries
          .map((e) => e.id == id ? e.withStatus(EntryStatus.fulfilled) : e)
          .toList(),
    );
  }

  Notebook revise(String id, String text, DateTime? due, DateTime now) {
    _pending(id, now);
    _validate(text, due, now);
    final supplement = JournalEntry(
      id: '$volume-${now.microsecondsSinceEpoch}-${entries.length}',
      parentId: id,
      text: text.trim(),
      createdAt: now.toUtc(),
      createdOn: _civilDate(now),
      due: due == null ? null : _civilDate(due),
      status: due == null ? EntryStatus.explanation : EntryStatus.pending,
    );
    final updated = <JournalEntry>[];
    for (final entry in entries) {
      updated.add(
        entry.id == id ? entry.withStatus(EntryStatus.revised) : entry,
      );
      if (entry.id == id) updated.add(supplement);
    }
    return Notebook(
      volume: volume,
      volumeName: volumeName,
      entries: updated,
      sortOrder: sortOrder,
      archives: archives,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': storageVersion,
    'archives': archives.map((a) => a.toJson()).toList(),
    'volume': volume,
    'volumeName': volumeName,
    'sortOrder': sortOrder.name,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  factory Notebook.fromJson(Map<String, dynamic> json) => Notebook(
    volume: json['volume'] as int,
    volumeName: json['volumeName'] as String? ?? '',
    archives: (json['archives'] as List? ?? [])
        .map((a) => NotebookArchive.fromJson(a as Map<String, dynamic>))
        .toList(),
    sortOrder: json['sortOrder'] == null
        ? NotebookSortOrder.writing
        : NotebookSortOrder.values.byName(json['sortOrder'] as String),
    entries: (json['entries'] as List)
        .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

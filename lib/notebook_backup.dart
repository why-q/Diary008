import 'dart:convert';

import 'package:flutter/services.dart';

import 'notebook.dart';

const backupChannel = MethodChannel('app.diary008/backup');

Notebook decodeNotebookBackup(String text) {
  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final version = json['schemaVersion'] ?? 1;
    if (version is! int || version < 1 || version > Notebook.storageVersion) {
      throw const FormatException('不支持的备份版本，请使用兼容版本的应用。');
    }
    if (version >= 4 &&
        (json['archives'] is! List ||
            json['volumeName'] is! String ||
            json['sortOrder'] is! String)) {
      throw const FormatException();
    }
    final book = Notebook.fromJson(json);
    if (book.volume < 1) throw const FormatException();
    final volumes = <int>{book.volume};
    _validateEntries(book.entries);
    for (final archive in book.archives) {
      if (archive.volume < 1 ||
          archive.volume >= book.volume ||
          !volumes.add(archive.volume)) {
        throw const FormatException();
      }
      _validateEntries(archive.entries);
      final ids = archive.entries.map((entry) => entry.id).toSet();
      if (!ids.containsAll(archive.failedEntryIds)) {
        throw const FormatException();
      }
    }
    return book;
  } on FormatException catch (error) {
    throw FormatException(
      error.message.isEmpty ? '备份文件无效或不完整，现有记录未改变。' : error.message,
    );
  } catch (_) {
    throw const FormatException('备份文件无效或不完整，现有记录未改变。');
  }
}

void _validateEntries(List<JournalEntry> entries) {
  final seen = <String, JournalEntry>{};
  for (final entry in entries) {
    if (entry.id.isEmpty ||
        seen.containsKey(entry.id) ||
        entry.text.trim().isEmpty ||
        (entry.status != EntryStatus.explanation && entry.due == null) ||
        (entry.status == EntryStatus.explanation && entry.due != null) ||
        (entry.parentId != null &&
            seen[entry.parentId]?.status != EntryStatus.revised)) {
      throw const FormatException();
    }
    seen[entry.id] = entry;
  }
}

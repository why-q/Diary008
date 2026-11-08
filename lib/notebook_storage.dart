import 'dart:convert';
import 'dart:io';

import 'diagnostics.dart';
import 'notebook.dart';

Future<void> writeNotebook(File file, Notebook book) async {
  try {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(book.toJson()), flush: true);
    await temp.rename(file.path);
    await Diagnostics.record('storage.write.success', 'volume=${book.volume}');
  } catch (error, stack) {
    await Diagnostics.record(
      'storage.write.failure',
      'volume=${book.volume};${error.runtimeType}\n$stack',
    );
    Error.throwWithStackTrace(error, stack);
  }
}

Future<Notebook> readNotebook(File file, {bool migrate = true}) async {
  int? volume;
  try {
    if (!await file.exists()) {
      final book = Notebook.empty();
      await Diagnostics.record('storage.read.success', 'volume=${book.volume}');
      return book;
    }
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final book = Notebook.fromJson(json);
    volume = book.volume;
    if (migrate &&
        (json['schemaVersion'] as int? ?? 1) < Notebook.storageVersion) {
      await writeNotebook(file, book);
    }
    await Diagnostics.record('storage.read.success', 'volume=$volume');
    return book;
  } catch (error, stack) {
    await Diagnostics.record(
      'storage.read.failure',
      'volume=$volume;${error.runtimeType}\n$stack',
    );
    Error.throwWithStackTrace(error, stack);
  }
}

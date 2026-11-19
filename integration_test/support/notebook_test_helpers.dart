import 'dart:io';
import 'dart:typed_data';

import 'package:diary008/notebook.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

Future<FileSnapshot> snapshotNotebook() async {
  final directory = await getApplicationDocumentsDirectory();
  return FileSnapshot.capture(File('${directory.path}/notebook.json'));
}

class FileSnapshot {
  const FileSnapshot._(this.file, this._contents);

  final File file;
  final Uint8List? _contents;

  static Future<FileSnapshot> capture(File file) async =>
      FileSnapshot._(file, await file.exists() ? await file.readAsBytes() : null);

  Future<void> restore() async {
    final contents = _contents;
    if (contents != null) {
      await file.writeAsBytes(contents);
    } else if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<void> chooseFilter(WidgetTester tester, String label) async {
  tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
  await tester.pumpAndSettle();
  final menu = find.byType(PopupMenuButton<NotebookFilter>);
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(PopupMenuItem<NotebookFilter>, label));
  await tester.pumpAndSettle();
}

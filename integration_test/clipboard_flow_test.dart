import 'dart:convert';
import 'dart:io';

import 'package:diary008/main.dart';
import 'package:diary008/entry_editor.dart';
import 'package:diary008/journal_page.dart';
import 'package:diary008/journal_theme.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('long-press copy and paste work without modifying sealed text', (
    tester,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/notebook.json');
    final original = await file.exists() ? await file.readAsString() : null;
    final now = DateTime.now();
    final book = Notebook.empty()
        .add('ArchivedClipboard', now.add(const Duration(days: 20)), now)
        .startNewVolume('', now)
        .add('ClipboardRoundTrip', now.add(const Duration(days: 20)), now);
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> copy(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.longPress(find.text(text));
      await tester.pumpAndSettle();
      if (find.text('复制').evaluate().isEmpty &&
          find.text('全选').evaluate().isNotEmpty) {
        await tap(find.text('全选'));
      }
      expect(find.text('复制'), findsOneWidget);
      await tap(find.text('复制'));
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, text);
    }

    Future<void> paste(String text, {bool useButton = false}) async {
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      if (useButton) {
        await tap(find.text('粘贴'));
      } else {
        await tester.longPressAt(
          tester.getTopLeft(field) + const Offset(24, 24),
        );
        await tester.pumpAndSettle();
        final pasteAction = find.descendant(
          of: find.byType(AdaptiveTextSelectionToolbar),
          matching: find.text('粘贴'),
        );
        expect(pasteAction, findsOneWidget);
        await tap(pasteAction);
      }
      expect(tester.widget<TextField>(field).controller!.text, text);
    }

    try {
      await file.writeAsString(jsonEncode(book.toJson()));
      await tester.pumpWidget(const DiaryApp());
      await tester.pumpAndSettle();
      await copy('ClipboardRoundTrip');
      await tap(find.byType(Feather));
      await paste('ClipboardRoundTrip', useButton: true);
      await tap(find.text('搁笔'));
      await tester.tapAt(const Offset(10, 200));
      await tester.pumpAndSettle();
      final paragraph = find.byType(JournalParagraph);
      await tester.ensureVisible(paragraph);
      await tester.pumpAndSettle();
      await tester.drag(paragraph, const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditor), findsOneWidget);
      await copy('ClipboardRoundTrip');
      await paste('ClipboardRoundTrip');
      await tap(find.text('搁笔'));
      await tap(find.text('卷二'));
      await tap(find.textContaining('卷一 · 已封存'));
      await copy('ArchivedClipboard');
      expect(jsonDecode(await file.readAsString()), book.toJson());
      await tester.tapAt(const Offset(10, 200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(JournalParagraph), const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(jsonDecode(await file.readAsString()), book.toJson());
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (original == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(original);
      }
    }
  });
}

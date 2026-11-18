import 'dart:convert';

import 'package:diary008/journal_page.dart';
import 'package:diary008/main.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/notebook_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('large notebook bounds mounted paragraphs and reaches both ends', (
    tester,
  ) async {
    final notebook = await snapshotNotebook();
    final file = notebook.file;
    final now = DateTime.now();
    final book = Notebook(
      volume: 1,
      entries: List.generate(
        500,
        (i) => JournalEntry(
          id: 'lazy-$i',
          text:
              '记录 ${i + 1}：${List.filled(i % 5 == 0 ? 12 : 2, '在期限之前完成约定，记录家人的生活与成长。').join()}',
          createdAt: now.add(Duration(microseconds: i)),
          createdOn: now,
          due: now.add(const Duration(days: 365)),
          status: EntryStatus.fulfilled,
        ),
      ),
    );
    try {
      await file.writeAsString(jsonEncode(book.toJson()));
      await tester.pumpWidget(const DiaryApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<NotebookFilter>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(PopupMenuItem<NotebookFilter>, '全部'),
      );
      await tester.pumpAndSettle();
      // Resource invariant: mounting hundreds of rich, selectable paragraphs
      // for one viewport recreates the large-notebook performance regression.
      expect(find.byType(JournalParagraph).evaluate().length, lessThan(30));
      final scrollable = find.byType(Scrollable);
      await tester.scrollUntilVisible(
        find.text(book.entries.last.text),
        450,
        scrollable: scrollable,
        maxScrolls: 1000,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.text(book.entries.last.text))
            .overlaps(tester.getRect(scrollable)),
        isTrue,
      );
      expect(find.byType(JournalParagraph).evaluate().length, lessThan(30));
      await tester.scrollUntilVisible(
        find.text(book.entries.first.text),
        -450,
        scrollable: scrollable,
        maxScrolls: 1000,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getRect(find.text(book.entries.first.text))
            .overlaps(tester.getRect(scrollable)),
        isTrue,
      );
      expect(jsonDecode(await file.readAsString()), book.toJson());
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await notebook.restore();
    }
  });
}

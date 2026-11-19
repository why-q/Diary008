import 'dart:convert';

import 'package:diary008/main.dart';
import 'package:diary008/journal_page.dart';
import 'package:diary008/journal_theme.dart';
import 'package:flutter/material.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/notebook_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'write, calendar, fulfill, revise, cancel, and reload saved notebook',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      Future<void> settle() async {
        await tester.pumpAndSettle(const Duration(milliseconds: 150));
      }

      Future<Map<String, dynamic>> saved() async =>
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      Future<void> write(String text) async {
        await tester.ensureVisible(find.byType(Feather));
        await settle();
        await tester.tap(find.byType(Feather));
        await settle();
        await tester.enterText(find.byType(TextField), text);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
        await tester.ensureVisible(find.text('三天后'));
        await tester.tap(find.text('三天后'));
        await settle();
        await tester.tap(find.text('落笔'));
        await settle();
      }

      try {
        if (await file.exists()) await file.delete();
        await tester.pumpWidget(const DiaryApp());
        await settle();
        const longText =
            '我会在两个月之内考完雅思。鉴于我的口语能力较差，我将会花一个月的时间练习口语，并且达到一个7.5分的水平。鉴于我的聪明才智和努力程度，这是合理的发展。';
        await write(longText);
        expect(find.text(longText), findsOneWidget);
        final paragraph = find.byType(JournalParagraph).first;
        await tester.drag(paragraph, const Offset(-50, 0));
        await settle();
        expect((await saved())['entries'][0]['status'], 'pending');
        final gesture = await tester.startGesture(tester.getCenter(paragraph));
        await gesture.moveBy(const Offset(-145, 0));
        await tester.pump();
        expect(find.text('松手\n确认履行'), findsOneWidget);
        await gesture.up();
        await settle();
        expect(find.text('是否确认已履行？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle();
        expect((await saved())['entries'][0]['status'], 'pending');
        final confirmGesture = await tester.startGesture(
          tester.getCenter(paragraph),
        );
        await confirmGesture.moveBy(const Offset(-145, 0));
        await tester.pump();
        expect(find.text('松手\n确认履行'), findsOneWidget);
        await confirmGesture.up();
        await settle();
        expect(find.text('是否确认已履行？'), findsOneWidget);
        expect(find.text('确认后将标记为已履行，不能撤销。'), findsOneWidget);
        await tester.tap(find.text('确认履行'));
        await settle();
        expect((await saved())['entries'][0]['status'], 'fulfilled');
        expect(find.text(longText), findsNothing);
        await chooseFilter(tester, '全部');
        await tester.drag(paragraph, const Offset(-160, 0));
        await settle();
        expect((await saved())['entries'][0]['status'], 'fulfilled');
        expect(find.text('是否确认已履行？'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        await tester.drag(paragraph, const Offset(160, 0));
        await settle();
        expect((await saved())['entries'][0]['status'], 'fulfilled');
        expect(find.text('是否确认已履行？'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        await chooseFilter(tester, '履行中');
        expect(find.text(longText), findsNothing);
        await chooseFilter(tester, '全部');
        await write('我会在清晨六点起床，读完今天的书。');
        final last = find.byType(JournalParagraph).last;
        await tester.ensureVisible(last);
        await settle();
        final right = await tester.startGesture(tester.getCenter(last));
        await right.moveBy(const Offset(145, 0));
        await tester.pump();
        expect(find.text('松手\n留下修订'), findsOneWidget);
        await right.up();
        await settle();
        await tester.tap(find.text('搁笔'));
        await settle();
        expect((await saved())['entries'][1]['status'], 'pending');
        await tester.drag(last, const Offset(160, 0));
        await settle();
        await tester.enterText(find.byType(TextField), '昨夜行程有所变动，我重新安排了作息。');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
        await tester.tap(find.text('落笔'));
        await settle();
        final explained = await saved();
        expect(explained['entries'][1]['status'], 'revised');
        expect(explained['entries'][2]['status'], 'explanation');
        expect(explained['entries'][2]['due'], isNull);
        await write('我会在下个月读完这本书。');
        final replacement = find.byType(JournalParagraph).last;
        await tester.ensureVisible(replacement);
        await settle();
        await tester.drag(replacement, const Offset(160, 0));
        await settle();
        await tester.tap(find.text('新的断言'));
        await settle();
        await tester.enterText(find.byType(TextField), '我会每日读书，在一个月后完成这本书。');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle();
        await tester.ensureVisible(find.text('选择日期'));
        await tester.tap(find.text('选择日期'));
        await settle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('落定'));
        await settle();
        await tester.tap(find.text('落笔'));
        await settle();
        final replaced = await saved();
        expect(replaced['entries'][3]['status'], 'revised');
        expect(replaced['entries'][4]['status'], 'pending');
        expect(
          replaced['entries'][4]['parentId'],
          replaced['entries'][3]['id'],
        );
        expect(replaced['entries'][4]['due'], isNotNull);
        // A new widget state must reconstruct the same notebook from disk.
        await tester.pumpWidget(const SizedBox.shrink());
        await settle();
        await tester.pumpWidget(const DiaryApp());
        await settle();
        expect(find.text(longText), findsNothing);
        await chooseFilter(tester, '全部');
        expect(find.text(longText), findsOneWidget);
        final restored = find.text('我会每日读书，在一个月后完成这本书。');
        await tester.scrollUntilVisible(
          restored,
          250,
          scrollable: find.byType(Scrollable),
        );
        await settle();
        expect(restored.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await notebook.restore();
      }
    },
  );
  testWidgets(
    'opening an expired volume clears all entries and persists the new volume',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      try {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final oldBook = Notebook.empty()
            .add('这段预言已经逾期。', yesterday, yesterday)
            .add(
              '这段预言尚未逾期，也将随整卷消失。',
              DateTime.now().add(const Duration(days: 7)),
              yesterday,
            );
        await file.writeAsString(jsonEncode(oldBook.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        expect(find.byType(JournalParagraph), findsNothing);
        final reset =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(reset['entries'], isEmpty);
        expect(reset['volume'], 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        await notebook.restore();
      }
    },
  );
  testWidgets(
    'sort selection reorders intact groups, survives reload, and restores writing order',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      try {
        final now = DateTime.now();
        var book = Notebook.empty()
            .add('原断言', now.add(const Duration(days: 2)), now)
            .add('独立断言', now.add(const Duration(days: 3)), now)
            .add('完成的记录', now.add(const Duration(days: 1)), now);
        book = book
            .fulfill(book.entries.last.id, now)
            .revise(
              book.entries.first.id,
              '新的断言',
              now.add(const Duration(days: 5)),
              now,
            );
        final legacy = book.toJson()..remove('sortOrder');
        await file.writeAsString(jsonEncode(legacy));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        void expectOrder(List<String> texts) {
          final positions = texts
              .map((text) => tester.getTopLeft(find.text(text)).dy)
              .toList();
          for (var i = 1; i < positions.length; i++) {
            expect(
              positions[i],
              greaterThan(positions[i - 1]),
              reason: '${texts[i]} should follow ${texts[i - 1]}',
            );
          }
        }

        Future<void> choose(String label) async {
          final menu = find.byType(PopupMenuButton<NotebookSortOrder>);
          await tester.ensureVisible(menu);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(PopupMenuItem<NotebookSortOrder>, label),
          );
          await tester.pumpAndSettle();
        }

        expect(find.text('完成的记录'), findsNothing);
        await chooseFilter(tester, '全部');
        expectOrder(['原断言', '新的断言', '独立断言', '完成的记录']);
        await choose('有效日期');
        expectOrder(['独立断言', '原断言', '新的断言', '完成的记录']);
        final stored =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(stored['sortOrder'], 'deadline');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        expect(find.text('完成的记录'), findsNothing);
        await chooseFilter(tester, '全部');
        expect(find.text('有效日期'), findsOneWidget);
        expectOrder(['独立断言', '原断言', '新的断言', '完成的记录']);
        // Completing the independent assertion moves its entire group behind pending groups.
        await tester.drag(
          find.widgetWithText(JournalParagraph, '独立断言'),
          const Offset(-160, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认履行'));
        await tester.pumpAndSettle();
        expectOrder(['原断言', '新的断言', '独立断言', '完成的记录']);
        await choose('书写顺序');
        expectOrder(['原断言', '新的断言', '独立断言', '完成的记录']);
        expect(
          (jsonDecode(await file.readAsString())
              as Map<String, dynamic>)['sortOrder'],
          'writing',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        await notebook.restore();
      }
    },
  );
}

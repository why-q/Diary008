import 'dart:convert';
import 'dart:io';

import 'package:diary008/main.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/journal_page.dart';
import 'package:diary008/journal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> showEntry(WidgetTester tester, String text) async {
    final scrollable = find.byType(Scrollable);
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(text),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text(text).hitTestable(), findsOneWidget);
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

  Future<void> chooseVolume(
    WidgetTester tester,
    String header,
    String volume,
  ) async {
    await tester.ensureVisible(find.widgetWithText(TextButton, header));
    await tester.tap(find.widgetWithText(TextButton, header));
    await tester.pumpAndSettle();
    await tester.tap(find.text(volume));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'filters overlap by group without splitting original and replacement',
    (tester) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/notebook.json');
      final original = await file.exists() ? await file.readAsString() : null;
      try {
        final now = DateTime.now();
        var book = Notebook.empty()
            .add('修订原文', now.add(const Duration(days: 20)), now)
            .add('履行的记录', now.add(const Duration(days: 2)), now);
        book = book
            .fulfill(book.entries.last.id, now)
            .revise(
              book.entries.first.id,
              '替代的新断言',
              now.add(const Duration(days: 10)),
              now,
            );
        await file.writeAsString(jsonEncode(book.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await chooseFilter(tester, '履行中');
        expect(find.text('修订原文'), findsOneWidget);
        expect(find.text('替代的新断言'), findsOneWidget);
        expect(find.text('履行的记录'), findsNothing);
        expect(
          tester.getTopLeft(find.text('替代的新断言')).dy,
          greaterThan(tester.getTopLeft(find.text('修订原文')).dy),
        );
        await chooseFilter(tester, '未履行');
        expect(find.text('修订原文'), findsOneWidget);
        expect(find.text('替代的新断言'), findsOneWidget);
        expect(find.text('履行的记录'), findsNothing);
        await chooseFilter(tester, '已履行');
        expect(find.text('履行的记录'), findsOneWidget);
        expect(find.text('替代的新断言'), findsNothing);
        await chooseFilter(tester, '全部');
        await showEntry(tester, '修订原文');
        await showEntry(tester, '替代的新断言');
        await showEntry(tester, '履行的记录');
        expect(jsonDecode(await file.readAsString()), book.toJson());
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        if (original != null) {
          await file.writeAsString(original);
        } else if (await file.exists()) {
          await file.delete();
        }
      }
    },
  );
  testWidgets(
    'expired volume is preserved, selectable, filterable, and read-only',
    (tester) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/notebook.json');
      final original = await file.exists() ? await file.readAsString() : null;
      try {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        var old = Notebook.empty()
            .add('逾期的预言', yesterday, yesterday)
            .add('旧的原文', now.add(const Duration(days: 2)), yesterday)
            .add('已经成立的往事', yesterday, yesterday);
        final root = old.entries[1].id;
        old = old
            .fulfill(old.entries.last.id, yesterday)
            .revise(
              root,
              '后续的新断言',
              now.add(const Duration(days: 3)),
              yesterday,
            );
        await file.writeAsString(jsonEncode(old.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        final saved =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(saved['volume'], 2);
        final archived = saved['archives'][0];
        expect(archived['entries'], old.toJson()['entries']);
        await chooseVolume(tester, '卷二', '卷一 · 已封存');
        await showEntry(tester, '逾期的预言');
        expect(find.text('未如期履行'), findsOneWidget);
        await showEntry(tester, '旧的原文');
        expect(find.text('随卷封存'), findsWidgets);
        await showEntry(tester, '后续的新断言');
        await showEntry(tester, '已经成立的往事');
        expect(find.byType(Feather), findsNothing);
        final before = await file.readAsString();
        final target = find.widgetWithText(JournalParagraph, '逾期的预言');
        await showEntry(tester, '逾期的预言');
        await tester.drag(target, const Offset(-160, 0));
        await tester.pumpAndSettle();
        await tester.drag(target, const Offset(160, 0));
        await tester.pumpAndSettle();
        expect(find.text('搁笔'), findsNothing);
        expect(await file.readAsString(), before);
        await chooseFilter(tester, '履行中');
        await showEntry(tester, '旧的原文');
        await showEntry(tester, '后续的新断言');
        expect(find.text('逾期的预言'), findsNothing);
        await chooseFilter(tester, '未履行');
        await showEntry(tester, '逾期的预言');
        await showEntry(tester, '旧的原文');
        await showEntry(tester, '后续的新断言');
        expect(find.text('已经成立的往事'), findsNothing);
        await chooseFilter(tester, '已履行');
        expect(find.text('已经成立的往事'), findsOneWidget);
        expect(find.text('逾期的预言'), findsNothing);
        await chooseVolume(tester, '卷一', '卷二 · 正在书写');
        expect(find.byType(Feather), findsOneWidget);
        await tester.ensureVisible(find.byType(Feather));
        await tester.tap(find.byType(Feather));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '第二卷从这里继续。');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('三天后'));
        await tester.tap(find.text('三天后'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('落笔'));
        await tester.pumpAndSettle();
        final after =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        expect(after['entries'][0]['text'], '第二卷从这里继续。');
        expect(after['archives'][0], archived);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        expect(find.text('第二卷从这里继续。'), findsOneWidget);
        await chooseVolume(tester, '卷二', '卷一 · 已封存');
        await showEntry(tester, '后续的新断言');
        expect(find.byType(Feather), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        if (original != null) {
          await file.writeAsString(original);
        } else if (await file.exists()) {
          await file.delete();
        }
      }
    },
  );
  testWidgets(
    'manual volumes preserve names and readonly history with pending-first current views',
    (tester) async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/notebook.json');
      final original = await file.exists() ? await file.readAsString() : null;
      Future<Notebook> savedBook() async => Notebook.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      Future<void> openPicker(String title) async {
        final button = find.widgetWithText(TextButton, title);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> nameAction(
        String title,
        String action,
        String name,
        String confirm,
      ) async {
        await openPicker(title);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), name);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, confirm));
        await tester.pumpAndSettle();
      }

      try {
        final now = DateTime.now();
        var book = Notebook.empty()
            .withVolumeName('晨间计划')
            .add('尚待履行的原文', now.add(const Duration(days: 3)), now)
            .add('已履行的旧事', now.add(const Duration(days: 4)), now);
        book = book
            .fulfill(book.entries.last.id, now)
            .revise(
              book.entries.first.id,
              '仍在履行的新断言',
              now.add(const Duration(days: 5)),
              now,
            );
        await file.writeAsString(jsonEncode(book.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        expect(find.text('尚待履行的原文'), findsOneWidget);
        expect(find.text('仍在履行的新断言'), findsOneWidget);
        expect(find.text('已履行的旧事'), findsNothing);
        await chooseFilter(tester, '全部');
        expect(find.text('已履行的旧事'), findsOneWidget);

        await nameAction('卷一 · 晨间计划', '修改当前卷名', '  新的主题  ', '保存');
        expect((await savedBook()).volumeName, '新的主题');
        expect(find.text('已履行的旧事'), findsOneWidget);
        final beforeCancel = await file.readAsString();
        await nameAction('卷一 · 新的主题', '新建一卷', '不会被保存', '取消');
        expect(await file.readAsString(), beforeCancel);
        await nameAction('卷一 · 新的主题', '新建一卷', '阅读与写作', '封存并新建');
        final next = await savedBook();
        expect(next.volume, 2);
        expect(next.volumeName, '阅读与写作');
        expect(next.entries, isEmpty);
        final archived = next.archives.single;
        expect(archived.volumeName, '新的主题');
        expect(archived.reason, ArchiveReason.manualClosure);
        expect(archived.invalidatedAt, isNull);
        expect(
          archived.entries.map((e) => e.toJson()),
          book.entries.map((e) => e.toJson()),
        );

        await chooseVolume(tester, '卷二 · 阅读与写作', '卷一 · 新的主题 · 已封存');
        await showEntry(tester, '已履行的旧事');
        await showEntry(tester, '仍在履行的新断言');
        expect(find.byType(Feather), findsNothing);
        final beforeDrag = await file.readAsString();
        final oldParagraph = find.widgetWithText(JournalParagraph, '仍在履行的新断言');
        await tester.ensureVisible(oldParagraph);
        await tester.drag(oldParagraph, const Offset(160, 0));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(await file.readAsString(), beforeDrag);
        await chooseVolume(tester, '卷一 · 新的主题', '卷二 · 阅读与写作 · 正在书写');
        await nameAction('卷二 · 阅读与写作', '修改当前卷名', '  ', '保存');
        expect((await savedBook()).volumeName, isEmpty);

        var current = (await savedBook())
            .add('当前的待履行断言', now.add(const Duration(days: 2)), now)
            .add('当前已履行的断言', now.add(const Duration(days: 2)), now);
        current = current.fulfill(current.entries.last.id, now);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await file.writeAsString(jsonEncode(current.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        expect(find.text('当前的待履行断言'), findsOneWidget);
        expect(find.text('当前已履行的断言'), findsNothing);
        await chooseVolume(tester, '卷二', '卷一 · 新的主题 · 已封存');
        await showEntry(tester, '已履行的旧事');
        await chooseVolume(tester, '卷一 · 新的主题', '卷二 · 正在书写');
        expect(find.text('当前的待履行断言'), findsOneWidget);
        expect(find.text('当前已履行的断言'), findsNothing);
        expect((await savedBook()).archives.single.toJson(), archived.toJson());
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (original != null) {
          await file.writeAsString(original);
        } else if (await file.exists()) {
          await file.delete();
        }
      }
    },
  );
}

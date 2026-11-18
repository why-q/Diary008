import 'dart:convert';

import 'package:diary008/main.dart';
import 'package:diary008/notebook.dart';
import 'package:diary008/notebook_backup.dart';
import 'package:diary008/backup_encryption.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/notebook_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'restore validates before confirmation and atomically replaces all volumes',
    (tester) async {
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      final now = DateTime.now();
      final old = Notebook.empty().add(
        '导入前记录',
        now.add(const Duration(days: 10)),
        now,
      );
      final archive = Notebook.empty().add(
        '备份原断言',
        now.add(const Duration(days: 10)),
        now,
      );
      final backup = archive
          .revise(archive.entries.single.id, '备份解释', null, now)
          .startNewVolume('恢复卷', now)
          .add('备份当前记录', now.add(const Duration(days: 20)), now)
          .withSortOrder(NotebookSortOrder.deadline);
      String? selection = '{';
      String? exported;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(backupChannel, (call) async {
        if (call.method == 'export') {
          exported = (call.arguments as Map)['contents'] as String;
          return true;
        }
        return selection;
      });
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        if (['导入备份', '导出备份', '密码加密备份', '确认密码'].contains(label)) {
          // Settings stays busy while a backup dialog awaits user input.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        } else {
          await tester.pumpAndSettle();
        }
      }

      Future<void> waitForText(String label) async {
        final elapsed = Stopwatch()..start();
        while (elapsed.elapsed < const Duration(minutes: 2)) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text(label).evaluate().isNotEmpty) {
            await tester.pump(const Duration(milliseconds: 500));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Timed out waiting for $label');
      }

      try {
        await file.writeAsString(jsonEncode(old.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await tap('设置');
        await tap('导入备份');
        expect(find.text('确认替换并导入'), findsNothing);
        expect(jsonDecode(await file.readAsString()), old.toJson());
        selection = null;
        await tap('导入备份');
        expect(jsonDecode(await file.readAsString()), old.toJson());
        await tap('导出备份');
        await tap('密码加密备份');
        await tester.enterText(find.byType(TextField).at(0), ' 密码🔑 ');
        await tester.enterText(find.byType(TextField).at(1), 'different');
        await tap('确认密码');
        expect(find.text('两次输入的密码不一致。'), findsOneWidget);
        await tester.enterText(find.byType(TextField).at(1), ' 密码🔑 ');
        await tester.tap(find.text('确认密码'));
        await waitForText('备份已导出。');
        expect(exported, isNotNull);
        expect(exported, isNot(contains('导入前记录')));
        expect(
          jsonDecode(await decryptBackup(exported!, ' 密码🔑 ')),
          old.toJson(),
        );
        selection = await encryptBackup(jsonEncode(backup.toJson()), ' 密码🔑 ');
        await tap('导入备份');
        await tap('取消');
        expect(jsonDecode(await file.readAsString()), old.toJson());
        await tap('导入备份');
        await tester.enterText(find.byType(TextField), 'wrong');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('解密备份'));
        await waitForText('密码错误或备份文件已损坏，现有记录未改变。');
        expect(find.text('确认替换并导入'), findsNothing);
        expect(jsonDecode(await file.readAsString()), old.toJson());
        await tester.enterText(find.byType(TextField), ' 密码🔑 ');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('解密备份'));
        await tester.pump();
        expect(find.text('密码错误或备份文件已损坏，现有记录未改变。'), findsNothing);
        await waitForText('确认替换并导入');
        await tap('取消');
        expect(jsonDecode(await file.readAsString()), old.toJson());
        await tap('导入备份');
        await tester.enterText(find.byType(TextField), ' 密码🔑 ');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('解密备份'));
        await waitForText('确认替换并导入');
        await tap('确认替换并导入');
        expect(jsonDecode(await file.readAsString()), backup.toJson());
        // Restore the initial state before exercising legacy plaintext imports.
        await tap('关闭');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await file.writeAsString(jsonEncode(old.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await tap('设置');
        selection = jsonEncode(backup.toJson());
        await tap('导入备份');
        await tap('取消');
        expect(jsonDecode(await file.readAsString()), old.toJson());
        await tap('导入备份');
        await tap('确认替换并导入');
        expect(jsonDecode(await file.readAsString()), backup.toJson());
        await tap('关闭');
        expect(find.text('导入前记录'), findsNothing);
        expect(find.text('备份当前记录'), findsOneWidget);
        await tap('卷二 · 恢复卷');
        await tester.tap(find.textContaining('卷一 · 已封存'));
        await tester.pumpAndSettle();
        expect(find.text('备份原断言'), findsOneWidget);
        expect(find.text('备份解释'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        expect(find.text('备份当前记录'), findsOneWidget);
        expect(jsonDecode(await file.readAsString()), backup.toJson());
      } finally {
        messenger.setMockMethodCallHandler(backupChannel, null);
        await tester.pumpWidget(const SizedBox.shrink());
        await notebook.restore();
      }
    },
  );
}

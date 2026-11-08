import 'package:diary008/backup_encryption.dart';
import 'package:diary008/backup_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wrong password can be corrected without replacing data', (
    tester,
  ) async {
    final encrypted = await tester.runAsync(
      () => encryptBackup('private notebook', ' 密码🔑 '),
    );
    String? restored;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              restored = await showBackupPassword(
                context,
                encrypted: encrypted,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    Future<void> submit(String password) async {
      await tester.enterText(find.byType(TextField), password);
      await tester.pump();
      await tester.tap(find.text('解密备份'));
      await tester.pump();
      await tester.runAsync(() async {
        while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
    }

    await submit('wrong');
    expect(restored, isNull);
    expect(find.text('密码错误或备份文件已损坏，现有记录未改变。'), findsOneWidget);
    await submit(' 密码🔑 ');
    expect(restored, 'private notebook');
    expect(find.byType(AlertDialog), findsNothing);
  });
}

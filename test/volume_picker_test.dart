import 'package:diary008/notebook.dart';
import 'package:diary008/volume_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'deleting an archive requires confirmation and can be cancelled',
    (tester) async {
      final now = DateTime(2026, 10, 21, 12);
      final book = Notebook.empty()
          .withVolumeName('晨间计划')
          .add('原断言', DateTime(2026, 11, 1), now)
          .startNewVolume('正在写', now);
      VolumeSelection? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  chosen = await showModalBottomSheet<VolumeSelection>(
                    context: context,
                    builder: (_) => VolumePicker(book: book),
                  );
                },
                child: const Text('翻阅'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('翻阅'));
      await tester.pumpAndSettle();
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('卷二 · 正在写 · 正在书写'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.textContaining('永久删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
      expect(find.text('翻阅卷册'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(chosen?.action, VolumeAction.delete);
      expect(chosen?.volume, 1);
      expect(find.text('翻阅卷册'), findsNothing);
    },
  );
}

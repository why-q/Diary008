import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diary008/journal_page.dart';
import 'package:diary008/notebook.dart';

void main() {
  testWidgets('copying an entry body writes its text to the clipboard', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    final entry = JournalEntry(
      id: 'entry',
      text: 'Copy this body',
      createdAt: DateTime(2026),
      createdOn: DateTime(2026),
      status: EntryStatus.pending,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JournalParagraph(
            entry: entry,
            onFulfill: () {},
            onRevise: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('复制正文'));
    await tester.pumpAndSettle();

    expect(copied, 'Copy this body');
  });
}

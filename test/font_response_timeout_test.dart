import 'dart:async';

import 'package:diary008/font_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stalled font response body times out and does not hang', () async {
    final response = StreamController<List<int>>();
    final cancellation = FontDownloadCancellation();
    final read = readFontResponseBody(
      response.stream,
      expectedLength: 10,
      cancellation: cancellation,
      idleTimeout: const Duration(milliseconds: 25),
    );

    await expectLater(read, throwsA(isA<TimeoutException>()));
    await response.close();
  });

  test('font response body still enforces the byte limit', () async {
    await expectLater(
      readFontResponseBody(
        Stream<List<int>>.fromIterable([
          [1, 2],
        ]),
        expectedLength: 1,
        cancellation: FontDownloadCancellation(),
        idleTimeout: const Duration(seconds: 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

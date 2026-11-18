import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:diary008/main.dart';
import 'package:diary008/notebook.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/notebook_test_helpers.dart';

// Opt in so the normal debug integration suite does not publish misleading FPS.
const _enabled = bool.fromEnvironment('SCROLL_PERF');
const _enforceBudget = bool.fromEnvironment('SCROLL_PERF_ENFORCE');
final _budgetMs = double.parse(
  const String.fromEnvironment(
    'SCROLL_FRAME_BUDGET_MS',
    defaultValue: '16.667',
  ),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final count in [100, 500, 1000]) {
    testWidgets('scroll performance with $count entries', (tester) async {
      expect(
        kProfileMode,
        isTrue,
        reason: 'Run this benchmark with --profile.',
      );
      final notebook = await snapshotNotebook();
      final file = notebook.file;
      try {
        final now = DateTime.now();
        final book = Notebook(
          volume: 1,
          entries: List.generate(
            count,
            (i) => JournalEntry(
              id: 'scroll-perf-$i',
              text:
                  '性能记录 ${i + 1}：${List.filled(i % 5 == 0 ? 12 : 2, '在期限之前完成约定，记录家人的生活与成长。').join()}',
              createdAt: now.add(Duration(microseconds: i)),
              createdOn: now,
              due: now.add(const Duration(days: 365)),
              // Fulfilled entries exercise paragraph rendering without
              // generating unrelated native reminder requests.
              status: EntryStatus.fulfilled,
            ),
          ),
        );
        await file.writeAsString(jsonEncode(book.toJson()));
        await tester.pumpWidget(const DiaryApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuButton<NotebookFilter>));
        await tester.pumpAndSettle();
        final load = Stopwatch()..start();
        await tester.tap(
          find.widgetWithText(PopupMenuItem<NotebookFilter>, '全部'),
        );
        await tester.pumpAndSettle();
        load.stop();
        final scrollable = find.byType(Scrollable);
        expect(scrollable, findsOneWidget);
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(
          position.maxScrollExtent,
          greaterThan(position.viewportDimension),
        );
        Future<void> reachEnd() async {
          // A lazy variable-height list refines maxScrollExtent during layout.
          // Finish navigation outside the timing window, then verify the end.
          for (var attempt = 0; attempt < 20; attempt++) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
            final last = find.text(book.entries.last.text);
            if (last.evaluate().isNotEmpty &&
                tester.getRect(last).overlaps(tester.getRect(scrollable))) {
              return;
            }
          }
          fail('Could not reach the final entry after extent refinement.');
        }

        final samples = <Map<String, Object>>[];
        // Repeat at the top, middle and bottom. Fixed-distance, fixed-speed
        // gestures avoid making large datasets scroll artificially faster.
        for (var round = 0; round < 2; round++) {
          for (final region in ['top', 'middle', 'bottom']) {
            final fraction = switch (region) {
              'top' => 0.0,
              'middle' => 0.5,
              _ => 1.0,
            };
            if (region == 'bottom') {
              await reachEnd();
            } else {
              position.jumpTo(position.maxScrollExtent * fraction);
              await tester.pumpAndSettle();
            }
            // Exclude loading/jump frames, including the engine's batched timings.
            await Future<void>.delayed(const Duration(seconds: 2));
            final timings = <FrameTiming>[];
            void record(List<FrameTiming> frames) => timings.addAll(frames);
            binding.addTimingsCallback(record);
            final before = position.pixels;
            final distance = math.min(240.0, position.viewportDimension * 0.4);
            try {
              for (var gesture = 0; gesture < 12; gesture++) {
                // Finger motion: swipe up to advance, down to return.
                final direction = region == 'bottom' ? 1.0 : -1.0;
                await tester.timedDrag(
                  scrollable,
                  Offset(0, direction * distance),
                  const Duration(milliseconds: 500),
                );
                await tester.pumpAndSettle();
              }
              await Future<void>.delayed(const Duration(seconds: 2));
            } finally {
              binding.removeTimingsCallback(record);
            }
            expect((position.pixels - before).abs(), greaterThan(distance));
            expect(
              timings.length,
              greaterThan(0),
              reason: 'No real rendered frames were captured.',
            );
            final build =
                timings
                    .map((f) => f.buildDuration.inMicroseconds / 1000)
                    .toList()
                  ..sort();
            final raster =
                timings
                    .map((f) => f.rasterDuration.inMicroseconds / 1000)
                    .toList()
                  ..sort();
            final overBudget = timings
                .where(
                  (f) =>
                      f.buildDuration.inMicroseconds / 1000 > _budgetMs ||
                      f.rasterDuration.inMicroseconds / 1000 > _budgetMs,
                )
                .length;
            double p95(List<double> values) =>
                values[(values.length * 0.95).ceil() - 1];
            samples.add({
              'round': round + 1,
              'region': region,
              'frames': timings.length,
              'build_p95_ms': p95(build),
              'build_max_ms': build.last,
              'raster_p95_ms': p95(raster),
              'raster_max_ms': raster.last,
              'over_budget_frames': overBudget,
              'over_budget_percent': 100 * overBudget / timings.length,
            });
          }
        }
        await reachEnd();
        final last = find.text(book.entries.last.text);
        expect(last, findsOneWidget);
        final viewport = tester.getRect(scrollable);
        expect(
          tester.getRect(last).overlaps(viewport),
          isTrue,
          reason: 'The final item must actually be visible at the list end.',
        );
        expect(tester.takeException(), isNull);
        final result = <String, Object>{
          'entries': count,
          'mode': 'profile',
          'frame_budget_ms': _budgetMs,
          'show_all_to_settled_ms': load.elapsedMilliseconds,
          'fixture_status': 'fulfilled',
          'samples': samples,
        };
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['scroll_$count'] = result;
        // One machine-readable line per dataset, retained in flutter test logs.
        // ignore: avoid_print
        print('SCROLL_PERF ${jsonEncode(result)}');
        if (_enforceBudget) {
          for (final sample in samples) {
            expect(
              sample['over_budget_percent'] as double,
              lessThanOrEqualTo(5),
              reason:
                  '$count entries, round ${sample['round']}, ${sample['region']}: >5% of frames exceed ${_budgetMs}ms.',
            );
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await notebook.restore();
      }
    }, skip: !_enabled);
  }
}

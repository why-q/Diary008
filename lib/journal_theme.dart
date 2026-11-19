import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme_preferences.dart';

const journalText = TextStyle(fontSize: 21, height: 1.8);

class JournalTheme extends ThemeExtension<JournalTheme> {
  const JournalTheme({
    required this.paper,
    required this.ink,
    required this.fadedInk,
    required this.accent,
    required this.onAccent,
    required this.grain,
    required this.grainHighlight,
    required this.edge,
    required this.swipePositive,
    required this.swipeNegative,
  });

  final Color paper;
  final Color ink;
  final Color fadedInk;
  final Color accent;
  final Color onAccent;
  final Color grain;
  final Color grainHighlight;
  final Color edge;
  final Color swipePositive;
  final Color swipeNegative;

  static JournalTheme fromPalette(
    JournalPalette palette,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    return switch ((palette, dark)) {
      (JournalPalette.antiquePaper, false) => const JournalTheme(
        paper: Color(0xFFF1E8D6),
        ink: Color(0xFF44382D),
        fadedInk: Color(0xFF6F604E),
        accent: Color(0xFF795A38),
        onAccent: Color(0xFFFFF8ED),
        grain: Color(0xFF8E6A42),
        grainHighlight: Color(0xFFFFFCF4),
        edge: Color(0xFFD4C3A7),
        swipePositive: Color(0xFF64735A),
        swipeNegative: Color(0xFF8B6547),
      ),
      (JournalPalette.antiquePaper, true) => const JournalTheme(
        paper: Color(0xFF28231D),
        ink: Color(0xFFF1E5D2),
        fadedInk: Color(0xFFC1B299),
        accent: Color(0xFFD0A568),
        onAccent: Color(0xFF2A2118),
        grain: Color(0xFFB28D5D),
        grainHighlight: Color(0xFF493F32),
        edge: Color(0xFF5B4B38),
        swipePositive: Color(0xFF70866E),
        swipeNegative: Color(0xFFAE7955),
      ),
      (JournalPalette.plainWhite, false) => const JournalTheme(
        paper: Color(0xFFFCFCFA),
        ink: Color(0xFF1F2426),
        fadedInk: Color(0xFF59656A),
        accent: Color(0xFF2B6870),
        onAccent: Color(0xFFF4FFFF),
        grain: Color(0xFF789196),
        grainHighlight: Color(0xFFFFFFFF),
        edge: Color(0xFFD9E0E0),
        swipePositive: Color(0xFF4D766A),
        swipeNegative: Color(0xFF8A6655),
      ),
      (JournalPalette.plainWhite, true) => const JournalTheme(
        paper: Color(0xFF1B2022),
        ink: Color(0xFFF0F5F3),
        fadedInk: Color(0xFFB9C7C8),
        accent: Color(0xFF78B8BD),
        onAccent: Color(0xFF132123),
        grain: Color(0xFF7D9A9D),
        grainHighlight: Color(0xFF2D383A),
        edge: Color(0xFF465457),
        swipePositive: Color(0xFF80A99A),
        swipeNegative: Color(0xFFBD8870),
      ),
      (JournalPalette.cyanPaper, false) => const JournalTheme(
        paper: Color(0xFFE5F1F0),
        ink: Color(0xFF17363A),
        fadedInk: Color(0xFF4C6E70),
        accent: Color(0xFF267579),
        onAccent: Color(0xFFF0FFFF),
        grain: Color(0xFF4C898B),
        grainHighlight: Color(0xFFF7FFFF),
        edge: Color(0xFFBCD6D5),
        swipePositive: Color(0xFF4B796C),
        swipeNegative: Color(0xFF8A6255),
      ),
      (JournalPalette.cyanPaper, true) => const JournalTheme(
        paper: Color(0xFF17292A),
        ink: Color(0xFFE5F3F1),
        fadedInk: Color(0xFFB2CBCA),
        accent: Color(0xFF78C1BE),
        onAccent: Color(0xFF102526),
        grain: Color(0xFF6CA5A2),
        grainHighlight: Color(0xFF2D4848),
        edge: Color(0xFF3F6261),
        swipePositive: Color(0xFF78A895),
        swipeNegative: Color(0xFFBD806D),
      ),
    };
  }

  @override
  JournalTheme copyWith({
    Color? paper,
    Color? ink,
    Color? fadedInk,
    Color? accent,
    Color? onAccent,
    Color? grain,
    Color? grainHighlight,
    Color? edge,
    Color? swipePositive,
    Color? swipeNegative,
  }) => JournalTheme(
    paper: paper ?? this.paper,
    ink: ink ?? this.ink,
    fadedInk: fadedInk ?? this.fadedInk,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    grain: grain ?? this.grain,
    grainHighlight: grainHighlight ?? this.grainHighlight,
    edge: edge ?? this.edge,
    swipePositive: swipePositive ?? this.swipePositive,
    swipeNegative: swipeNegative ?? this.swipeNegative,
  );

  @override
  JournalTheme lerp(covariant JournalTheme? other, double t) {
    if (other == null) return this;
    return JournalTheme(
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      fadedInk: Color.lerp(fadedInk, other.fadedInk, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      grain: Color.lerp(grain, other.grain, t)!,
      grainHighlight: Color.lerp(grainHighlight, other.grainHighlight, t)!,
      edge: Color.lerp(edge, other.edge, t)!,
      swipePositive: Color.lerp(swipePositive, other.swipePositive, t)!,
      swipeNegative: Color.lerp(swipeNegative, other.swipeNegative, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JournalTheme &&
      other.paper == paper &&
      other.ink == ink &&
      other.fadedInk == fadedInk &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.grain == grain &&
      other.grainHighlight == grainHighlight &&
      other.edge == edge &&
      other.swipePositive == swipePositive &&
      other.swipeNegative == swipeNegative;

  @override
  int get hashCode => Object.hash(
    paper,
    ink,
    fadedInk,
    accent,
    onAccent,
    grain,
    grainHighlight,
    edge,
    swipePositive,
    swipeNegative,
  );
}

JournalTheme journalThemeOf(BuildContext context) =>
    Theme.of(context).extension<JournalTheme>() ??
    JournalTheme.fromPalette(JournalPalette.antiquePaper, Brightness.light);

ThemeData journalThemeData(JournalPalette palette, Brightness brightness) {
  final colors = JournalTheme.fromPalette(palette, brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
        surface: colors.paper,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        surface: colors.paper,
        onSurface: colors.ink,
        onSurfaceVariant: colors.fadedInk,
        outline: colors.edge,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.paper,
    canvasColor: colors.paper,
    colorScheme: scheme,
    extensions: [colors],
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        textStyle: const TextStyle(fontSize: 19),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: colors.paper),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.paper, fontSize: 17),
    ),
  );
}

String _volumeNumber(int number, {bool leading = true}) {
  const digits = '零一二三四五六七八九';
  for (final (base, unit) in const [
    (100000000, '亿'),
    (10000, '万'),
    (1000, '千'),
    (100, '百'),
    (10, '十'),
  ]) {
    if (number < base) continue;
    final head = number ~/ base;
    final tail = number % base;
    final prefix =
        '${leading && base == 10 && head == 1 ? '' : _volumeNumber(head)}$unit';
    if (tail == 0) return prefix;
    return '$prefix${tail < base ~/ 10 ? '零' : ''}${_volumeNumber(tail, leading: false)}';
  }
  return digits[number];
}

String journalVolumeTitle(int volume, String name) {
  final suffix = name.trim();
  final prefix = '卷${_volumeNumber(volume)}';
  return suffix.isEmpty ? prefix : '$prefix · $suffix';
}

String journalDate(DateTime date) {
  const digits = '〇一二三四五六七八九';
  String number(int n) => n < 10
      ? digits[n]
      : n < 20
      ? '十${n == 10 ? '' : digits[n % 10]}'
      : '${digits[n ~/ 10]}十${n % 10 == 0 ? '' : digits[n % 10]}';
  final year = date.year
      .toString()
      .split('')
      .map((d) => digits[int.parse(d)])
      .join();
  return '$year年${number(date.month)}月${number(date.day)}日';
}

class PaperSurface extends StatelessWidget {
  const PaperSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = journalThemeOf(context);
    return CustomPaint(painter: _PaperPainter(colors), child: child);
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.colors);
  final JournalTheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = colors.paper);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            colors.grain.withValues(alpha: .12),
            colors.grainHighlight.withValues(alpha: 0),
            colors.grain.withValues(alpha: .06),
          ],
          stops: const [0, .16, 1],
        ).createShader(rect),
    );
    final random = math.Random(8);
    final speck = Paint()..color = colors.grain.withValues(alpha: .12);
    for (var i = 0; i < (size.width * size.height / 200).round(); i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * .6,
        speck,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) => oldDelegate.colors != colors;
}

class Feather extends StatelessWidget {
  const Feather({super.key, this.size = 38});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = journalThemeOf(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _FeatherPainter(colors.ink),
    );
  }
}

class _FeatherPainter extends CustomPainter {
  const _FeatherPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(7, 35)
        ..cubicTo(11, 26, 18, 18, 29, 8),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(12, 27)
        ..cubicTo(5, 16, 19, 3, 34, 4)
        ..cubicTo(34, 16, 26, 30, 12, 27),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15, 23)
        ..lineTo(14, 16)
        ..moveTo(19, 19)
        ..lineTo(19, 11)
        ..moveTo(23, 15)
        ..lineTo(29, 15)
        ..moveTo(16, 24)
        ..lineTo(23, 24),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FeatherPainter oldDelegate) => oldDelegate.color != color;
}

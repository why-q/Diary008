import 'dart:math' as math;

import 'package:flutter/material.dart';

const paper = Color(0xFFF1E8D6);
const ink = Color(0xFF44382D);
const fadedInk = Color(0xFF897B67);
const journalText = TextStyle(
  fontFamily: 'JournalKai',
  fontFamilyFallback: ['JournalSerif'],
  color: ink,
  fontSize: 21,
  height: 1.8,
);

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
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PaperPainter(), child: child);
}

class _PaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = paper);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x199C7542), Color(0x00FFFFFF), Color(0x0D9C7542)],
          stops: [0, .16, 1],
        ).createShader(rect),
    );
    final random = math.Random(8);
    final speck = Paint()..color = const Color(0x14785834);
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
  bool shouldRepaint(_PaperPainter oldDelegate) => false;
}

class Feather extends StatelessWidget {
  const Feather({super.key, this.size = 38});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _FeatherPainter());
}

class _FeatherPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final paint = Paint()
      ..color = ink
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
  bool shouldRepaint(_FeatherPainter oldDelegate) => false;
}

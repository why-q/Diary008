import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'journal_theme.dart';
import 'notebook.dart';

class JournalParagraph extends StatefulWidget {
  const JournalParagraph({
    super.key,
    required this.entry,
    required this.onFulfill,
    required this.onRevise,
    this.readOnly = false,
    this.annotation,
  });
  final JournalEntry entry;
  final VoidCallback onFulfill;
  final VoidCallback onRevise;
  final bool readOnly;
  final String? annotation;
  @override
  State<JournalParagraph> createState() => _JournalParagraphState();
}

class _JournalParagraphState extends State<JournalParagraph> {
  double _offset = 0;
  bool _dragging = false;
  static const threshold = 108.0;
  bool get _pending =>
      !widget.readOnly && widget.entry.status == EntryStatus.pending;
  bool get _swipeable => _pending;
  void _release() {
    final offset = _offset;
    setState(() {
      _offset = 0;
      _dragging = false;
    });
    if (offset <= -threshold && _pending) widget.onFulfill();
    if (offset >= threshold && _pending) widget.onRevise();
  }

  Future<void> _copyBody() async {
    await Clipboard.setData(ClipboardData(text: widget.entry.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('正文已复制。')));
  }

  Future<void> _showActions() async {
    final copyRequested = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: paper,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text('条目操作', style: TextStyle(fontSize: 25, color: ink)),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy, color: fadedInk),
              title: const Text('复制正文'),
              onTap: () => Navigator.pop(context, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
    if (copyRequested != true || !mounted) return;
    await _copyBody();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final reached = _offset.abs() >= threshold;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(entry.parentId == null ? 0 : 14, 14, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.text,
            style: journalText.copyWith(
              color: entry.status == EntryStatus.revised ? fadedInk : ink,
              decoration: entry.status == EntryStatus.revised
                  ? TextDecoration.lineThrough
                  : null,
              decorationThickness: 1.3,
            ),
          ),
          const SizedBox(height: 9),
          SelectionContainer.disabled(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      journalDate(entry.due ?? entry.createdOn),
                      style: const TextStyle(fontSize: 14, color: fadedInk),
                    ),
                    IconButton(
                      tooltip: '复制正文',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copyBody,
                      icon: const Icon(Icons.content_copy, size: 16),
                    ),
                  ],
                ),
                if (widget.annotation != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.annotation!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, color: fadedInk),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    // Keep selection outside the swipe detector so quick drags retain priority.
    return SelectionArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Semantics(
          label: _pending ? '可向左滑动确认履行，向右滑动修订' : null,
          customSemanticsActions: _pending
              ? {
                  const CustomSemanticsAction(label: '确认履行'): widget.onFulfill,
                  const CustomSemanticsAction(label: '修订'): widget.onRevise,
                }
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTap: _showActions,
            onHorizontalDragStart: _swipeable
                ? (_) => setState(() => _dragging = true)
                : null,
            onHorizontalDragUpdate: _swipeable
                ? (details) => setState(() {
                    _offset = (_offset + details.delta.dx).clamp(
                      -146.0,
                      _pending ? 146.0 : 0.0,
                    );
                  })
                : null,
            onHorizontalDragEnd: _swipeable ? (_) => _release() : null,
            onHorizontalDragCancel: _swipeable
                ? () => setState(() {
                    _offset = 0;
                    _dragging = false;
                  })
                : null,
            child: ClipRect(
              child: Stack(
                children: [
                  if (_offset != 0)
                    Positioned.fill(
                      child: ColoredBox(
                        color: _offset < 0
                            ? const Color(0xFF8B7356)
                            : const Color(0xFF776D5A),
                        child: Align(
                          alignment: _offset < 0
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: SizedBox(
                            width: 108,
                            child: Text(
                              _offset < 0
                                  ? '${reached ? '松手' : '继续左滑'}\n确认履行'
                                  : '${reached ? '松手' : '继续右滑'}\n留下修订',
                              textAlign: TextAlign.center,
                              style: journalText.copyWith(
                                fontSize: 17,
                                color: paper,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  AnimatedContainer(
                    duration: Duration(milliseconds: _dragging ? 0 : 230),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(_offset, 0, 0),
                    child: _offset == 0
                        ? content
                        : ColoredBox(color: paper, child: content),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

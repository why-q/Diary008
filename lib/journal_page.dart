import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'app_localizations.dart';
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
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).copiedBody)),
      );
  }

  Future<void> _showActions() async {
    final l10n = AppLocalizations.of(context);
    final copyRequested = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: paper,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                l10n.entryActions,
                style: const TextStyle(fontSize: 25, color: ink),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy, color: fadedInk),
              title: Text(l10n.copyBody),
              onTap: () => Navigator.pop(context, true),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
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
                      AppLocalizations.of(context)
                          .dateFormat((entry.due ?? entry.createdOn).toLocal()),
                      style: const TextStyle(fontSize: 14, color: fadedInk),
                    ),
                    IconButton(
                      tooltip: AppLocalizations.of(context).copyBody,
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
          label: _pending ? AppLocalizations.of(context).canSwipe : null,
          customSemanticsActions: _pending
              ? {
                  CustomSemanticsAction(
                    label: AppLocalizations.of(context).confirmAction,
                  ): widget.onFulfill,
                  CustomSemanticsAction(
                    label: AppLocalizations.of(context).reviseAction,
                  ): widget.onRevise,
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
                                  ? AppLocalizations.of(context)
                                        .swipeAction(true, reached)
                                  : AppLocalizations.of(context)
                                        .swipeAction(false, reached),
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

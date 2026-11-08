import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'journal_theme.dart';
import 'notebook.dart';

class EntryDraft {
  const EntryDraft(this.text, this.due);
  final String text;
  final DateTime? due;
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, this.original});
  final JournalEntry? original;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _text = TextEditingController();
  final _textFocus = FocusNode();
  DateTime? _date;
  bool _explanation = true;
  String? _error;
  bool get _needsDate => widget.original == null || !_explanation;
  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('剪贴板中没有可粘贴的文字。')));
      return;
    }
    final value = _text.value;
    final selection = value.selection;
    final validSelection =
        selection.isValid && selection.end <= value.text.length;
    final start = validSelection ? selection.start : value.text.length;
    final end = validSelection ? selection.end : value.text.length;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    setState(() => _error = null);
    _textFocus.requestFocus();
  }

  Future<void> _calendar() async {
    final today = dateOnly(DateTime.now());
    final result = await showDatePicker(
      context: context,
      initialDate: _date != null && !_date!.isBefore(today) ? _date : today,
      firstDate: today,
      lastDate: DateTime(today.year + 100, 12, 31),
      helpText: '为预言落下日期',
      cancelText: '返回',
      confirmText: '落定',
    );
    if (result != null) {
      setState(() {
        _date = result;
        _error = null;
      });
    }
  }

  void _save() {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = '请先写下文字。');
      return;
    }
    if (_needsDate &&
        (_date == null || _date!.isBefore(dateOnly(DateTime.now())))) {
      setState(() => _error = '请为这段预言选择日期。');
      return;
    }
    Navigator.pop(
      context,
      EntryDraft(_text.text.trim(), _needsDate ? _date : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final choices = <String, DateTime>{
      '三天后': dateOnly(now.add(const Duration(days: 3))),
      '一周后': dateOnly(now.add(const Duration(days: 7))),
      '一个月后': calendarOffset(now, months: 1),
      '一年后': calendarOffset(now, years: 1),
      '三年后': calendarOffset(now, years: 3),
    };
    return Scaffold(
      body: PaperSurface(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('搁笔'),
                    ),
                    Text(
                      widget.original == null ? '续写' : '修订',
                      style: journalText.copyWith(fontSize: 24),
                    ),
                    TextButton(onPressed: _save, child: const Text('落笔')),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.original != null) ...[
                        SelectableText(
                          widget.original!.text,
                          style: journalText.copyWith(
                            color: fadedInk,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 18,
                          children: [_mode('留下解释', true), _mode('新的断言', false)],
                        ),
                        const SizedBox(height: 18),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: const Text('粘贴'),
                        ),
                      ),
                      TextField(
                        controller: _text,
                        focusNode: _textFocus,
                        minLines: 7,
                        maxLines: null,
                        style: journalText,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: _needsDate ? '我会……' : '事情未曾如此发展，是因为……',
                          hintStyle: journalText.copyWith(
                            color: fadedInk.withValues(alpha: .65),
                          ),
                        ),
                      ),
                      if (_needsDate) ...[
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _calendar,
                            child: Text(
                              _date == null ? '选择日期' : journalDate(_date!),
                              style: journalText.copyWith(fontSize: 17),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          children: choices.entries
                              .map(
                                (choice) => TextButton(
                                  onPressed: () => setState(() {
                                    _date = choice.value;
                                    _error = null;
                                  }),
                                  child: Text(
                                    choice.key,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '所选日期的最后一刻，为这段预言的期限。',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: fadedInk, fontSize: 13),
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFF8B493F),
                              fontSize: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mode(String label, bool value) => TextButton(
    onPressed: () => setState(() => _explanation = value),
    style: TextButton.styleFrom(
      foregroundColor: _explanation == value ? ink : fadedInk,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 19,
        decoration: _explanation == value ? TextDecoration.underline : null,
      ),
    ),
  );
}

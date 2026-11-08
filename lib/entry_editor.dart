import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_localizations.dart';
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
  AppLocalizations get _l10n => AppLocalizations.of(context);
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
        ..showSnackBar(SnackBar(content: Text(_l10n.clipboardEmpty)));
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
      helpText: _l10n.dueDateHelp,
      cancelText: _l10n.cancel,
      confirmText: _l10n.setDate,
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
      setState(() => _error = _l10n.writeFirst);
      return;
    }
    if (_needsDate &&
        (_date == null || _date!.isBefore(dateOnly(DateTime.now())))) {
      setState(() => _error = _l10n.chooseDueDate);
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
      _l10n.inThreeDays: dateOnly(now.add(const Duration(days: 3))),
      _l10n.inOneWeek: dateOnly(now.add(const Duration(days: 7))),
      _l10n.inOneMonth: calendarOffset(now, months: 1),
      _l10n.inOneYear: calendarOffset(now, years: 1),
      _l10n.inThreeYears: calendarOffset(now, years: 3),
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
                      child: Text(_l10n.closeEditor),
                    ),
                    Text(
                      widget.original == null
                          ? _l10n.continueWriting
                          : _l10n.revise,
                      style: journalText.copyWith(fontSize: 24),
                    ),
                    TextButton(onPressed: _save, child: Text(_l10n.write)),
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
                          children: [
                            _mode(_l10n.leaveExplanation, true),
                            _mode(_l10n.newAssertionMode, false),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: Text(_l10n.paste),
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
                          hintText: _needsDate
                              ? _l10n.assertionHint
                              : _l10n.revisionHint,
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
                              _date == null
                                  ? _l10n.chooseDate
                                  : _l10n.dateFormat(_date!),
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
                        Text(
                          _l10n.dateDeadlineHint,
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

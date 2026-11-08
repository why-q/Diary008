import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'journal_theme.dart';
import 'reminder_preferences.dart';
import 'reminder_service.dart';

class ReminderSettings extends StatefulWidget {
  const ReminderSettings({
    super.key,
    required this.preferences,
    required this.result,
    required this.hasError,
    required this.onEnable,
    required this.onCheck,
    required this.onSystemSettings,
    required this.onSave,
  });

  final ReminderSyncResult? result;
  final ReminderPreferences preferences;
  final bool hasError;
  final VoidCallback onEnable;
  final VoidCallback onCheck;
  final VoidCallback onSystemSettings;
  final Future<bool> Function(ReminderPreferences) onSave;

  @override
  State<ReminderSettings> createState() => _ReminderSettingsState();
}

class _ReminderSettingsState extends State<ReminderSettings> {
  late ReminderMode _mode;
  late int _hour;
  late int _minute;
  bool _saving = false;
  bool _saveFailed = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    final preferences = widget.preferences;
    _mode = preferences.mode;
    _hour = preferences.hour;
    _minute = preferences.minute;
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      helpText: _l10n.chooseDailyTime,
      cancelText: _l10n.cancel,
      confirmText: _l10n.confirm,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _hour = selected.hour;
      _minute = selected.minute;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    var saved = false;
    try {
      saved = await widget.onSave(
        ReminderPreferences(mode: _mode, hour: _hour, minute: _minute),
      );
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent == false ||
        route?.animation?.status == AnimationStatus.reverse ||
        route?.animation?.status == AnimationStatus.dismissed) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _saveFailed = true;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        child: RadioGroup<ReminderMode>(
          groupValue: _mode,
          onChanged: (value) {
            if (!_saving && value != null) setState(() => _mode = value);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _l10n.reminderSettings,
                textAlign: TextAlign.center,
                style: journalText.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 12),
              Text(
                widget.hasError
                    ? _l10n.reminderScheduleFailure
                    : widget.result == null
                    ? _l10n.checkingNotificationStatus
                    : widget.result!.enabled
                    ? _l10n.scheduledReminders(widget.result!.scheduledCount)
                    : _l10n.notificationsOff,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: fadedInk,
                ),
              ),
              const SizedBox(height: 12),
              RadioListTile<ReminderMode>(
                key: const Key('reminder-mode-automatic'),
                value: ReminderMode.automatic,
                enabled: !_saving,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _l10n.automatic,
                  style: journalText.copyWith(fontSize: 19),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: 52, bottom: 8),
                child: Text(
                  _l10n.automaticDescription,
                  style: TextStyle(fontSize: 14, height: 1.65, color: fadedInk),
                ),
              ),
              RadioListTile<ReminderMode>(
                key: const Key('reminder-mode-daily'),
                value: ReminderMode.daily,
                enabled: !_saving,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _l10n.daily,
                  style: journalText.copyWith(fontSize: 19),
                ),
              ),
              if (_mode == ReminderMode.daily) ...[
                Padding(
                  padding: EdgeInsets.only(left: 52, bottom: 8),
                  child: Text(
                    _l10n.dailyDescription,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.65,
                      color: fadedInk,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('reminder-time'),
                    onPressed: _saving ? null : _chooseTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(_l10n.dailyTime(_formatClock(_hour, _minute))),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _l10n.timezoneNotice,
                style: TextStyle(fontSize: 14, height: 1.65, color: fadedInk),
              ),
              if (_saveFailed) ...[
                const SizedBox(height: 8),
                Text(
                  _l10n.settingsRetry,
                  style: TextStyle(fontSize: 15, height: 1.6, color: ink),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('reminder-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('reminder-save'),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_l10n.save),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.result?.enabled != true)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onEnable();
                  },
                  child: Text(_l10n.enableNotifications),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCheck();
                },
                child: Text(_l10n.recheckReminders),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onSystemSettings();
                },
                child: Text(_l10n.systemNotificationSettings),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _formatClock(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

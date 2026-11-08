import 'package:flutter/material.dart';

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
      helpText: '选择每日提醒时间',
      cancelText: '取消',
      confirmText: '确定',
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
                '断言提醒',
                textAlign: TextAlign.center,
                style: journalText.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 12),
              Text(
                widget.hasError
                    ? '提醒排程未完成，请重新检查；笔记内容已保存。'
                    : widget.result == null
                    ? '正在检查通知状态。'
                    : widget.result!.enabled
                    ? '通知已开启，已安排 ${widget.result!.scheduledCount} 次未来提醒。'
                    : '系统通知尚未开启，或提醒通道已被关闭。',
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
                title: Text('自动提醒', style: journalText.copyWith(fontSize: 19)),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 52, bottom: 8),
                child: Text(
                  '仅提醒当前卷，按当地上午九点安排；同一天多个条目合并为一次。七天内只在截止当天提醒；更长期限采用第1、3、7、14、30、60、90、180、270天，并保留截止当天；超过30天再加最后一周。卷内最早期限之后不再安排。',
                  style: TextStyle(fontSize: 14, height: 1.65, color: fadedInk),
                ),
              ),
              RadioListTile<ReminderMode>(
                key: const Key('reminder-mode-daily'),
                value: ReminderMode.daily,
                enabled: !_saving,
                contentPadding: EdgeInsets.zero,
                title: Text('每日提醒', style: journalText.copyWith(fontSize: 19)),
              ),
              if (_mode == ReminderMode.daily) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 52, bottom: 8),
                  child: Text(
                    '每天按设备当地时间提醒一次，即使当前没有待办记录也会继续提醒。',
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
                    label: Text('每日提醒时间 · ${_formatClock(_hour, _minute)}'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '提醒跟随设备当地时间，不补发已过节点。系统省电策略或通知权限可能影响送达，无法保证准点。',
                style: TextStyle(fontSize: 14, height: 1.65, color: fadedInk),
              ),
              if (_saveFailed) ...[
                const SizedBox(height: 8),
                const Text(
                  '设置或提醒排程未完成，请重新检查设置后重试。',
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
                      child: const Text('取消'),
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
                          : const Text('保存设置'),
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
                  child: const Text('启用通知提醒'),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCheck();
                },
                child: const Text('重新检查提醒'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onSystemSettings();
                },
                child: const Text('系统通知设置'),
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

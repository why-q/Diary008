import 'package:flutter/material.dart';

import 'diagnostics.dart';
import 'journal_theme.dart';

void _noTheme() {}

class DataSettings extends StatefulWidget {
  const DataSettings({
    super.key,
    this.onTheme = _noTheme,
    required this.onDestroy,
    required this.onExport,
    required this.onImport,
  });
  final VoidCallback onTheme;
  final Future<String> Function() onDestroy;
  final Future<String> Function() onExport;
  final Future<String> Function() onImport;

  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  bool _busy = false;
  String? _message;

  Future<bool> _confirm(
    String title,
    String explanation,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: journalThemeOf(context).paper,
          title: Text(title),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showPrivacyNotice() async {
    final notice = await DefaultAssetBundle.of(context)
        .loadString('assets/privacy_notice.txt');
    if (!mounted) return;
    final separator = notice.indexOf('\n\n');
    final title = separator < 0 ? '隐私说明' : notice.substring(0, separator);
    final body = separator < 0 ? notice : notice.substring(separator + 2);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: journalThemeOf(context).paper,
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error, stack) {
      await Diagnostics.record(
        'settings.operation.failed',
        '${error.runtimeType}\n$stack',
      );
      if (mounted) setState(() => _message = '操作未完成，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '设置',
              style: TextStyle(
                fontSize: 25,
                color: journalThemeOf(context).ink,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : widget.onTheme,
              child: const Text('外观设置'),
            ),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              '数据与诊断',
              style: TextStyle(
                fontSize: 20,
                color: journalThemeOf(context).ink,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _busy ? null : _showPrivacyNotice,
              child: const Text('隐私说明'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => showLicensePage(
                      context: context,
                      applicationName: '家族笔记',
                    ),
              child: const Text('开源许可'),
            ),
            const SizedBox(height: 16),
            const Text(
              '备份包含当前卷、全部历史卷、卷名、正文、解释、修订记录和排序偏好，不包含诊断日志。导出时可选择明文或密码加密；忘记密码无法恢复加密备份。选择云盘时文件会交由该提供方处理。',
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(widget.onExport),
              child: const Text('导出备份'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(widget.onImport),
              child: const Text('导入备份'),
            ),
            const Text('导入将完整替换现有所有卷和记录，不进行合并。建议先导出当前数据；选择文件后仍需确认才能覆盖。'),
            const Divider(),
            const SizedBox(height: 16),
            const Text('日志仅保存在本机，不记录正文或卷名，不自动上传。容量达到上限后会覆盖最早的日志。'),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () async =>
                          await Diagnostics.export() ? '日志已导出。' : '已取消导出。',
                    ),
              child: const Text('导出日志'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!await _confirm(
                            '清空日志？',
                            '删除本机诊断日志，不影响笔记，也不会删除已导出的文件。',
                            '确认清空日志',
                          ) ||
                          !mounted) {
                        return;
                      }
                      await _run(() async {
                        await Diagnostics.clear();
                        return '日志已清空；之后的操作会继续记录。';
                      });
                    },
              child: const Text('清空日志'),
            ),
            const Divider(),
            const Text(
              '销毁后，当前卷、全部历史卷、断言、解释和修订记录均不可恢复。诊断日志保留，已导出的文件不受影响。这不是闪存安全擦除。',
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!await _confirm(
                            '销毁所有记录？',
                            '所有卷册和记录将永久删除，并清除已有通知和条目自动提醒。每日写作提醒设置保留，空白卷也会继续提醒。此操作不可撤销，诊断日志会保留。',
                            '确认销毁记录',
                          ) ||
                          !mounted) {
                        return;
                      }
                      await _run(widget.onDestroy);
                    },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('销毁所有记录'),
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _message!,
                  semanticsLabel: _message,
                  style: TextStyle(color: journalThemeOf(context).ink),
                ),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    ),
  );
}

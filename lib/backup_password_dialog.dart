import 'package:flutter/material.dart';

import 'backup_encryption.dart';
import 'journal_theme.dart';

/// Returns a new password for export, or decrypted contents for import.
Future<String?> showBackupPassword(BuildContext context, {String? encrypted}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BackupPasswordDialog(encrypted: encrypted),
    );

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({this.encrypted});
  final String? encrypted;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _password.text;
    final encrypted = widget.encrypted;
    if (password.isEmpty ||
        (encrypted == null && password != _confirmation.text)) {
      setState(() => _error = password.isEmpty ? '密码不能为空。' : '两次输入的密码不一致。');
      return;
    }
    if (encrypted == null) {
      Navigator.pop(context, password);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plaintext = await decryptBackup(encrypted, password);
      if (mounted) Navigator.pop(context, plaintext);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '解密未完成，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exporting = widget.encrypted == null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: journalThemeOf(context).paper,
        title: Text(exporting ? '设置备份密码' : '输入备份密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exporting
                    ? '密码仅用于本次备份，不会保存。忘记密码将无法恢复备份；应用内笔记仍按原方式存储。'
                    : '解密成功后仍需确认替换记录。密码不会保存。',
              ),
              TextField(
                controller: _password,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: '密码'),
                onSubmitted: exporting ? null : (_) => _submit(),
              ),
              if (exporting)
                TextField(
                  controller: _confirmation,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: '再次输入密码'),
                  onSubmitted: (_) => _submit(),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(exporting ? '确认密码' : '解密备份'),
          ),
        ],
      ),
    );
  }
}

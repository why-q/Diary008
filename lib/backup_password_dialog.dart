import 'package:flutter/material.dart';

import 'app_localizations.dart';
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
      final l10n = AppLocalizations.of(context);
      setState(
        () => _error = password.isEmpty
            ? l10n.passwordEmpty
            : l10n.passwordsDiffer,
      );
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
      if (mounted) {
        setState(() => _error = _l10n.localizeBackupError(error.message));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).decryptionFailure);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  Widget build(BuildContext context) {
    final exporting = widget.encrypted == null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: journalThemeOf(context).paper,
        title: Text(
          exporting ? _l10n.setBackupPassword : _l10n.enterBackupPassword,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exporting
                    ? _l10n.exportPasswordDescription
                    : _l10n.importPasswordDescription,
              ),
              TextField(
                controller: _password,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: _l10n.password),
                onSubmitted: exporting ? null : (_) => _submit(),
              ),
              if (exporting)
                TextField(
                  controller: _confirmation,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: _l10n.confirmPassword),
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
            child: Text(_l10n.cancel),
          ),
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              exporting ? _l10n.confirmPasswordAction : _l10n.decryptBackup,
            ),
          ),
        ],
      ),
    );
  }
}

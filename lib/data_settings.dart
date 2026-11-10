import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_localizations.dart';
import 'diagnostics.dart';
import 'journal_theme.dart';

class DataSettings extends StatefulWidget {
  const DataSettings({
    super.key,
    required this.onDestroy,
    required this.onExport,
    required this.onImport,
    required this.language,
    required this.onLanguageChanged,
  });
  final Future<String> Function() onDestroy;
  final Future<String> Function() onExport;
  final Future<String> Function() onImport;
  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;

  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  bool _busy = false;
  String? _message;
  late AppLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = widget.language;
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  Future<void> _changeLanguage(AppLanguage? language) async {
    if (language == null || _busy) return;
    setState(() => _language = language);
    await widget.onLanguageChanged(language);
  }

  Future<bool> _confirm(
    String title,
    String explanation,
    String action,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: paper,
          title: Text(title),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_l10n.cancel),
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
    final notice = await DefaultAssetBundle.of(context).loadString(
      _l10n.isEnglish
          ? 'assets/privacy_notice_en.txt'
          : 'assets/privacy_notice.txt',
    );
    if (!mounted) return;
    final separator = notice.indexOf('\n\n');
    final title = separator < 0
        ? _l10n.privacyTitleFallback
        : notice.substring(0, separator);
    final body = separator < 0 ? notice : notice.substring(separator + 2);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paper,
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_l10n.close),
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
      if (mounted) {
        setState(() => _message = _l10n.localizeBackupError(error.message));
      }
    } catch (error, stack) {
      await Diagnostics.record(
        'settings.operation.failed',
        '${error.runtimeType}\n$stack',
      );
      if (mounted) setState(() => _message = _l10n.operationFailed);
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
              _l10n.dataDiagnostics,
              style: const TextStyle(fontSize: 25, color: ink),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AppLanguage>(
              key: ValueKey(_language),
              initialValue: _language,
              decoration: InputDecoration(labelText: _l10n.language),
              items: [
                DropdownMenuItem(
                  value: AppLanguage.system,
                  child: Text(_l10n.systemLanguage),
                ),
                DropdownMenuItem(
                  value: AppLanguage.simplifiedChinese,
                  child: Text(_l10n.simplifiedChinese),
                ),
                DropdownMenuItem(
                  value: AppLanguage.english,
                  child: Text(_l10n.english),
                ),
              ],
              onChanged: _changeLanguage,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _busy ? null : _showPrivacyNotice,
              child: Text(_l10n.privacyNotice),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => showLicensePage(
                      context: context,
                      applicationName: _l10n.appTitle,
                    ),
              child: Text(_l10n.openSourceLicenses),
            ),
            const SizedBox(height: 16),
            Text(_l10n.backupDescription),
            TextButton(
              onPressed: _busy ? null : () => _run(widget.onExport),
              child: Text(_l10n.exportBackup),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(widget.onImport),
              child: Text(_l10n.importBackup),
            ),
            Text(_l10n.importDescription),
            const Divider(),
            const SizedBox(height: 16),
            Text(_l10n.diagnosticsDescription),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () async => await Diagnostics.export()
                          ? _l10n.diagnosticsExported
                          : _l10n.exportCancelledShort,
                    ),
              child: Text(_l10n.exportDiagnostics),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!await _confirm(
                            _l10n.clearDiagnosticsTitle,
                            _l10n.clearDiagnosticsContent,
                            _l10n.confirmClearDiagnostics,
                          ) ||
                          !mounted) {
                        return;
                      }
                      await _run(() async {
                        await Diagnostics.clear();
                        return _l10n.diagnosticsCleared;
                      });
                    },
              child: Text(_l10n.confirmClearDiagnostics),
            ),
            const Divider(),
            Text(_l10n.destroyDescription),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!await _confirm(
                            _l10n.destroyTitle,
                            _l10n.destroyContent,
                            _l10n.confirmDestroy,
                          ) ||
                          !mounted) {
                        return;
                      }
                      await _run(widget.onDestroy);
                    },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(_l10n.confirmDestroy),
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _message!,
                  semanticsLabel: _message,
                  style: const TextStyle(color: ink),
                ),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(_l10n.close),
            ),
          ],
        ),
      ),
    ),
  );
}

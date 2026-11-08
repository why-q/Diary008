import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'journal_theme.dart';

class VolumeNameDialog extends StatefulWidget {
  const VolumeNameDialog({
    super.key,
    required this.volume,
    required this.initialName,
    this.sealingVolumeTitle,
  });

  final int volume;
  final String initialName;
  final String? sealingVolumeTitle;

  @override
  State<VolumeNameDialog> createState() => _VolumeNameDialogState();
}

class _VolumeNameDialogState extends State<VolumeNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.sealingVolumeTitle != null;
    final l10n = AppLocalizations.of(context);
    final fixedTitle = l10n.volumeTitle(widget.volume, '');
    return AlertDialog(
      backgroundColor: paper,
      scrollable: true,
      title: Text(l10n.newVolumeTitle(fixedTitle, creating)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (creating) ...[
            Text(
              l10n.sealingVolume(widget.sealingVolumeTitle!),
              style: const TextStyle(fontSize: 16, height: 1.7),
            ),
            const SizedBox(height: 18),
          ],
          TextField(
            controller: _name,
            autofocus: true,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.volumeNameLabel,
              hintText: l10n.volumeNameHint,
              helperText: l10n.volumeNameHelper(fixedTitle),
              helperMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _name.text.trim()),
          child: Text(creating ? l10n.archiveAndCreate : l10n.save),
        ),
      ],
    );
  }
}

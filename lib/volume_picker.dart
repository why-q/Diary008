import 'package:flutter/material.dart';

import 'app_localizations.dart';
import 'journal_theme.dart';
import 'notebook.dart';

enum VolumeAction { open, create, rename, delete }

class VolumeSelection {
  const VolumeSelection.open(int this.volume) : action = VolumeAction.open;
  const VolumeSelection.create() : action = VolumeAction.create, volume = null;
  const VolumeSelection.rename() : action = VolumeAction.rename, volume = null;
  const VolumeSelection.delete(int this.volume) : action = VolumeAction.delete;

  final VolumeAction action;
  final int? volume;
}

class VolumePicker extends StatelessWidget {
  const VolumePicker({super.key, required this.book});
  final Notebook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.volumePickerTitle,
                textAlign: TextAlign.center,
                style: journalText.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        VolumeSelection.open(book.volume),
                      ),
                      child: Text(
                        l10n.writingVolume(
                          l10n.volumeTitle(book.volume, book.volumeName),
                        ),
                      ),
                    ),
                    ...book.archives.reversed.map(
                      (archive) => Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(
                                context,
                                VolumeSelection.open(archive.volume),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      l10n.archivedVolume(
                                        l10n.volumeTitle(
                                          archive.volume,
                                          archive.volumeName,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.dateFormat(
                                        archive.archivedAt.toLocal(),
                                      ),
                                      key: const Key('archived-volume-date'),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: journalThemeOf(context).fadedInk,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            key: const Key('archive-delete'),
                            onPressed: () =>
                                _confirmDeleteArchive(context, archive),
                            child: Text(l10n.delete),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const VolumeSelection.rename()),
                child: Text(l10n.renameCurrentVolume),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const VolumeSelection.create()),
                child: Text(l10n.createVolume),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteArchive(
  BuildContext sheetContext,
  NotebookArchive archive,
) async {
  final l10n = AppLocalizations.of(sheetContext);
  final title = l10n.volumeTitle(archive.volume, archive.volumeName);
  final confirmed = await showDialog<bool>(
    context: sheetContext,
    builder: (context) => AlertDialog(
      key: const Key('archive-delete-confirmation'),
      backgroundColor: journalThemeOf(context).paper,
      title: Text(l10n.deleteArchivedTitle),
      content: Text(
        l10n.deleteArchivedContent(title),
        style: const TextStyle(fontSize: 16, height: 1.7),
      ),
      actions: [
        TextButton(
          key: const Key('archive-delete-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed == true && sheetContext.mounted) {
    Navigator.pop(sheetContext, VolumeSelection.delete(archive.volume));
  }
}

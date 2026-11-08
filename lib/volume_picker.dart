import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '翻阅卷册',
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
                      '${journalVolumeTitle(book.volume, book.volumeName)} · 正在书写',
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
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  Text(
                                    '${journalVolumeTitle(archive.volume, archive.volumeName)} · 已封存',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    journalDate(archive.archivedAt.toLocal()),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: fadedInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _confirmDeleteArchive(context, archive),
                          child: const Text('删除'),
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
              child: const Text('修改当前卷名'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const VolumeSelection.create()),
              child: const Text('新建一卷'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _confirmDeleteArchive(
  BuildContext sheetContext,
  NotebookArchive archive,
) async {
  final title = journalVolumeTitle(archive.volume, archive.volumeName);
  final confirmed = await showDialog<bool>(
    context: sheetContext,
    builder: (context) => AlertDialog(
      backgroundColor: paper,
      title: const Text('删除封存卷'),
      content: Text(
        '$title中的记录将永久删除，无法恢复。其后各卷的卷号会依次前移。',
        style: const TextStyle(fontSize: 16, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed == true && sheetContext.mounted) {
    Navigator.pop(sheetContext, VolumeSelection.delete(archive.volume));
  }
}

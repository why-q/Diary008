import 'package:flutter/material.dart';

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
    final fixedTitle = journalVolumeTitle(widget.volume, '');
    return AlertDialog(
      backgroundColor: journalThemeOf(context).paper,
      scrollable: true,
      title: Text(creating ? '新建$fixedTitle' : '修改卷名'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (creating) ...[
            Text(
              '${widget.sealingVolumeTitle}将永久封存，无法继续编辑，也不再提醒。',
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
              labelText: '卷名（选填）',
              hintText: '例如：晨间计划',
              helperText: '卷号固定为$fixedTitle；留空只显示卷号。',
              helperMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _name.text.trim()),
          child: Text(creating ? '封存并新建' : '保存'),
        ),
      ],
    );
  }
}

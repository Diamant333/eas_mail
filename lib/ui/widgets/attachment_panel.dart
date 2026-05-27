import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../mail/models/mail_attachment.dart';
import '../../mail/models/mail_message.dart';
import '../../services/mail_session.dart';

class AttachmentPanel extends StatefulWidget {
  const AttachmentPanel({super.key, required this.message});

  final MailMessage message;

  @override
  State<AttachmentPanel> createState() => _AttachmentPanelState();
}

class _AttachmentPanelState extends State<AttachmentPanel> {
  int? _loadingIndex;
  final Map<int, Uint8List> _previewCache = {};

  bool _isImage(MailAttachment att) {
    final n = att.displayName.toLowerCase();
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp');
  }

  Future<void> _loadPreview(int index) async {
    if (_previewCache.containsKey(index)) return;
    setState(() => _loadingIndex = index);
    try {
      final session = context.read<MailSession>();
      final bytes = await session.loadAttachmentBytes(
        message: widget.message,
        attachmentIndex: index,
      );
      if (mounted) {
        setState(() => _previewCache[index] = bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingIndex = null);
    }
  }

  Future<void> _saveAndOpen(int index) async {
    setState(() => _loadingIndex = index);
    try {
      final session = context.read<MailSession>();
      final path = await session.downloadAttachment(
        message: widget.message,
        attachmentIndex: index,
      );
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.message.hasAttachments) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Вложения (${widget.message.attachments.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        ...List.generate(widget.message.attachments.length, (i) {
          final att = widget.message.attachments[i];
          final loading = _loadingIndex == i;
          final preview = _previewCache[i];

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ExpansionTile(
              leading: const Icon(Icons.attach_file),
              title: Text(att.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: att.size != null ? Text('${att.size} байт') : null,
              children: [
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (preview != null && _isImage(att))
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(preview, fit: BoxFit.contain),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: loading ? null : () => _loadPreview(i),
                        icon: const Icon(Icons.visibility),
                        label: const Text('Просмотр'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: loading ? null : () => _saveAndOpen(i),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Открыть файл'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

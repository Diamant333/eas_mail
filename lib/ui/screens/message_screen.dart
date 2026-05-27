import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../mail/models/mail_message.dart';
import '../../services/mail_session.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key, required this.message});

  final MailMessage message;

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  int? _downloadingIndex;

  Future<void> _download(int index) async {
    setState(() => _downloadingIndex = index);
    final session = context.read<MailSession>();
    try {
      final path = await session.downloadAttachment(
        message: widget.message,
        attachmentIndex: index,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранено: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final date = message.dateReceived != null
        ? DateFormat('dd MMMM yyyy, HH:mm')
            .format(message.dateReceived!.toLocal())
        : '';

    return Scaffold(
      appBar: AppBar(title: const Text('Письмо')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            message.subject,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text('От: ${message.from}'),
          if (message.to != null) Text('Кому: ${message.to}'),
          if (date.isNotEmpty) Text('Дата: $date'),
          if (message.hasAttachments) ...[
            const Divider(height: 32),
            Text(
              'Вложения',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...List.generate(message.attachments.length, (i) {
              final att = message.attachments[i];
              final loading = _downloadingIndex == i;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(att.displayName),
                  subtitle: att.isInline ? const Text('Встроенное') : null,
                  trailing: loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _download(i),
                          tooltip: 'Скачать',
                        ),
                ),
              );
            }),
          ],
          const Divider(height: 32),
          SelectableText(
            message.body?.trim().isNotEmpty == true
                ? message.body!
                : '(текст письма недоступен)',
          ),
        ],
      ),
    );
  }
}

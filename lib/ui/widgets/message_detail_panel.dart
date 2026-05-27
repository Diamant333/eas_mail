import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/mail_session.dart';
import 'attachment_panel.dart';
import 'html_message_view.dart';

class MessageDetailPanel extends StatelessWidget {
  const MessageDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final message = session.selectedMessage;

    if (message == null) {
      return Center(
        child: Text(
          'Выберите письмо',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    final date = message.dateReceived != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(message.dateReceived!.toLocal())
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.subject,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('От: ${message.from}'),
                if (message.to != null) Text('Кому: ${message.to}'),
                if (date != null) Text('Дата: $date'),
              ],
            ),
          ),
        ),
        AttachmentPanel(message: message),
        // ── Body ──────────────────────────────────────────────────────────
        Expanded(
          child: _buildBody(context, session, message),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, MailSession session, message) {
    if (message.bodyLoaded) {
      return HtmlMessageView(html: message.displayHtml);
    }

    // Body not yet loaded.
    if (session.isBodyLoading(message)) {
      return const Center(child: CircularProgressIndicator());
    }

    // Load failed — show retry.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'Не удалось загрузить содержимое письма',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить'),
            onPressed: () => session.selectMessage(message),
          ),
        ],
      ),
    );
  }
}

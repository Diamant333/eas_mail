import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/mail_session.dart';
import 'login_screen.dart';
import 'compose_screen.dart';
import 'message_screen.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(session.account?.email ?? 'Входящие'),
        bottom: session.account != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    session.isImap ? 'IMAP' : 'Exchange ActiveSync',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            onPressed: session.loading ? null : () => session.refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
          IconButton(
            onPressed: () async {
              await session.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: session.loading && session.messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : session.messages.isEmpty
              ? Center(
                  child: Text(
                    session.error ?? 'Нет писем',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: session.refresh,
                  child: ListView.separated(
                    itemCount: session.messages.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final msg = session.messages[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            msg.from.isNotEmpty
                                ? msg.from[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(
                          msg.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                msg.read ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.from,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (msg.dateReceived != null)
                              Text(
                                dateFormat.format(msg.dateReceived!.toLocal()),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        isThreeLine: msg.dateReceived != null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (msg.hasAttachments)
                              const Icon(Icons.attach_file, size: 18),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MessageScreen(message: msg),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const ComposeScreen()),
          );
        },
        tooltip: 'Написать',
        child: const Icon(Icons.edit),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/mail_session.dart';
import '../widgets/mail_layout.dart';
import 'address_book_screen.dart';
import 'compose_screen.dart';
import 'settings_screen.dart';

class MailShell extends StatefulWidget {
  const MailShell({super.key});

  @override
  State<MailShell> createState() => _MailShellState();
}

class _MailShellState extends State<MailShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _compose({String? prefilledTo}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(prefilledTo: prefilledTo),
      ),
    );
  }

  void _reply() {
    final session = context.read<MailSession>();
    final msg = session.selectedMessage;
    if (msg == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(replyTo: msg),
      ),
    );
  }

  void _forward() {
    final session = context.read<MailSession>();
    final msg = session.selectedMessage;
    if (msg == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(forwardOf: msg),
      ),
    );
  }

  Future<void> _delete() async {
    final session = context.read<MailSession>();
    final msg = session.selectedMessage;
    if (msg == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить письмо?'),
        content: Text(
          msg.subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      // ignore: use_build_context_synchronously
      context.read<MailSession>().deleteMessage(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final hasSelected = session.selectedMessage != null;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(
          session.account?.email ?? 'Почта',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Compose
          IconButton(
            onPressed: _compose,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Новое сообщение',
          ),
          // Reply
          IconButton(
            onPressed: hasSelected ? _reply : null,
            icon: const Icon(Icons.reply_outlined),
            tooltip: 'Ответить',
          ),
          // Forward
          IconButton(
            onPressed: hasSelected ? _forward : null,
            icon: const Icon(Icons.forward_outlined),
            tooltip: 'Переслать',
          ),
          // Delete
          IconButton(
            onPressed: hasSelected ? _delete : null,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Удалить',
          ),
          // Refresh
          IconButton(
            onPressed: (session.loading || session.syncing) ? null : () => session.refresh(),
            icon: (session.loading || session.syncing)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
            tooltip: 'Обновить',
          ),
        ],
        bottom: session.syncing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      drawer: _buildDrawer(context, session),
      body: const MailLayout(),
    );
  }

  Widget _buildDrawer(BuildContext context, MailSession session) {
    return Drawer(
      child: Column(
        children: [
          // Account header
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    radius: 24,
                    child: Text(
                      session.account?.email.isNotEmpty == true
                          ? session.account!.email[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.account?.email ?? '—',
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (session.accounts.length > 1)
                    Text(
                      '${session.accounts.length} аккаунта',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          // Navigation items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: Text('Входящие (${session.messages.length})'),
                  onTap: () {
                    Navigator.pop(context);
                    _selectInbox(session);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.contacts_outlined),
                  title: const Text('Адресная книга'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddressBookScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Настройки'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectInbox(MailSession session) {
    final inbox = session.folders.where((f) => f.isInbox).firstOrNull;
    if (inbox != null) {
      session.selectFolder(inbox.id);
    } else {
      session.refresh();
    }
  }
}

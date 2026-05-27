import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/mail_session.dart';
import 'login_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final accounts = session.accounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Учётные записи'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Добавить аккаунт',
            onPressed: () => _addAccount(context),
          ),
        ],
      ),
      body: accounts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Нет учётных записей'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _addAccount(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (ctx, i) {
                final acc = accounts[i];
                final isActive = i == session.activeAccountIndex;
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(acc.email.isNotEmpty ? acc.email[0].toUpperCase() : '?'),
                  ),
                  title: Text(acc.email),
                  subtitle: Text(acc.isEas ? 'Exchange (EAS)' : 'IMAP/SMTP'),
                  selected: isActive,
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isActive)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Удалить',
                        onPressed: () => _confirmDelete(context, session, i),
                      ),
                    ],
                  ),
                  onTap: isActive
                      ? null
                      : () async {
                          await session.switchAccount(i);
                          if (context.mounted) Navigator.pop(context);
                        },
                );
              },
            ),
      bottomNavigationBar: accounts.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () => _confirmSignOut(context, session),
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти из всех аккаунтов'),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _addAccount(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen(addMode: true)),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, MailSession session, int index) async {
    final acc = session.accounts[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: Text(acc.email),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await session.removeAccount(index);
    if (context.mounted && session.accounts.isEmpty) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context, MailSession session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из всех аккаунтов?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await session.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../services/app_settings.dart';
import '../../services/carddav_service.dart';
import '../../services/mail_session.dart';
import 'compose_screen.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  int? _selectedConfigIndex;
  List<Contact> _contacts = [];
  bool _loading = false;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Contact> get _filtered {
    if (_query.isEmpty) return _contacts;
    return _contacts.where((c) {
      return c.displayName.toLowerCase().contains(_query) ||
          c.emails.any((e) => e.toLowerCase().contains(_query)) ||
          (c.organization?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }

  Future<void> _fetchContacts(CardDavConfig config) async {
    setState(() {
      _loading = true;
      _error = null;
      _contacts = [];
    });
    try {
      final contacts = await CardDavService().fetchContacts(config);
      contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
      setState(() => _contacts = contacts);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final configs = session.settings.carddavConfigs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Адресная книга'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Добавить CardDAV',
            onPressed: () => _showAddDialog(context, session),
          ),
        ],
      ),
      body: configs.isEmpty && _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.contacts_outlined, size: 64),
                  const SizedBox(height: 16),
                  const Text('Нет подключённых адресных книг'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context, session),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить CardDAV'),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                // Sidebar with configs
                if (configs.isNotEmpty)
                  Container(
                    width: 200,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Серверы',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            itemCount: configs.length,
                            itemBuilder: (ctx, i) {
                              final cfg = configs[i];
                              final isSelected = _selectedConfigIndex == i;
                              return ListTile(
                                selected: isSelected,
                                title: Text(
                                  cfg.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  cfg.username,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      tooltip: 'Изменить',
                                      onPressed: () =>
                                          _showEditDialog(context, session, i),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      tooltip: 'Удалить',
                                      onPressed: () =>
                                          _deleteConfig(context, session, i),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() => _selectedConfigIndex = i);
                                  _fetchContacts(cfg);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const VerticalDivider(width: 1),
                // Contacts list
                Expanded(
                  child: Column(
                    children: [
                      if (_contacts.isNotEmpty || _loading)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Поиск...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      if (_loading)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_error != null)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red),
                                const SizedBox(height: 8),
                                Text(_error!),
                              ],
                            ),
                          ),
                        )
                      else if (_contacts.isEmpty && _selectedConfigIndex != null)
                        const Expanded(
                          child: Center(child: Text('Нет контактов')),
                        )
                      else if (_contacts.isEmpty)
                        const Expanded(
                          child: Center(child: Text('Выберите сервер слева')),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) {
                              final contact = _filtered[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    contact.displayName.isNotEmpty
                                        ? contact.displayName[0].toUpperCase()
                                        : '?',
                                  ),
                                ),
                                title: Text(contact.displayName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (contact.primaryEmail.isNotEmpty)
                                      Text(contact.primaryEmail),
                                    if (contact.organization != null)
                                      Text(
                                        contact.organization!,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                isThreeLine: contact.organization != null,
                                trailing: contact.primaryEmail.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.send_outlined),
                                        tooltip: 'Написать',
                                        onPressed: () => _composeToContact(context, contact),
                                      )
                                    : null,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, MailSession session) async {
    final result = await showDialog<CardDavConfig>(
      context: context,
      builder: (ctx) => const _CardDavDialog(),
    );
    if (result == null) return;
    final newList = [...session.settings.carddavConfigs, result];
    await session.settings.setCarddavConfigs(newList);
    if (context.mounted) setState(() {});
  }

  Future<void> _showEditDialog(
      BuildContext context, MailSession session, int index) async {
    final existing = session.settings.carddavConfigs[index];
    final result = await showDialog<CardDavConfig>(
      context: context,
      builder: (ctx) => _CardDavDialog(existing: existing),
    );
    if (result == null) return;
    final newList = List<CardDavConfig>.from(session.settings.carddavConfigs);
    newList[index] = result;
    await session.settings.setCarddavConfigs(newList);
    if (context.mounted) {
      setState(() {
        if (_selectedConfigIndex == index) {
          _fetchContacts(result);
        }
      });
    }
  }

  Future<void> _deleteConfig(
      BuildContext context, MailSession session, int index) async {
    final newList = List<CardDavConfig>.from(session.settings.carddavConfigs)
      ..removeAt(index);
    await session.settings.setCarddavConfigs(newList);
    if (_selectedConfigIndex == index) {
      setState(() {
        _selectedConfigIndex = null;
        _contacts = [];
      });
    } else {
      setState(() {});
    }
  }

  void _composeToContact(BuildContext context, Contact contact) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(prefilledTo: contact.primaryEmail),
      ),
    );
  }
}

class _CardDavDialog extends StatefulWidget {
  const _CardDavDialog({this.existing});

  final CardDavConfig? existing;

  @override
  State<_CardDavDialog> createState() => _CardDavDialogState();
}

class _CardDavDialogState extends State<_CardDavDialog> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late final TextEditingController _name;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _url = TextEditingController(text: e?.serverUrl ?? '');
    _user = TextEditingController(text: e?.username ?? '');
    _pass = TextEditingController(text: e?.password ?? '');
    _name = TextEditingController(text: e?.displayName ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Изменить CardDAV' : 'Подключить CardDAV'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Название (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'URL сервера',
                hintText: 'https://example.com/carddav/user/',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Логин',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Пароль',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final url = _url.text.trim();
            final user = _user.text.trim();
            final pass = _pass.text;
            if (url.isEmpty || user.isEmpty || pass.isEmpty) return;
            Navigator.pop(
              context,
              CardDavConfig(
                serverUrl: url,
                username: user,
                password: pass,
                displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
              ),
            );
          },
          child: Text(isEdit ? 'Сохранить' : 'Подключить'),
        ),
      ],
    );
  }
}

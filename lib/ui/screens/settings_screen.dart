import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message_layout.dart';
import '../../services/app_settings.dart';
import '../../services/mail_session.dart';
import 'account_edit_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _intervals = [
    (label: '1 минута', value: 60),
    (label: '5 минут', value: 300),
    (label: '10 минут', value: 600),
    (label: '15 минут', value: 900),
    (label: '30 минут', value: 1800),
    (label: '1 час', value: 3600),
    (label: 'Вручную', value: 0),
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final settings = session.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Sync interval ────────────────────────────────────────────────
          Text('Синхронизация', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<int>(
                initialValue: _matchInterval(settings.syncIntervalSeconds),
                decoration: const InputDecoration(
                  labelText: 'Период синхронизации',
                  border: InputBorder.none,
                ),
                items: _intervals
                    .map((e) => DropdownMenuItem(
                          value: e.value,
                          child: Text(e.label),
                        ))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  await session.updateSyncInterval(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Layout ───────────────────────────────────────────────────────
          Text('Расположение панелей', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<MessagePaneLayout>(
              groupValue: session.paneLayout,
              onChanged: (v) {
                if (v != null) session.setPaneLayout(v);
              },
              child: Column(
                children: MessagePaneLayout.values.map((layout) {
                  return ListTile(
                    title: Text(layout.title),
                    leading: Radio<MessagePaneLayout>(value: layout),
                    onTap: () => session.setPaneLayout(layout),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Folder sort order ────────────────────────────────────────────
          Text('Порядок папок', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<FolderSortOrder>(
                initialValue: settings.folderSortOrder,
                decoration: const InputDecoration(
                  labelText: 'Порядок отображения папок',
                  border: InputBorder.none,
                ),
                items: const [
                  DropdownMenuItem(
                    value: FolderSortOrder.serverOrder,
                    child: Text('Как на сервере'),
                  ),
                  DropdownMenuItem(
                    value: FolderSortOrder.alphabetical,
                    child: Text('По алфавиту'),
                  ),
                  DropdownMenuItem(
                    value: FolderSortOrder.systemFirst,
                    child: Text('Системные вперёд'),
                  ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await session.settings.setFolderSortOrder(v);
                  if (context.mounted) setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Appearance ────────────────────────────────────────────────────
          Text('Внешний вид', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _AppearanceSection(settings: settings),
            ),
          ),
          const SizedBox(height: 24),

          // ── Accounts ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'Учётные записи',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(addMode: true),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (int i = 0; i < session.accounts.length; i++)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(
                        session.accounts[i].email.isNotEmpty
                            ? session.accounts[i].email[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(
                      session.accounts[i].email,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      session.accounts[i].protocol.name.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i == session.activeAccountIndex)
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Изменить',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AccountEditScreen(accountIndex: i),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Удалить',
                          onPressed: () => _deleteAccount(context, session, i),
                        ),
                      ],
                    ),
                    onTap: i == session.activeAccountIndex
                        ? null
                        : () => session.switchAccount(i),
                  ),
                if (session.accounts.isEmpty)
                  const ListTile(
                    title: Text('Нет учётных записей'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Labels ───────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'Метки',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _addLabel(context, session),
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (int i = 0; i < settings.labelPresets.length; i++)
                  _LabelRow(
                    preset: settings.labelPresets[i],
                    onEdit: () => _editLabel(context, session, i),
                    onDelete: () => _deleteLabel(context, session, i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(
      BuildContext context, MailSession session, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить учётную запись?'),
        content: Text(session.accounts[index].email),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirm != true) return;
    await session.removeAccount(index);
    if (context.mounted) {
      if (session.accounts.isEmpty) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else {
        setState(() {});
      }
    }
  }

  int _matchInterval(int seconds) {
    for (final item in _intervals) {
      if (item.value == seconds) return seconds;
    }
    return 300;
  }

  Future<void> _addLabel(BuildContext context, MailSession session) async {
    final result = await showDialog<LabelPreset>(
      context: context,
      builder: (ctx) => const _LabelEditDialog(),
    );
    if (result == null) return;
    final newList = [...session.settings.labelPresets, result];
    await session.settings.setLabelPresets(newList);
    if (context.mounted) setState(() {});
  }

  Future<void> _editLabel(
      BuildContext context, MailSession session, int index) async {
    final result = await showDialog<LabelPreset>(
      context: context,
      builder: (ctx) =>
          _LabelEditDialog(existing: session.settings.labelPresets[index]),
    );
    if (result == null) return;
    final newList = List<LabelPreset>.from(session.settings.labelPresets);
    newList[index] = result;
    await session.settings.setLabelPresets(newList);
    if (context.mounted) setState(() {});
  }

  Future<void> _deleteLabel(
      BuildContext context, MailSession session, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить метку?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (confirm != true) return;
    final newList = List<LabelPreset>.from(session.settings.labelPresets)
      ..removeAt(index);
    await session.settings.setLabelPresets(newList);
    if (context.mounted) setState(() {});
  }
}

// ── Appearance section widget ─────────────────────────────────────────────────

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection({required this.settings});

  final AppSettings settings;

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late TextEditingController _appNameCtrl;

  @override
  void initState() {
    super.initState();
    _appNameCtrl = TextEditingController(text: widget.settings.appName);
  }

  @override
  void dispose() {
    _appNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSplashImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;
    await widget.settings.setSplashImagePath(file.path);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final splashPath = widget.settings.splashImagePath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App name
        Text('Название приложения',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _appNameCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'EAS Mail',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                widget.settings.setAppName(_appNameCtrl.text).then((_) {
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Название обновится при следующем запуске'),
                      ),
                    );
                  }
                });
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // Splash image
        Text('Экран загрузки (Splash Screen)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(
          'Рекомендуемые параметры изображения:\n'
          '• Формат: PNG\n'
          '• Размер: 1080×1920 пикселей (портрет) или 1920×1080 (пейзаж)\n'
          '• Разрешение: 72–144 DPI\n'
          '• Фоновое изображение без прозрачности',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 10),
        if (splashPath != null && !kIsWeb)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(splashPath),
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (context, error, s) =>
                    const Icon(Icons.broken_image, size: 60),
              ),
            ),
          ),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickSplashImage,
              icon: const Icon(Icons.upload_outlined, size: 16),
              label: Text(splashPath != null ? 'Заменить' : 'Выбрать изображение'),
            ),
            if (splashPath != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  await widget.settings.setSplashImagePath(null);
                  if (mounted) setState(() {});
                },
                child: const Text('Сбросить'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // App icon info
        Text('Иконка приложения',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(
          'Иконка приложения задаётся на этапе сборки (flutter_launcher_icons).\n'
          'Требования к файлу:\n'
          '• Формат: PNG\n'
          '• Размер: 1024×1024 пикселей, квадратное\n'
          '• Без скруглённых углов (система добавляет форму автоматически)\n'
          '• Путь задаётся в pubspec.yaml: flutter_launcher_icons → image_path',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({
    required this.preset,
    required this.onEdit,
    required this.onDelete,
  });

  final LabelPreset preset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color(preset.color),
        radius: 12,
      ),
      title: Text(preset.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
            tooltip: 'Изменить',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
            tooltip: 'Удалить',
          ),
        ],
      ),
    );
  }
}

class _LabelEditDialog extends StatefulWidget {
  const _LabelEditDialog({this.existing});

  final LabelPreset? existing;

  @override
  State<_LabelEditDialog> createState() => _LabelEditDialogState();
}

class _LabelEditDialogState extends State<_LabelEditDialog> {
  late final TextEditingController _name;
  late int _color;

  static const _palette = [
    0xFFFFCDD2, 0xFFFFE0B2, 0xFFFFF9C4, 0xFFC8E6C9,
    0xFFB3E5FC, 0xFFBBDEFB, 0xFFE1BEE7, 0xFFE0E0E0,
    0xFFFF8A80, 0xFFFFD180, 0xFFFFFF8D, 0xFFCCFF90,
    0xFF80D8FF, 0xFF82B1FF, 0xFFEA80FC, 0xFFCFD8DC,
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.color ?? _palette.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новая метка' : 'Изменить метку'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette.map((c) {
                final selected = _color == c;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
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
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, LabelPreset(name: name, color: _color));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

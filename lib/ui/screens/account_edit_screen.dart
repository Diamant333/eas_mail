import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../../mail/models/mail_account.dart';
import '../../models/mail_folder.dart';
import '../../services/mail_session.dart';

class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key, required this.accountIndex});

  final int accountIndex;

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _saving = false;

  // ── Connection fields ──────────────────────────────────────────────────────
  late TextEditingController _displayName;
  late TextEditingController _password;
  late TextEditingController _server;
  late TextEditingController _domain;
  late TextEditingController _imapHost;
  late TextEditingController _imapPort;
  late TextEditingController _smtpHost;
  late TextEditingController _smtpPort;
  late bool _imapSsl;
  late bool _smtpSsl;
  bool _obscurePass = true;

  // ── Folder prefs ───────────────────────────────────────────────────────────
  late List<MailFolder> _folderList;
  late Set<String> _hidden;

  // ── Signature fields ───────────────────────────────────────────────────────
  // Initialised in didChangeDependencies (before first build).
  late quill.QuillController _sigQuill;
  bool _sigQuillReady = false;
  late bool _sigOnCompose;
  late bool _sigOnReply;
  late bool _sigOnForward;
  String? _senderIconPath;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    // All field initialisation that requires context.read is deferred to
    // didChangeDependencies — the element is fully active there (unlike
    // initState), which avoids the '_elements.contains(element)' assertion
    // in newer Flutter versions.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sigQuillReady) return; // only initialise once
    _sigQuillReady = true;

    final session = context.read<MailSession>();
    final acc = session.accounts[widget.accountIndex];

    _displayName = TextEditingController(text: acc.displayName ?? '');
    _password = TextEditingController(text: acc.password);
    _server = TextEditingController(text: acc.serverUrl);
    _domain = TextEditingController(text: acc.domain ?? '');
    _imapHost = TextEditingController(text: acc.imapHost);
    _imapPort = TextEditingController(text: acc.imapPort.toString());
    _smtpHost = TextEditingController(text: acc.smtpHost);
    _smtpPort = TextEditingController(text: acc.smtpPort.toString());
    _imapSsl = acc.imapSsl;
    _smtpSsl = acc.smtpSsl;

    _hidden = Set.from(session.folderPrefs.hiddenFolderIds);

    final allFolders = session.folders;
    final customOrder = session.folderPrefs.customOrder;
    if (customOrder.isNotEmpty) {
      final orderMap = {for (var i = 0; i < customOrder.length; i++) customOrder[i]: i};
      _folderList = List.from(allFolders)
        ..sort((a, b) {
          final ai = orderMap[a.id] ?? 9999;
          final bi = orderMap[b.id] ?? 9999;
          return ai.compareTo(bi);
        });
    } else {
      _folderList = List.from(allFolders);
    }

    // Signature — assign once, no placeholder to dispose.
    _sigOnCompose = acc.signatureOnCompose;
    _sigOnReply = acc.signatureOnReply;
    _sigOnForward = acc.signatureOnForward;
    _senderIconPath = acc.senderIconPath;
    _sigQuill = _htmlToController(acc.signature);
  }

  quill.QuillController _htmlToController(String html) {
    if (html.trim().isEmpty) return quill.QuillController.basic();
    try {
      final delta = HtmlToDelta().convert(html);
      final doc = quill.Document.fromDelta(delta);
      return quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return quill.QuillController.basic();
    }
  }

  String _controllerToHtml() {
    final delta = _sigQuill.document.toDelta();
    final converter = QuillDeltaToHtmlConverter(
      delta.toJson().cast<Map<String, dynamic>>(),
      ConverterOptions.forEmail(),
    );
    return converter.convert();
  }

  @override
  void dispose() {
    _tabs.dispose();
    if (_sigQuillReady) {
      _displayName.dispose();
      _password.dispose();
      _server.dispose();
      _domain.dispose();
      _imapHost.dispose();
      _imapPort.dispose();
      _smtpHost.dispose();
      _smtpPort.dispose();
      _sigQuill.dispose();
    }
    super.dispose();
  }

  Future<void> _saveConnection() async {
    final session = context.read<MailSession>();
    final acc = session.accounts[widget.accountIndex];

    final serverText = _server.text.trim();
    final domainText = _domain.text.trim();
    final imapHostText = _imapHost.text.trim();
    final smtpHostText = _smtpHost.text.trim();

    final updated = acc.copyWith(
      displayName: _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
      password: _password.text.isNotEmpty ? _password.text : null,
      serverUrl: (acc.isEas && serverText.isNotEmpty) ? serverText : null,
      domain: acc.isEas ? (domainText.isEmpty ? null : domainText) : null,
      imapHost: (acc.isImap && imapHostText.isNotEmpty) ? imapHostText : null,
      imapPort: acc.isImap ? (int.tryParse(_imapPort.text) ?? acc.imapPort) : null,
      imapSsl: acc.isImap ? _imapSsl : null,
      smtpHost: (acc.isImap && smtpHostText.isNotEmpty) ? smtpHostText : null,
      smtpPort: acc.isImap ? (int.tryParse(_smtpPort.text) ?? acc.smtpPort) : null,
      smtpSsl: acc.isImap ? _smtpSsl : null,
    );

    setState(() => _saving = true);
    try {
      await session.reconnectAccount(widget.accountIndex, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сохранены')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveFolderPrefs() async {
    final session = context.read<MailSession>();
    setState(() => _saving = true);
    try {
      await session.updateFolderPrefs(
        order: _folderList.map((f) => f.id).toList(),
        hidden: _hidden,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Порядок папок сохранён')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSignature() async {
    final session = context.read<MailSession>();
    final acc = session.accounts[widget.accountIndex];
    final sigHtml = _controllerToHtml();
    final updated = acc.copyWith(
      signature: sigHtml,
      signatureOnCompose: _sigOnCompose,
      signatureOnReply: _sigOnReply,
      signatureOnForward: _sigOnForward,
      senderIconPath: _senderIconPath,
    );
    setState(() => _saving = true);
    try {
      await session.updateAccount(widget.accountIndex, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подпись сохранена')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSenderIcon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) return;

    // Save to documents directory.
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      final iconsDir = Directory(p.join(dir.path, 'sender_icons'));
      await iconsDir.create(recursive: true);
      final safeName = file.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final destFile = File(p.join(iconsDir.path, safeName));
      await destFile.writeAsBytes(bytes);
      setState(() => _senderIconPath = destFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final acc = session.accounts[widget.accountIndex];
    final isActive = widget.accountIndex == session.activeAccountIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text(acc.displayName?.isNotEmpty == true ? acc.displayName! : acc.email),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Подключение'),
            Tab(text: 'Папки'),
            Tab(text: 'Подпись'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildConnectionTab(acc),
          isActive
              ? _buildFoldersTab()
              : const Center(
                  child: Text(
                    'Переключитесь на этот аккаунт\nчтобы настроить папки',
                    textAlign: TextAlign.center,
                  ),
                ),
          _buildSignatureTab(),
        ],
      ),
    );
  }

  Widget _buildConnectionTab(MailAccount acc) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextFormField(
          controller: _displayName,
          decoration: const InputDecoration(
            labelText: 'Отображаемое имя (необязательно)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _password,
          obscureText: _obscurePass,
          decoration: InputDecoration(
            labelText: 'Пароль',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
        ),
        if (acc.isEas && !acc.usesOAuth) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _domain,
            decoration: const InputDecoration(
              labelText: 'Домен (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _server,
            decoration: const InputDecoration(
              labelText: 'Сервер Exchange',
              hintText: 'mail.company.ru',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (acc.isImap) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _imapHost,
            decoration: const InputDecoration(
              labelText: 'IMAP сервер',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _imapPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'IMAP порт',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('SSL'),
                selected: _imapSsl,
                onSelected: (v) => setState(() => _imapSsl = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _smtpHost,
            decoration: const InputDecoration(
              labelText: 'SMTP сервер',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _smtpPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'SMTP порт',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('SSL/TLS'),
                selected: _smtpSsl,
                onSelected: (v) => setState(() => _smtpSsl = v),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _saveConnection,
          child: _saving
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сохранить и переподключиться'),
        ),
      ],
    );
  }

  Widget _buildFoldersTab() {
    if (_folderList.isEmpty) {
      return const Center(child: Text('Нет папок'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Перетащите для изменения порядка.\nСнимите флажок чтобы скрыть папку.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _saveFolderPrefs,
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: _folderList.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _folderList.removeAt(oldIndex);
                _folderList.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final folder = _folderList[index];
              final visible = !_hidden.contains(folder.id);
              return ListTile(
                key: ValueKey(folder.id),
                leading: Icon(_folderIcon(folder.type)),
                title: Text(folder.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: visible,
                      onChanged: (v) => setState(() {
                        if (v) {
                          _hidden.remove(folder.id);
                        } else {
                          _hidden.add(folder.id);
                        }
                      }),
                    ),
                    const Icon(Icons.drag_handle, color: Colors.grey),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureTab() {
    return Column(
      children: [
        // ── Use-signature checkboxes ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Добавлять подпись при:',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Создании письма'),
                value: _sigOnCompose,
                onChanged: (v) => setState(() => _sigOnCompose = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Ответе'),
                value: _sigOnReply,
                onChanged: (v) => setState(() => _sigOnReply = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Пересылке'),
                value: _sigOnForward,
                onChanged: (v) => setState(() => _sigOnForward = v ?? false),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Sender icon ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text('Иконка отправителя:',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 12),
              if (_senderIconPath != null && !kIsWeb)
                ClipOval(
                  child: Image.file(
                    File(_senderIconPath!),
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, s) => const Icon(Icons.broken_image, size: 40),
                  ),
                )
              else
                const CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.person_outline, size: 20),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _pickSenderIcon,
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: const Text('Выбрать'),
              ),
              if (_senderIconPath != null)
                TextButton(
                  onPressed: () => setState(() => _senderIconPath = null),
                  child: const Text('Удалить'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Изображение: квадратное, рекомендуется 256×256 пикселей, PNG или JPG.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const Divider(height: 1),
        // ── Signature editor toolbar ──────────────────────────────────────────
        quill.QuillSimpleToolbar(
          controller: _sigQuill,
          config: quill.QuillSimpleToolbarConfig(
            showFontFamily: false,
            showFontSize: false,
            showInlineCode: false,
            showCodeBlock: false,
            showSubscript: false,
            showSuperscript: false,
            showSmallButton: false,
            showSearchButton: false,
          ),
        ),
        // ── Signature editor ──────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: quill.QuillEditor.basic(
                controller: _sigQuill,
                config: const quill.QuillEditorConfig(
                  padding: EdgeInsets.all(12),
                  placeholder: 'Введите подпись...',
                  scrollable: true,
                  expands: true,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _saving ? null : _saveSignature,
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Сохранить подпись'),
          ),
        ),
      ],
    );
  }

  IconData _folderIcon(MailFolderType type) {
    switch (type) {
      case MailFolderType.inbox:
        return Icons.inbox_outlined;
      case MailFolderType.sent:
        return Icons.send_outlined;
      case MailFolderType.trash:
        return Icons.delete_outline;
      case MailFolderType.drafts:
        return Icons.drafts_outlined;
      case MailFolderType.spam:
        return Icons.report_outlined;
      case MailFolderType.other:
        return Icons.folder_outlined;
    }
  }
}

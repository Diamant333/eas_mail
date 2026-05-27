import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../mail/models/mail_message.dart';
import '../../services/mail_session.dart';

// ── Avatar colors (8 hues, deterministic by sender email hash) ───────────────
const _kAvatarColors = [
  Color(0xFF1565C0), // deep blue
  Color(0xFF2E7D32), // dark green
  Color(0xFF6A1B9A), // purple
  Color(0xFFC62828), // dark red
  Color(0xFF00838F), // teal
  Color(0xFFE65100), // deep orange
  Color(0xFF37474F), // blue grey
  Color(0xFF4527A0), // deep violet
];

Color _avatarColor(String email) {
  final e = email.toLowerCase().trim();
  int hash = 0;
  for (final c in e.codeUnits) {
    hash = (hash * 31 + c) & 0x7FFFFFFF;
  }
  return _kAvatarColors[hash % _kAvatarColors.length];
}

/// Parses "Display Name [email@host]" format.
/// Returns (name, email). If no angle brackets, returns ('', original).
(String name, String email) _parseSender(String from) {
  final match = RegExp(r'^(.+?)\s*<([^>]+)>$').firstMatch(from.trim());
  if (match != null) {
    return (match.group(1)!.trim(), match.group(2)!.trim());
  }
  return ('', from.trim());
}

class MessageListPanel extends StatefulWidget {
  const MessageListPanel({super.key});

  @override
  State<MessageListPanel> createState() => _MessageListPanelState();
}

class _MessageListPanelState extends State<MessageListPanel> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _filterLabelName;
  bool _filterHasAttachments = false;
  bool _pinnedExpanded = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showLabelDialog(BuildContext context, MailMessage message) async {
    final session = context.read<MailSession>();
    final result = await showDialog<({String name, int color})?>(
      context: context,
      builder: (ctx) => _LabelDialogContent(message: message),
    );
    if (result != null) {
      await session.setLabel(
        message,
        labelName: result.name,
        colorValue: result.color,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MailSession>();
    final dateFormat = DateFormat('dd.MM HH:mm');
    final presets = session.settings.labelPresets;

    final allMessages = session.sortedMessages;
    final metaMap = {for (final m in allMessages) session.messageKey(m): session.metaFor(m)};

    final query = _searchQuery.toLowerCase();
    final List<MailMessage> filteredAll = allMessages.where((msg) {
      if (_filterHasAttachments && !msg.hasAttachments) return false;
      if (_filterLabelName != null) {
        final meta = metaMap[session.messageKey(msg)];
        if (meta == null || meta.labelName != _filterLabelName) return false;
      }
      if (query.isNotEmpty) {
        if (!msg.subject.toLowerCase().contains(query) &&
            !msg.from.toLowerCase().contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    final pinned = filteredAll.where((m) => metaMap[session.messageKey(m)]?.pinned == true).toList();
    final regular = filteredAll.where((m) => metaMap[session.messageKey(m)]?.pinned != true).toList();

    // Build the full item list with section headers.
    final items = <_ListItem>[];
    if (pinned.isNotEmpty) {
      items.add(_ListItem.header(pinned: true));
      if (_pinnedExpanded) {
        for (final m in pinned) { items.add(_ListItem.message(m)); }
      }
    }
    if (regular.isNotEmpty) {
      if (pinned.isNotEmpty) items.add(_ListItem.header(pinned: false));
      for (final m in regular) { items.add(_ListItem.message(m)); }
    }

    return Column(
      children: [
        // ── Search + filter bar ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'С вложениями',
                child: SizedBox(
                  height: 48,
                  child: InkWell(
                    onTap: () =>
                        setState(() => _filterHasAttachments = !_filterHasAttachments),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _filterHasAttachments
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        color: _filterHasAttachments
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                      child: Icon(
                        Icons.attach_file,
                        size: 18,
                        color: _filterHasAttachments
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Label filter chips ───────────────────────────────────────────────
        if (presets.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              children: [
                for (final p in presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ColorLabelChip(
                      name: p.name,
                      color: Color(p.color),
                      selected: _filterLabelName == p.name,
                      onSelected: (v) => setState(
                        () => _filterLabelName = v ? p.name : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // ── Message list ─────────────────────────────────────────────────────
        Expanded(
          child: session.loading && filteredAll.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filteredAll.isEmpty
                  ? Center(child: Text(session.error ?? 'Нет писем'))
                  : RefreshIndicator(
                      onRefresh: session.refresh,
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          if (item.isHeader) {
                            return _SectionHeader(
                              label: item.isPinnedHeader ? 'Закреплённые' : 'Сообщения',
                              expanded: item.isPinnedHeader ? _pinnedExpanded : true,
                              showToggle: item.isPinnedHeader,
                              onToggle: item.isPinnedHeader
                                  ? () => setState(() => _pinnedExpanded = !_pinnedExpanded)
                                  : null,
                            );
                          }
                          final msg = item.message!;
                          final key = session.messageKey(msg);
                          final meta = metaMap[key];
                          final selected = session.selectedMessageKey == key;
                          final (senderName, senderEmail) = _parseSender(msg.from);
                          final avatarLabel = senderName.isNotEmpty
                              ? senderName[0].toUpperCase()
                              : senderEmail.isNotEmpty
                                  ? senderEmail[0].toUpperCase()
                                  : '?';
                          final avatarBg = _avatarColor(senderEmail.isNotEmpty ? senderEmail : msg.from);

                          Color? tileColor;
                          if (meta != null && meta.hasLabel) {
                            tileColor = Color(meta.labelColorValue!);
                          } else if (selected) {
                            tileColor = Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.4);
                          }

                          return RepaintBoundary(
                            child: Material(
                              color: tileColor,
                              child: InkWell(
                                onTap: () => Future.microtask(
                                    () => session.selectMessage(msg)),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 6, right: 8),
                                            child: CircleAvatar(
                                              radius: 20,
                                              backgroundColor: avatarBg,
                                              child: Text(
                                                avatarLabel,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        msg.subject,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontWeight: msg.read
                                                              ? FontWeight.normal
                                                              : FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    if (msg.hasAttachments)
                                                      const Padding(
                                                        padding: EdgeInsets.only(
                                                            left: 4),
                                                        child: Icon(
                                                            Icons.attach_file,
                                                            size: 14),
                                                      ),
                                                    if (msg.dateReceived != null)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                                left: 4),
                                                        child: Text(
                                                          dateFormat.format(msg
                                                              .dateReceived!
                                                              .toLocal()),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 2),
                                                // Sender name + email
                                                Text(
                                                  senderName.isNotEmpty
                                                      ? '$senderName  $senderEmail'
                                                      : senderEmail.isNotEmpty
                                                          ? senderEmail
                                                          : msg.from,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        fontWeight: senderName.isNotEmpty
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                ),
                                                if (msg.previewText.isNotEmpty)
                                                  Text(
                                                    msg.previewText,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                Row(
                                                  children: [
                                                    if (meta != null &&
                                                        meta.hasLabel)
                                                      Expanded(
                                                        child: Text(
                                                          meta.labelName!,
                                                          style: Theme.of(
                                                                  context)
                                                              .textTheme
                                                              .labelSmall,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      )
                                                    else
                                                      const Spacer(),
                                                    _TileIconButton(
                                                      icon: meta != null &&
                                                              meta.pinned
                                                          ? Icons.push_pin
                                                          : Icons
                                                              .push_pin_outlined,
                                                      color: meta != null &&
                                                              meta.pinned
                                                          ? Colors.orange
                                                          : null,
                                                      tooltip: meta != null &&
                                                              meta.pinned
                                                          ? 'Открепить'
                                                          : 'Закрепить',
                                                      onPressed: () =>
                                                          session.togglePin(msg),
                                                    ),
                                                    _TileIconButton(
                                                      icon: meta != null &&
                                                              meta.hasLabel
                                                          ? Icons.label
                                                          : Icons.label_outline,
                                                      color: meta != null &&
                                                              meta.hasLabel
                                                          ? Color(meta
                                                                  .labelColorValue!)
                                                              .withValues(
                                                                  alpha: 1)
                                                          : null,
                                                      tooltip: 'Метка',
                                                      onPressed: () =>
                                                          _showLabelDialog(
                                                              context, msg),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Right-edge selection indicator
                                    if (selected)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(width: 4, color: Colors.black87),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

// ── List item model ───────────────────────────────────────────────────────────

class _ListItem {
  const _ListItem._({
    required this.isHeader,
    this.isPinnedHeader = false,
    this.message,
  });

  factory _ListItem.header({required bool pinned}) =>
      _ListItem._(isHeader: true, isPinnedHeader: pinned);
  factory _ListItem.message(MailMessage m) =>
      _ListItem._(isHeader: false, message: m);

  final bool isHeader;
  final bool isPinnedHeader;
  final MailMessage? message;
}

// ── Section header widget ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.expanded,
    required this.showToggle,
    this.onToggle,
  });

  final String label;
  final bool expanded;
  final bool showToggle;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: showToggle ? onToggle : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (showToggle) ...[
              const Spacer(),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Colored label chip (no Material 3 color override) ────────────────────────

class _ColorLabelChip extends StatelessWidget {
  const _ColorLabelChip({
    required this.name,
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final String name;
  final Color color;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onSelected(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.black87 : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

// ── Tile icon button ──────────────────────────────────────────────────────────

class _TileIconButton extends StatelessWidget {
  const _TileIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Icon(
            icon,
            size: 16,
            color: color ?? Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

// ── Label dialog ─────────────────────────────────────────────────────────────

class _LabelDialogContent extends StatefulWidget {
  const _LabelDialogContent({required this.message});

  final MailMessage message;

  @override
  State<_LabelDialogContent> createState() => _LabelDialogContentState();
}

class _LabelDialogContentState extends State<_LabelDialogContent> {
  late final TextEditingController _nameCtrl;
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    final session = context.read<MailSession>();
    final meta = session.metaFor(widget.message);
    final presets = session.settings.labelPresets;
    _nameCtrl = TextEditingController(text: meta.labelName ?? '');
    _selectedColor =
        meta.labelColorValue ?? (presets.isNotEmpty ? presets.first.color : 0xFFFFCDD2);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<MailSession>();
    final meta = session.metaFor(widget.message);
    final presets = session.settings.labelPresets;

    return AlertDialog(
      title: const Text('Метка'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Название метки',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((p) {
                final isSelected = _selectedColor == p.color;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedColor = p.color;
                    if (_nameCtrl.text.isEmpty) _nameCtrl.text = p.name;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Color(p.color),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.check, size: 14,
                                color: Colors.black87),
                          ),
                        Text(
                          p.name,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black87),
                        ),
                      ],
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
        if (meta.hasLabel)
          TextButton(
            onPressed: () async {
              await session.clearLabel(widget.message);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Убрать метку'),
          ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty || _selectedColor == null) return;
            Navigator.pop(context, (name: name, color: _selectedColor!));
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
